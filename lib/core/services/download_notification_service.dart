/// User-visible progress and terminal notifications for model downloads.
///
/// A model can be several gigabytes, so its transfer is paired with a
/// dataSync foreground service while bytes are moving. The service and the
/// progress notification share an id: the plugin's richer per-model content
/// replaces the service's bootstrap notification in place. Progress uses a
/// silent default-importance channel; completion and failure use a separate
/// high-importance channel so they can alert once without turning each progress
/// update into an interruption.
///
/// The mapping from [DownloadTask] to what should appear on screen is a pure
/// function ([downloadNotificationFor]) so it can be unit tested without a
/// platform channel. Android service lifecycle calls go through
/// [ForegroundDownloadBridge], which is injectable in tests.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/transfer_state.dart';
import '../utils/formatters.dart';

/// Progress channel. A new id is used so Android does not retain the old
/// low-importance setting and hide the notification from the shade.
const String kDownloadProgressChannelId = 'model_download_progress';
const String kDownloadProgressChannelName = 'Model download progress';
const String kDownloadProgressChannelDescription =
    'Silent, in-place progress for user-started model downloads.';

/// Terminal channel: a completed or failed download is a one-time alert.
const String kDownloadTerminalChannelId = 'model_download_terminal';
const String kDownloadTerminalChannelName = 'Download results';
const String kDownloadTerminalChannelDescription =
    'One-time alerts when a model download is ready or has failed.';

/// Kept as an alias for clients compiled against the original channel id.
const String kDownloadChannelId = kDownloadProgressChannelId;
const String kDownloadChannelName = kDownloadProgressChannelName;
const String kDownloadChannelDescription =
    kDownloadProgressChannelDescription;

/// Drawable resource name (no `@drawable/` prefix) used as the small icon.
///
/// Must be a white-on-transparent vector: Android masks notification icons to
/// a single colour, so a launcher icon here would render as a white blob.
const String kDownloadIcon = 'ic_stat_download';

/// Action id for the Cancel button. The app receives it back through
/// `onDidReceiveNotificationResponse`.
const String kCancelDownloadAction = 'cancel_download';

/// What a task should put on screen.
enum DownloadNotificationKind {
  /// A live transfer: determinate bar, cancel action.
  progress,

  /// Bytes are down; the checksum is being computed. Indeterminate bar.
  verifying,

  /// Finished and verified. Taps through to the Model Library.
  complete,

  /// Failed. The body carries the reason the user needs.
  failed,

  /// Nothing to show - remove this model's notification if one is up.
  dismiss,
}

bool _isTerminalNotification(DownloadNotificationKind kind) =>
    kind == DownloadNotificationKind.complete ||
    kind == DownloadNotificationKind.failed;

/// Channel policy is kept pure so the two-channel contract can be tested.
String downloadNotificationChannelFor(DownloadNotificationKind kind) =>
    _isTerminalNotification(kind)
        ? kDownloadTerminalChannelId
        : kDownloadProgressChannelId;

/// Progress must remain visible without making a sound; terminal states alert.
Importance downloadNotificationImportanceFor(
  DownloadNotificationKind kind,
) =>
    _isTerminalNotification(kind)
        ? Importance.high
        : Importance.defaultImportance;

Priority downloadNotificationPriorityFor(DownloadNotificationKind kind) =>
    _isTerminalNotification(kind)
        ? Priority.high
        : Priority.defaultPriority;

bool downloadNotificationPlaysSoundFor(DownloadNotificationKind kind) =>
    _isTerminalNotification(kind);

bool downloadNotificationVibratesFor(DownloadNotificationKind kind) =>
    _isTerminalNotification(kind);

/// One notification's worth of content, decided from a [DownloadTask].
@immutable
class DownloadNotificationContent {
  const DownloadNotificationContent({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.percent,
  });

  final int id;
  final DownloadNotificationKind kind;
  final String title;
  final String body;

  /// 0..100, for the progress bar.
  final int percent;

  /// True when the notification should refuse to be swiped away.
  bool get isOngoing =>
      kind == DownloadNotificationKind.progress ||
      kind == DownloadNotificationKind.verifying;

