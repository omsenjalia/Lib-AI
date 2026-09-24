/// Google-Play-style progress notifications for model downloads.
///
/// A model is up to 7.3 GB. Without a notification the only progress the user
/// has is the model card, which means they have to hold the app open for twenty
/// minutes - and on a phone that also means the screen stays on. The
/// notification is therefore not decoration: it is what makes a large download
/// practical, and it is modelled on the Play Store's own download notification
/// because that is the shape every Android user already knows:
///
///  * one ongoing notification per download, with a real determinate bar and a
///    percentage, updated in place rather than posted repeatedly;
///  * a body that answers "how much longer" - bytes done, transfer rate, ETA;
///  * a **Cancel** action while the transfer is live;
///  * a terminal notification that replaces the progress one: "ready" or
///    "failed", which taps through to the Model Library.
///
/// Two deliberate differences from Play, both because this app is not Play:
///
///  * There is no download *service*. Cancelling stops the transfer; nothing
///    resumes in the background if the process dies. What is left behind is
///    cleaned up on the next launch, together with the `.part` file.
///  * The channel is created at [Importance.low] with no sound. A 7 GB
///    download that buzzes every few seconds would be worse than no
///    notification at all. A user who wants an alert can raise the channel's
///    importance in Android's own settings.
///
/// The mapping from [DownloadTask] to what should appear on screen is a pure
/// function ([downloadNotificationFor]) so it can be unit tested without a
/// platform channel; [DownloadNotificationService] is a thin wrapper that only
/// performs the calls.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/transfer_state.dart';
import '../utils/formatters.dart';

/// Channel id. Bumping this would orphan the user's per-channel settings, so
/// it is deliberately stable and versioned by name only.
const String kDownloadChannelId = 'model_downloads';

const String kDownloadChannelName = 'Model downloads';
const String kDownloadChannelDescription =
    'Progress for model downloads, and a note when one is ready to use.';

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

/// Posts and updates the notifications described by
/// [downloadNotificationFor].
///
/// Nothing here is required for a download to work: if the user denies the
/// notification permission, or the plugin is unavailable, every method is a
/// silent no-op and the model card remains the source of truth.
class DownloadNotificationService {
  DownloadNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    this.onCancelRequested,
    this.onOpenRequested,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

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
  /// The cleanup matters: this app has no background download service, so if
  /// the process is killed mid-transfer the notification would otherwise sit in
  /// the shade forever showing a progress bar that will never move. Relaunching
  /// means the `.part` file has been swept, so the notification must go too.
  /// Nothing else in the app posts notifications, which is what makes
  /// [FlutterLocalNotificationsPlugin.cancelAll] safe here.
  Future<void> initialize() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings(kDownloadIcon),
    );

    try {
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _handleResponse,
      );
      await _plugin.cancelAll();
      _posted.clear();
      _ready = true;
    } catch (error) {
      // A missing platform implementation (tests, an unsupported device) must
      // never take the download down with it.
      _ready = false;
      if (kDebugMode) {
        debugPrint('Download notifications unavailable: $error');
      }
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
      if (android == null) return false;
      return await android.requestNotificationsPermission() ?? false;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Notification permission request failed: $error');
      }
      return false;
    }
  }

  /// Shows, updates, or removes the notification for [task].
  Future<void> apply(DownloadTask task, {required String modelName}) async {
    final content = downloadNotificationFor(task, modelName: modelName);
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

    _posted[task.modelId] = content.kind;
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
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Could not post download notification: $error');
      }
    }
  }

  /// Removes the notification for [modelId], if any.
  Future<void> dismiss(String modelId) async {
    _posted.remove(modelId);
    if (!_ready) return;
    try {
      await _plugin.cancel(id: downloadNotificationId(modelId));
    } catch (_) {
      // Best effort; a stale notification is cosmetic.
    }
  }

  AndroidNotificationDetails _androidDetails(
    DownloadNotificationContent content,
  ) {
    return AndroidNotificationDetails(
      kDownloadChannelId,
      kDownloadChannelName,
      channelDescription: kDownloadChannelDescription,
      icon: kDownloadIcon,
      // Low importance: no sound, no heads-up. The bar in the shade is the
      // point, not an interruption.
      importance: Importance.low,
      priority: Priority.low,
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
      if (kDebugMode) {
        debugPrint('Could not read notification launch details: $error');
      }
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
