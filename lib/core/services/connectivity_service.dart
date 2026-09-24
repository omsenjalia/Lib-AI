import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Network state, and the basis for two rules in this app:
///
///  * The 27B download is **hard blocked** on mobile data. Not warned about -
///    blocked, in [DownloadManager].
///  * Every auto-update check is **silently skipped** when offline. Offline is
///    a normal state for this app, not an error, and it must never surface a
///    message or degrade any UI.
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  /// Emits the current online state immediately, then on every change.
  Stream<bool> get onlineChanges async* {
    yield await isOnline();
    yield* _connectivity.onConnectivityChanged.map(_isOnlineResult);
  }

  /// True when any transport is available.
  Future<bool> isOnline() async {
    try {
      return _isOnlineResult(await _connectivity.checkConnectivity());
    } catch (_) {
      // If the platform channel is unavailable we cannot prove we are offline.
      // Treating this as online is the safer default: the only things gated on
      // it are downloads and update checks, both of which fail safely.
      return true;
    }
  }

  /// True only on Wi-Fi or Ethernet.
  ///
  /// This is the gate for the 27B download. Mobile data and VPN-only
  /// connections both return false, which is the intended conservative
  /// behaviour: the consequence of a false negative is that the user is asked
  /// to find Wi-Fi, whereas a false positive would burn gigabytes of their
  /// mobile allowance.
  Future<bool> isOnUnmeteredConnection() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return _hasUnmetered(results);
    } catch (_) {
      return false;
    }
  }

  static bool _isOnlineResult(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  static bool _hasUnmetered(List<ConnectivityResult> results) =>
      results.contains(ConnectivityResult.wifi) ||
      results.contains(ConnectivityResult.ethernet);

  /// A short label for the settings/diagnostic surfaces.
  static String describe(List<ConnectivityResult> results) {
    if (results.isEmpty || results.contains(ConnectivityResult.none)) {
      return 'Offline';
    }
    if (_hasUnmetered(results)) return 'Wi-Fi';
    if (results.contains(ConnectivityResult.mobile)) return 'Mobile data';
    return results.first.name;
  }
}
