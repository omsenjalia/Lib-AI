import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../data/database.dart';
import '../models/model_catalogue.dart';
import 'storage_paths.dart';

/// Moves installed model files to the currently selected storage location.
///
/// Each file is streamed into a `.move.part` sibling and SHA-256 checked before
/// promotion. An installation row is switched only after its model and any
/// projector are both present at the destination; source files are removed
/// only after that database update. The pending-id list is persisted in
/// SettingEntries so an interrupted move can be resumed after process death.
class ModelMigrationService {
  ModelMigrationService({
    required AppDatabase database,
    required StoragePaths storagePaths,
  })  : _database = database,
        _storagePaths = storagePaths;

  static const pendingMoveSettingKey = 'pending_model_storage_moves';

  final AppDatabase _database;
  final StoragePaths _storagePaths;
  bool _cancelRequested = false;
  bool _running = false;

  Future<bool> get hasPendingMove async => (await _pendingIds()).isNotEmpty;

  void cancel() => _cancelRequested = true;

  Future<ModelMigrationReport> moveExistingModels({
    required List<ModelInstallation> installations,
    required ModelCatalogue catalogue,
    required void Function(ModelMigrationProgress progress) onProgress,
  }) async {
    final ids = installations.map((installation) => installation.modelId).toList();
    await _savePendingIds(ids);
    return _resume(
      catalogue: catalogue,
      onProgress: onProgress,
    );
  }

  Future<ModelMigrationReport> resumePendingMoves({
    required ModelCatalogue catalogue,
    required void Function(ModelMigrationProgress progress) onProgress,
  }) =>
      _resume(catalogue: catalogue, onProgress: onProgress);

  Future<ModelMigrationReport> _resume({
    required ModelCatalogue catalogue,
    required void Function(ModelMigrationProgress progress) onProgress,
  }) async {
    if (_running) {
      return const ModelMigrationReport(
        movedModelIds: [],
        failures: [],
        cancelled: false,
      );
    }
    _running = true;
    _cancelRequested = false;
    final failures = <ModelMigrationFailure>[];
    final moved = <String>[];
    try {
      final ids = await _pendingIds();
      for (var index = 0; index < ids.length; index++) {
        if (_cancelRequested) break;
        final modelId = ids[index];
        final installation = await _database.installation(modelId);
        if (installation == null) {
          await _removePendingId(modelId);
          continue;
        }
        final model = catalogue.byId(modelId);
        if (model == null) {
          failures.add(
            ModelMigrationFailure(
              modelId: modelId,
              modelName: modelId,
              reason: 'This model is no longer in the bundled catalogue.',
            ),
          );
          continue;
        }

        onProgress(
          ModelMigrationProgress(
            modelId: modelId,
            modelName: model.displayName,
            modelIndex: index + 1,
            modelCount: ids.length,
            copiedBytes: 0,
            totalBytes: installation.totalBytes,
          ),
        );
        try {
          final changed = await _moveOne(
            installation: installation,
            model: model,
            onProgress: (copiedBytes) => onProgress(
              ModelMigrationProgress(
                modelId: modelId,
                modelName: model.displayName,
                modelIndex: index + 1,
                modelCount: ids.length,
                copiedBytes: copiedBytes,
                totalBytes: installation.totalBytes,
              ),
            ),
          );
          if (changed) moved.add(modelId);
          await _removePendingId(modelId);
        } on ModelStorageCancelledException {
          _cancelRequested = true;
          break;
        } catch (error) {
          failures.add(
            ModelMigrationFailure(
              modelId: modelId,
              modelName: model.displayName,
              reason: '$error',
            ),
          );
        }
      }
      return ModelMigrationReport(
        movedModelIds: moved,
        failures: failures,
        cancelled: _cancelRequested,
      );
    } finally {
      _running = false;
    }
  }

