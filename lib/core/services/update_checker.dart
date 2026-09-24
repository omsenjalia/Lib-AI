import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../data/database.dart';
import '../models/model_catalogue.dart';
import '../models/transfer_state.dart';
import 'connectivity_service.dart';
import 'huggingface_client.dart';

/// Detects when a model repository has moved on from what is on the device.
///
/// Design rules, all from the brief and all enforced here:
///
///  * **Offline is silent.** A failed check when there is no connection is
///    skipped without an error, a message, or any UI change.
///  * **Throttled to once per 24 h per model**, measured from the stored
///    `lastCheckedAt`, so reconnecting repeatedly does not hammer the API.
///  * **Wi-Fi gate.** The 27B is never checked over mobile data.
///  * **It never downloads anything.** Its entire output is a flag and a
///    timestamp. Replacing a model file requires the user to tap Update.
class UpdateChecker {
  UpdateChecker({
    required AppDatabase database,
    required HuggingFaceClient client,
    required ConnectivityService connectivity,
  })  : _db = database,
        _client = client,
        _connectivity = connectivity;

  final AppDatabase _db;
  final HuggingFaceClient _client;
  final ConnectivityService _connectivity;

  final _controller =
      StreamController<Map<String, ModelUpdateInfo>>.broadcast();
  final Map<String, ModelUpdateInfo> _state = {};

  /// Latest known update state, keyed by catalogue model id.
  Stream<Map<String, ModelUpdateInfo>> get updatesStream => _controller.stream;
  Map<String, ModelUpdateInfo> get updates => Map.unmodifiable(_state);

  ModelUpdateInfo? forModel(String modelId) => _state[modelId];

  /// True when at least one model has a pending update, for the dismissible
  /// banner. Returns the first such model's name for the message.
  ModelUpdateInfo? get firstPending {
    for (final entry in _state.values) {
      if (entry.updateAvailable) return entry;
    }
    return null;
  }

  /// Checks every model that is installed on the device.
  ///
  /// [force] bypasses the 24 h throttle; it is used when the user taps
  /// "Check now" in Settings, never on a foreground event.
  Future<void> checkAll(
    List<CatalogueModel> models, {
    bool force = false,
  }) async {
    if (!await _connectivity.isOnline()) return;

    final installed = await _db.allInstallations();
    if (installed.isEmpty) return;

    for (final model in models) {
      final hasInstall =
          installed.any((i) => i.modelId == model.id);
      if (!hasInstall) continue;
      await checkOne(model, force: force);
    }
  }

  /// Checks a single model, applying the throttle and the Wi-Fi rule.
  Future<void> checkOne(CatalogueModel model, {bool force = false}) async {
    // Rule: offline is a silent skip, not an error.
    if (!await _connectivity.isOnline()) return;

    // Rule: never poll the 27B's repository over mobile data.
    if (model.wifiOnly &&
        !await _connectivity.isOnUnmeteredConnection()) {
      return;
    }

    final existing = await _db.updateCheck(model.id);
    if (!force && existing != null) {
      final age = DateTime.now().difference(existing.lastCheckedAt);
      if (age < AppConstants.updateCheckThrottle) return;
    }

    final install = await _db.installation(model.id);
    if (install == null) return;

    try {
      final remote = await _client.fetchRepoState(model.ggufRepoId);

      // Compare at file granularity where possible: HuggingFace exposes the
      // LFS object id per file, and for LFS objects that id is the SHA-256 of
      // the content - the same value stored on the install record. That makes
      // this a genuine "has this file changed" test rather than "has the repo
      // been touched".
      final remoteOid = remote.oidFor(install.fileName);
      final localOid = install.sha256;

      final bool changed;
      if (remoteOid != null && localOid != null && localOid.isNotEmpty) {
        changed = remoteOid.toLowerCase() != localOid.toLowerCase();
      } else {
        // Fall back to the repository commit hash when per-file data is absent.
        final remoteSha = remote.sha;
        final localSha = install.repoSha;
        changed = remoteSha != null &&
            localSha != null &&
            remoteSha != localSha;
      }

      final info = ModelUpdateInfo(
        modelId: model.id,
        updateAvailable: changed,
        lastCheckedAt: DateTime.now(),
        remoteSha: remote.sha,
        remoteLastModified: remote.lastModified,
      );

      await _db.upsertUpdateCheck(
        ModelUpdateChecksCompanion.insert(
          modelId: model.id,
          lastCheckedAt: info.lastCheckedAt!,
          remoteSha: Value(remote.sha),
          remoteLastModified: Value(remote.lastModified),
          updateAvailable: Value(changed),
        ),
      );

      _publish(info);
    } catch (error) {
      // A metadata call failing is not worth interrupting study for. Record it
      // so the model library can show "last checked: failed" on demand, and
      // otherwise stay out of the way.
      final isNetwork = error is DioException;
      _publish(
        ModelUpdateInfo(
          modelId: model.id,
          updateAvailable: false,
          lastCheckedAt: DateTime.now(),
          error: isNetwork ? 'Could not reach HuggingFace' : '$error',
        ),
      );
    }
  }

  /// Reads persisted state into memory so the UI shows badges immediately on
  /// launch, before any network call has happened.
  Future<void> hydrate(List<CatalogueModel> models) async {
    final rows = await _db.watchUpdateChecks().first;
    for (final row in rows) {
      _state[row.modelId] = ModelUpdateInfo(
        modelId: row.modelId,
        updateAvailable: row.updateAvailable,
        lastCheckedAt: row.lastCheckedAt,
        remoteSha: row.remoteSha,
        remoteLastModified: row.remoteLastModified,
      );
    }
    if (!_controller.isClosed && _state.isNotEmpty) {
      _controller.add(Map.unmodifiable(_state));
    }
  }

  void _publish(ModelUpdateInfo info) {
    _state[info.modelId] = info;
    if (!_controller.isClosed) _controller.add(Map.unmodifiable(_state));
  }

  void dispose() {
    _controller.close();
  }
}

/// Debug-only helper so a developer can see what the checker is doing without
/// attaching a debugger.
void logUpdateCheck(String message) {
  if (kDebugMode) {
    debugPrint('[LibraryAI/update] $message');
  }
}