  /// True when the bar should spin instead of filling.
  bool get isIndeterminate => kind == DownloadNotificationKind.verifying;

  /// True when the bar is meaningful at all.
  bool get hasProgressBar => kind != DownloadNotificationKind.dismiss;

  /// True when a Cancel button belongs on it.
  bool get hasCancelAction => isOngoing;

  /// True when the notification should raise a fresh alert rather than being
  /// updated silently. Progress updates are silent; terminal states are not.
  bool get alertsOnce => isOngoing;

  @override
  String toString() => 'DownloadNotificationContent(${kind.name}, $percent%)';
}

/// Stable notification id for a model.
///
/// `String.hashCode` is not guaranteed to be stable across processes, and this
/// id has to be, so that a relaunched app can cancel or replace a notification
/// posted by the previous run. FNV-1a over the code units, masked to the range
/// Android accepts.
int downloadNotificationId(String modelId) {
  var hash = 0x811C9DC5;
  for (final unit in modelId.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash & 0x7FFFFFFF;
}

/// Decides what [task] should show, or null when it should not be announced.
///
/// [modelName] is the human name from the catalogue - `Phi-4-mini-instruct`
/// rather than `phi-4-mini-3.8b` - because a notification is read out of
/// context.
DownloadNotificationContent? downloadNotificationFor(
  DownloadTask task, {
  required String modelName,
}) {
  final id = downloadNotificationId(task.modelId);
  final percent = (task.progress * 100).round().clamp(0, 100);

  switch (task.phase) {
    case DownloadPhase.downloading:
      return DownloadNotificationContent(
        id: id,
        kind: DownloadNotificationKind.progress,
        title: 'Downloading $modelName',
        body: _progressBody(task, percent),
        percent: percent,
      );

    case DownloadPhase.verifying:
      return DownloadNotificationContent(
        id: id,
        kind: DownloadNotificationKind.verifying,
        title: 'Verifying $modelName',
        body: 'Checking the file against its published SHA-256.',
        percent: percent,
      );

    case DownloadPhase.complete:
      return DownloadNotificationContent(
        id: id,
        kind: DownloadNotificationKind.complete,
        title: '$modelName is ready',
        body: 'Downloaded and verified. Tap to open the Model Library.',
        percent: 100,
      );

    case DownloadPhase.failed:
      return DownloadNotificationContent(
        id: id,
        kind: DownloadNotificationKind.failed,
        title: '$modelName could not be downloaded',
        body: task.error ?? 'The download failed.',
        percent: percent,
      );

    // Cancelled: the notification goes away, because the model card already
    // shows the state and a notifications-tray entry for "nothing happened" is
    // noise.
    case DownloadPhase.cancelled:
      return DownloadNotificationContent(
        id: id,
        kind: DownloadNotificationKind.dismiss,
        title: '',
        body: '',
        percent: 0,
      );

    // Nothing worth interrupting for: the user is looking at the confirm
    // dialog, or the task has not started moving yet.
    case DownloadPhase.queued:
    case DownloadPhase.awaitingConfirmation:
      return null;
  }
}

/// `42% · 1.05 GB of 2.49 GB · 12.3 MB/s · 3m 20s left`
///
/// Built from the same formatters the model card uses, so the two can never
/// disagree about how large a file is or how fast it is moving.
String _progressBody(DownloadTask task, int percent) {
  final parts = <String>['$percent%'];

  if (task.totalBytes > 0) {
    parts.add(
      '${formatBytes(task.receivedBytes)} of ${formatBytes(task.totalBytes)}',
    );
  }

  if (task.bytesPerSecond > 0) {
    parts.add(formatSpeed(task.bytesPerSecond));
  }

  final eta = task.eta;
  if (eta != null && eta.inSeconds > 0) {
    parts.add('${formatDuration(eta)} left');
  }

  if (task.fileCount > 1) {
    parts.add('file ${task.fileIndex} of ${task.fileCount}');
  }

  return parts.join(' · ');
}

/// A small, release-visible snapshot of the notification path.
///
/// The download itself must remain independent of Android's notification
/// permission, but a silent failure is not diagnosable from the model card.
@immutable
class DownloadNotificationDiagnostics {
  const DownloadNotificationDiagnostics({
    this.ready = false,
    this.permissionResult = 'not requested',
    this.lastApplyKind,
    this.lastApplyPercent,
    this.lastApplyAt,
    this.lastError,
    this.lastErrorAt,
  });

  final bool ready;
  final String permissionResult;
  final String? lastApplyKind;
  final int? lastApplyPercent;
  final DateTime? lastApplyAt;
  final String? lastError;
  final DateTime? lastErrorAt;

  bool get shouldShowPermissionHint =>
      permissionResult == 'denied' ||
      permissionResult == 'unavailable' ||
      permissionResult == 'error';

  DownloadNotificationDiagnostics copyWith({
    bool? ready,
    String? permissionResult,
    String? lastApplyKind,
    int? lastApplyPercent,
    DateTime? lastApplyAt,
    String? lastError,
    DateTime? lastErrorAt,
  }) =>
      DownloadNotificationDiagnostics(
        ready: ready ?? this.ready,
        permissionResult: permissionResult ?? this.permissionResult,
        lastApplyKind: lastApplyKind ?? this.lastApplyKind,
        lastApplyPercent: lastApplyPercent ?? this.lastApplyPercent,
        lastApplyAt: lastApplyAt ?? this.lastApplyAt,
        lastError: lastError ?? this.lastError,
        lastErrorAt: lastErrorAt ?? this.lastErrorAt,
      );
}

/// Thin platform seam for the user-initiated Android transfer service.
///
/// The service receives the same stable notification id as its first active
/// model; [DownloadNotificationService.apply] then updates that notification
/// with the full progress text and Cancel action.
class ForegroundDownloadBridge {
  ForegroundDownloadBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('library_ai/download_service');

  final MethodChannel _channel;

  Future<void> start(DownloadNotificationContent content) async {
    await _channel.invokeMethod<void>('start', <String, Object>{
      'id': content.id,
      'title': content.title,
      'body': content.body,
      'percent': content.percent,
      'indeterminate': content.isIndeterminate,
    });
  }

  Future<void> stop() async {
    await _channel.invokeMethod<void>('stop');
  }
}

/// Posts and updates the notifications described by
/// [downloadNotificationFor].
///
/// Nothing here is required for a download to work: if the user denies the
/// notification permission, or the plugin is unavailable, the model card stays
/// the source of truth. The diagnostics snapshot still records that outcome so
/// a release build does not fail invisibly.
class DownloadNotificationService extends ChangeNotifier {
  DownloadNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    ForegroundDownloadBridge? foregroundBridge,
    this.onCancelRequested,
    this.onOpenRequested,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _foregroundBridge = foregroundBridge ?? ForegroundDownloadBridge();

  final FlutterLocalNotificationsPlugin _plugin;
  final ForegroundDownloadBridge _foregroundBridge;
  int? _foregroundNotificationId;

  DownloadNotificationDiagnostics _diagnostics =
      const DownloadNotificationDiagnostics();

  DownloadNotificationDiagnostics get diagnostics => _diagnostics;

  void _publishDiagnostics(DownloadNotificationDiagnostics next) {
    _diagnostics = next;
    notifyListeners();
  }

  void _recordError(String source, Object error) {
    final now = DateTime.now();
    _publishDiagnostics(_diagnostics.copyWith(
      lastError: '$source: $error',
      lastErrorAt: now,
    ));
    // Release breadcrumbs are intentional: otherwise the failure this row is
    // meant to diagnose disappears in the exact build users run.
    debugPrint('Library AI notification $source failed: $error');
  }

  /// Called with a model id when the user taps **Cancel** on a notification.
  ///
  /// The action is declared with `showsUserInterface: true`, so Android brings
  /// the app forward and this runs on the main isolate with the download
  /// manager in reach - which is the only place cancellation can be applied.
  final void Function(String modelId)? onCancelRequested;

  /// Called when the user taps the notification body of a finished download.
  final void Function(String modelId)? onOpenRequested;

  /// Model ids with a notification on screen, and what it last said.
  ///
  /// The kind is remembered so that a terminal notification is posted exactly
  /// once: tasks stay in the manager's map after they finish, so without this a
  /// later progress update for some *other* model would resurrect a "ready"
  /// notification the user had already swiped away.
  final Map<String, DownloadNotificationKind> _posted = {};

  /// Set once the plugin is initialised. Until then every call is a no-op, so
  /// a download started before startup finished cannot throw.
  bool _ready = false;

  /// Initialises the plugin and clears anything a previous run left behind.
  ///
  /// The cleanup matters: a killed process cannot resume the transfer, so a
  /// stale progress bar must not sit in the shade showing movement that stopped.
  /// Relaunching means the `.part` file has been swept, so the notification goes
  /// too.
  /// Nothing else in the app posts notifications, which is what makes
  /// [FlutterLocalNotificationsPlugin.cancelAll] safe here.
  Future<void> initialize() async {
    _publishDiagnostics(_diagnostics.copyWith(ready: false));
    const settings = InitializationSettings(
      android: AndroidInitializationSettings(kDownloadIcon),
    );

    try {
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _handleResponse,
      );
      await _createNotificationChannels();
      await _plugin.cancelAll();
      _posted.clear();
      _ready = true;
      _publishDiagnostics(_diagnostics.copyWith(ready: true));
    } catch (error) {
      // A missing platform implementation (tests, an unsupported device) must
      // never take the download down with it.
      _ready = false;
      _publishDiagnostics(_diagnostics.copyWith(ready: false));
      _recordError('initialize', error);
      return;
    }

    await _handleLaunch();
  }

  /// Asks for the notification permission on Android 13+.
  ///
  /// Called when the user starts a download rather than at startup: that is the
  /// moment the notification becomes useful, and an app that demands a
  /// permission before doing anything is an app people decline. A refusal is
  /// not an error - the download proceeds and simply stays in the app.
  Future<bool> ensurePermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) {
        _publishDiagnostics(
          _diagnostics.copyWith(permissionResult: 'unavailable'),
        );
        return false;
      }
      final requested = await android.requestNotificationsPermission();
      final enabled = await android.areNotificationsEnabled();
      final granted = enabled ?? requested ?? false;
      _publishDiagnostics(_diagnostics.copyWith(
        permissionResult: granted ? 'granted' : 'denied',
      ));
      return granted;
    } catch (error) {
      _publishDiagnostics(
        _diagnostics.copyWith(permissionResult: 'error'),
      );
      _recordError('permission request', error);
      return false;
    }
  }

  /// Promotes the first live transfer to the Android foreground service.
  ///
  /// The bridge is deliberately isolated from [apply], leaving pure mapping
  /// tests and unsupported platforms independent of Android service APIs.
  Future<void> syncForegroundDownload(
    DownloadTask? task, {
    required String modelName,
  }) async {
    final canRun = task != null &&
        (task.phase == DownloadPhase.downloading ||
            task.phase == DownloadPhase.verifying);
    if (!canRun) {
      if (_foregroundNotificationId == null) return;
      try {
        await _foregroundBridge.stop();
        _foregroundNotificationId = null;
      } catch (error) {
        _recordError('foreground service stop', error);
      }
      return;
    }

    final liveTask = task;
    if (liveTask == null) return;
    final content = downloadNotificationFor(liveTask, modelName: modelName);
    if (content == null || _foregroundNotificationId == content.id) return;

    try {
      await _foregroundBridge.start(content);
      _foregroundNotificationId = content.id;
    } catch (error) {
      _recordError('foreground service start', error);
    }
  }

  /// Shows, updates, or removes the notification for [task].
  Future<void> apply(DownloadTask task, {required String modelName}) async {
    final content = downloadNotificationFor(task, modelName: modelName);
    final now = DateTime.now();
    _publishDiagnostics(_diagnostics.copyWith(
      lastApplyKind: content?.kind.name ?? 'none',
      lastApplyPercent: content?.percent ?? 0,
      lastApplyAt: now,
    ));
    if (content == null) return;

    if (content.kind == DownloadNotificationKind.dismiss) {
      await dismiss(task.modelId);
      return;
    }

    if (!_ready) return;

    // A terminal state is announced once. A live transfer is not: it is the
    // same notification being updated in place, which is the whole point.
    final terminal = content.kind == DownloadNotificationKind.complete ||
        content.kind == DownloadNotificationKind.failed;
    if (terminal && _posted[task.modelId] == content.kind) return;

    try {
      await _plugin.show(
        id: content.id,
        title: content.title,
        body: content.body,
        notificationDetails: NotificationDetails(
          android: _androidDetails(content),
        ),
        payload: task.modelId,
      );
      _posted[task.modelId] = content.kind;
    } catch (error) {
      _recordError('show', error);
    }
  }

  /// Removes the notification for [modelId], if any.
  Future<void> dismiss(String modelId) async {
    _posted.remove(modelId);
    if (!_ready) return;
    try {
      await _plugin.cancel(id: downloadNotificationId(modelId));
    } catch (error) {
      // Best effort; the download itself is not coupled to this cosmetic path.
      _recordError('cancel', error);
    }
  }

  Future<void> _createNotificationChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        kDownloadProgressChannelId,
        kDownloadProgressChannelName,
        description: kDownloadProgressChannelDescription,
        importance: Importance.defaultImportance,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        kDownloadTerminalChannelId,
        kDownloadTerminalChannelName,
        description: kDownloadTerminalChannelDescription,
        importance: Importance.high,
      ),
    );
  }

  AndroidNotificationDetails _androidDetails(
    DownloadNotificationContent content,
  ) {
    final terminal = _isTerminalNotification(content.kind);
    return AndroidNotificationDetails(
      downloadNotificationChannelFor(content.kind),
      terminal ? kDownloadTerminalChannelName : kDownloadProgressChannelName,
      channelDescription: terminal
          ? kDownloadTerminalChannelDescription
          : kDownloadProgressChannelDescription,
      icon: kDownloadIcon,
      importance: downloadNotificationImportanceFor(content.kind),
      priority: downloadNotificationPriorityFor(content.kind),
      // The progress channel is silent even at default importance. A terminal
      // state gets the platform's normal alert once; subsequent progress never
      // re-alerts because onlyAlertOnce remains true for ongoing updates.
      playSound: downloadNotificationPlaysSoundFor(content.kind),
      enableVibration: downloadNotificationVibratesFor(content.kind),
      category: content.kind == DownloadNotificationKind.failed
          ? AndroidNotificationCategory.error
          : AndroidNotificationCategory.progress,
      ongoing: content.isOngoing,
      autoCancel: !content.isOngoing,
      onlyAlertOnce: content.alertsOnce,
      showProgress: content.hasProgressBar,
      maxProgress: 100,
      progress: content.percent,
      indeterminate: content.isIndeterminate,
      actions: content.hasCancelAction
          ? <AndroidNotificationAction>[
              const AndroidNotificationAction(
                kCancelDownloadAction,
                'Cancel',
                // Bring the app forward so the request is handled on the main
                // isolate, where the download manager lives. The notification
                // itself is left alone; the manager's own terminal state
                // removes it, so a cancel that races with completion still
                // shows the truth.
                showsUserInterface: true,
                cancelNotification: false,
              ),
            ]
          : null,
    );
  }

  /// Handles the app being *launched* by a notification.
  ///
  /// `onDidReceiveNotificationResponse` only fires while the app is running, so
  /// a tap that starts the process has to be picked up from the launch details
  /// instead. Both paths run through the same callbacks.
  Future<void> _handleLaunch() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return;
      final response = details.notificationResponse;
      if (response == null) return;
      _handleResponse(response);
    } catch (error) {
      _recordError('read launch details', error);
    }
  }

  void _handleResponse(NotificationResponse response) {
    final modelId = response.payload;
    if (modelId == null || modelId.isEmpty) return;

    if (response.actionId == kCancelDownloadAction) {
      onCancelRequested?.call(modelId);
      return;
    }

    onOpenRequested?.call(modelId);
  }
}