  Future<bool> _moveOne({
    required ModelInstallation installation,
    required CatalogueModel model,
    required void Function(int copiedBytes) onProgress,
  }) async {
    QuantOption? quant;
    for (final option in model.quants) {
      if (option.quant == installation.quant) {
        quant = option;
        break;
      }
    }
    final expectedModelHash = quant?.sha256 ?? installation.sha256;
    if (expectedModelHash == null || expectedModelHash.isEmpty) {
      throw StateError('No SHA-256 checksum is available for '
          '${installation.fileName}.');
    }

    final modelTarget = _withMovePart(
      await _storagePaths.modelFileTarget(
        installation.modelId,
        installation.fileName,
      ),
    );
    final existingModelTarget = await _existingLocator(modelTarget);
    final modelDestination = existingModelTarget == installation.localPath
        ? installation.localPath
        : await _storagePaths.copyVerifiedModelFile(
            sourceLocator: installation.localPath,
            destination: modelTarget,
            expectedSha256: expectedModelHash,
            onProgress: onProgress,
            isCancelled: () => _cancelRequested,
          );

    String? mmprojDestination;
    final oldMmproj = installation.mmprojPath;
    if (oldMmproj != null) {
      final projector = model.mmproj;
      if (projector == null || projector.sha256 == null) {
        throw StateError('No projector checksum is available for '
            '${p.basename(oldMmproj)}.');
      }
      final mmprojTarget = _withMovePart(
        await _storagePaths.modelFileTarget(
          installation.modelId,
          projector.fileName,
        ),
      );
      final existingMmprojTarget = await _existingLocator(mmprojTarget);
      mmprojDestination = existingMmprojTarget == oldMmproj
          ? oldMmproj
          : await _storagePaths.copyVerifiedModelFile(
              sourceLocator: oldMmproj,
              destination: mmprojTarget,
              expectedSha256: projector.sha256!,
              onProgress: onProgress,
              isCancelled: () => _cancelRequested,
            );
    }

    final changed = modelDestination != installation.localPath ||
        mmprojDestination != oldMmproj;
    if (!changed) return false;

    final modelBytes = await _storagePaths.modelFileSize(modelDestination);
    final mmprojBytes = mmprojDestination == null
        ? 0
        : await _storagePaths.modelFileSize(mmprojDestination);
    await _database.upsertInstallation(
      ModelInstallationsCompanion.insert(
        modelId: installation.modelId,
        quant: installation.quant,
        fileName: installation.fileName,
        localPath: modelDestination,
        mmprojPath: Value(mmprojDestination),
        sizeBytes: modelBytes,
        sha256: Value(expectedModelHash),
        repoSha: Value(installation.repoSha),
        repoLastModified: Value(installation.repoLastModified),
        totalBytes: modelBytes + mmprojBytes,
        downloadedAt: Value(installation.downloadedAt),
      ),
    );

    if (installation.localPath != modelDestination) {
      await _tryDelete(installation.localPath);
    }
    if (oldMmproj != null && oldMmproj != mmprojDestination) {
      await _tryDelete(oldMmproj);
    }
    return true;
  }

  ModelFileTarget _withMovePart(ModelFileTarget target) {
    if (target.isSaf) {
      return ModelFileTarget.saf(
        parentUri: target.parentUri!,
        fileName: target.fileName,
        partSuffix: 'move.part',
      );
    }
    return ModelFileTarget.local(
      path: target.path!,
      fileName: target.fileName,
      partSuffix: 'move.part',
    );
  }

  Future<String?> _existingLocator(ModelFileTarget target) async {
    try {
      return await _storagePaths.modelFileLocator(target);
    } catch (_) {
      return null;
    }
  }

  Future<void> _tryDelete(String locator) async {
    try {
      await _storagePaths.deleteModelFile(locator);
    } catch (_) {
      // A stale duplicate is preferable to losing the only adopted copy.
    }
  }

  Future<List<String>> _pendingIds() async {
    final value = await _database.setting(pendingMoveSettingKey);
    if (value == null || value.isEmpty) return const [];
    try {
      return (jsonDecode(value) as List<dynamic>).cast<String>().toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _savePendingIds(List<String> ids) async {
    final uniqueIds = ids.toSet().toList(growable: false);
    if (uniqueIds.isEmpty) {
      await _database.deleteSetting(pendingMoveSettingKey);
    } else {
      await _database.putSetting(pendingMoveSettingKey, jsonEncode(uniqueIds));
    }
  }

  Future<void> _removePendingId(String id) async {
    final ids = await _pendingIds();
    ids.remove(id);
    await _savePendingIds(ids);
  }
}

class ModelMigrationProgress {
  const ModelMigrationProgress({
    required this.modelId,
    required this.modelName,
    required this.modelIndex,
    required this.modelCount,
    required this.copiedBytes,
    required this.totalBytes,
  });

  final String modelId;
  final String modelName;
  final int modelIndex;
  final int modelCount;
  final int copiedBytes;
  final int totalBytes;
}

class ModelMigrationFailure {
  const ModelMigrationFailure({
    required this.modelId,
    required this.modelName,
    required this.reason,
  });

  final String modelId;
  final String modelName;
  final String reason;
}

class ModelMigrationReport {
  const ModelMigrationReport({
    required this.movedModelIds,
    required this.failures,
    required this.cancelled,
  });

  final List<String> movedModelIds;
  final List<ModelMigrationFailure> failures;
  final bool cancelled;
}
