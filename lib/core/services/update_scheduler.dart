import 'dart:async';

import 'connectivity_service.dart';
import 'catalogue_repository.dart';
import 'settings_service.dart';
import 'update_checker.dart';

/// Runs the model update check at the moments the brief allows, and at no
/// others.
///
/// The behaviour being implemented, stated precisely because it is easy to get
/// subtly wrong:
///
///  * A check runs **when connectivity is regained**, not on a timer and not on
///    every foregrounding. The trigger is the transition offline -> online.
///  * A check also runs **once at startup**, if online, so a device that has
///    been online the whole time still learns about updates.
///  * Nothing here downloads. The checker's only output is a flag that drives a
///    badge and the dismissible banner.
///  * Offline is not an error path. `checkAll` returns without doing anything
///    and without recording a failure, which is what keeps the airplane-mode
///    requirement satisfied.
///
/// The 24 h per-model throttle lives inside [UpdateChecker], not here, so that
/// a manually triggered check from Settings can bypass it while these automatic
/// triggers cannot.
class UpdateScheduler {
  UpdateScheduler({
    required ConnectivityService connectivity,
    required UpdateChecker checker,
    required CatalogueRepository catalogue,
    required SettingsService settings,
  })  : _connectivity = connectivity,
        _checker = checker,
        _catalogue = catalogue,
        _settings = settings;

  final ConnectivityService _connectivity;
  final UpdateChecker _checker;
  final CatalogueRepository _catalogue;
  final SettingsService _settings;

  StreamSubscription<bool>? _subscription;
  bool _wasOnline = false;
  bool _disposed = false;

  /// Begins watching connectivity. Safe to call once at startup.
  Future<void> start() async {
    _wasOnline = await _connectivity.isOnline();
    if (_wasOnline) {
      // Delay the startup check slightly so it never competes with the first
      // frame or with model loading for the disk and network.
      unawaited(
        Future<void>.delayed(const Duration(seconds: 5), _runCheck),
      );
    }

    _subscription = _connectivity.onlineChanges.listen((online) {
      final regained = online && !_wasOnline;
      _wasOnline = online;
      if (regained) unawaited(_runCheck());
    });
  }

  /// Manual trigger from Settings' "Check for updates now".
  ///
  /// [force] bypasses the throttle; it is the only caller that does, and it is
  /// always the direct result of a user tap.
  Future<void> checkNow({bool force = true}) async {
    final settings = await _settings.load();
    if (!settings.autoUpdateCheckEnabled && !force) return;
    await _runCheck(force: force);
  }

  Future<void> _runCheck({bool force = false}) async {
    if (_disposed) return;
    try {
      final settings = await _settings.load();
      if (!settings.autoUpdateCheckEnabled && !force) return;

      final catalogue = await _catalogue.load();
      await _checker.checkAll(catalogue.models, force: force);
    } catch (_) {
      // A metadata check is a convenience. If it fails, the app carries on
      // exactly as it was: no dialog, no error state, no failed badge.
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
  }
}
