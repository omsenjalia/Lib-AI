import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_ai/core/models/transfer_state.dart';
import 'package:library_ai/core/services/download_notification_service.dart';

/// The download notification is the only progress a user gets for a 7 GB
/// transfer, so its content is asserted rather than eyeballed: what it says at
/// each phase, and that the actions on it are the ones that make sense there.
///
/// Only the pure mapping is tested. Posting the notification needs a platform
/// channel, and there is nothing in the decision logic that needs one.
void main() {
  group('notification diagnostics', () {
    test('only show a shade hint after permission is unavailable', () {
      expect(
        const DownloadNotificationDiagnostics().shouldShowPermissionHint,
        isFalse,
      );
      for (final result in ['denied', 'unavailable', 'error']) {
        expect(
          const DownloadNotificationDiagnostics()
              .copyWith(permissionResult: result)
              .shouldShowPermissionHint,
          isTrue,
        );
      }
      expect(
        const DownloadNotificationDiagnostics()
            .copyWith(permissionResult: 'granted')
            .shouldShowPermissionHint,
        isFalse,
      );
    });
  });

  DownloadTask task({
    DownloadPhase phase = DownloadPhase.downloading,
    int totalBytes = 2491874688,
    int receivedBytes = 1046587368,
    double bytesPerSecond = 0,
    Duration? eta,
    String? error,
    int fileIndex = 1,
    int fileCount = 1,
  }) =>
      DownloadTask(
        modelId: 'phi-4-mini-3.8b',
        quant: 'Q4_K_M',
        fileName: 'microsoft_Phi-4-mini-instruct-Q4_K_M.gguf',
        totalBytes: totalBytes,
        receivedBytes: receivedBytes,
        phase: phase,
        bytesPerSecond: bytesPerSecond,
        eta: eta,
        error: error,
        fileIndex: fileIndex,
        fileCount: fileCount,
      );

  group('notification ids', () {
    test('are stable, so a relaunched app can cancel a stale notification', () {
      // Hard-coded values on purpose: if the hash changes, every notification
      // posted by the previous run becomes un-cancellable, and this test is the
      // only thing that would notice.
      expect(downloadNotificationId('phi-4-mini-3.8b'), 1563396809);
      expect(downloadNotificationId('qwen3.8-27b'), 225382487);
      expect(downloadNotificationId('mimo-v2.6-9b'), 1527652498);
    });

    test('are the same on every call', () {
      final first = downloadNotificationId('qwythos-9b-v2');
      final second = downloadNotificationId('qwythos-9b-v2');
      expect(first, second);
      expect(first, 44543741);
    });

    test('differ between models, and stay inside the range Android accepts', () {
      const ids = [
        'qwen3.8-27b',
        'mimo-v2.6-9b',
        'qwythos-9b-v2',
        'qwythos-9b-mythos-5-1m',
        'qwen3.5-9b-opus-4.6-distill',
        'phi-4-mini-3.8b',
      ];
      final computed = ids.map(downloadNotificationId).toList();

      expect(computed.toSet(), hasLength(ids.length));
      expect(computed.every((id) => id >= 0 && id <= 0x7FFFFFFF), isTrue);
    });
  });

  group('a live transfer', () {
    test('is a determinate, ongoing, cancellable notification', () {
      final content = downloadNotificationFor(
        task(),
        modelName: 'Phi-4-mini-instruct',
      )!;

      expect(content.kind, DownloadNotificationKind.progress);
      expect(content.title, 'Downloading Phi-4-mini-instruct');
      expect(content.percent, 42);
      expect(content.isOngoing, isTrue);
      expect(content.isIndeterminate, isFalse);
      expect(content.hasProgressBar, isTrue);
      expect(content.hasCancelAction, isTrue);
      // Progress updates must not buzz on every few hundred kilobytes.
      expect(content.alertsOnce, isTrue);
    });

    test('answers "how much longer" when that is knowable', () {
      final content = downloadNotificationFor(
        task(bytesPerSecond: 12300000, eta: const Duration(seconds: 200)),
        modelName: 'Phi-4-mini-instruct',
      )!;

      expect(content.body, '42% · 1.05 GB of 2.49 GB · 12.30 MB/s · 3m 20s left');
    });

    test('omits the rate and ETA rather than printing placeholders', () {
      // `--` belongs on a quiet model card, not in the notification shade.
      final content = downloadNotificationFor(
        task(eta: Duration.zero),
        modelName: 'Phi-4-mini-instruct',
      )!;

      expect(content.body, '42% · 1.05 GB of 2.49 GB');
      expect(content.body, isNot(contains('--')));
      expect(content.body, isNot(contains('left')));
    });

    test('says which file it is on when a projector is included', () {
      final content = downloadNotificationFor(
        task(fileIndex: 2, fileCount: 2),
        modelName: 'Qwythos-9B-v2',
      )!;

      expect(content.body, endsWith('file 2 of 2'));
    });

    test('survives a server that sends no Content-Length', () {
      final content = downloadNotificationFor(
        task(totalBytes: 0, receivedBytes: 1024),
        modelName: 'Phi-4-mini-instruct',
      )!;

      expect(content.percent, 0);
      expect(content.body, '0%');
    });

    test('never reports more than 100 percent', () {
      final content = downloadNotificationFor(
        task(totalBytes: 1000, receivedBytes: 5000),
        modelName: 'Phi-4-mini-instruct',
      )!;

      expect(content.percent, 100);
    });
  });

  group('verifying', () {
    test('is ongoing but indeterminate, and still cancellable', () {
      final content = downloadNotificationFor(
        task(phase: DownloadPhase.verifying, receivedBytes: 2491874688),
        modelName: 'Phi-4-mini-instruct',
      )!;

      expect(content.kind, DownloadNotificationKind.verifying);
      expect(content.title, 'Verifying Phi-4-mini-instruct');
      expect(content.body, contains('SHA-256'));
      expect(content.isOngoing, isTrue);
      expect(content.isIndeterminate, isTrue);
      expect(content.hasCancelAction, isTrue);
    });
  });

  group('terminal states', () {
    test('a finished download is dismissible and points at the library', () {
      final content = downloadNotificationFor(
        task(phase: DownloadPhase.complete, receivedBytes: 2491874688),
        modelName: 'Phi-4-mini-instruct',
      )!;

      expect(content.kind, DownloadNotificationKind.complete);
      expect(content.title, 'Phi-4-mini-instruct is ready');
      expect(content.body, contains('Model Library'));
      expect(content.percent, 100);
      expect(content.isOngoing, isFalse);
      expect(content.hasCancelAction, isFalse);
      // A completion is worth a fresh alert, unlike a progress update.
      expect(content.alertsOnce, isFalse);
    });

    test('a failure carries the reason and what to do about it', () {
      final content = downloadNotificationFor(
        task(
          phase: DownloadPhase.failed,
          error: 'Downloaded file failed its integrity check.',
        ),
        modelName: 'Phi-4-mini-instruct',
      )!;

      expect(content.kind, DownloadNotificationKind.failed);
      expect(content.title, 'Phi-4-mini-instruct could not be downloaded');
      expect(content.body, 'Downloaded file failed its integrity check.');
      expect(content.hasCancelAction, isFalse);
      expect(content.isOngoing, isFalse);
    });

    test('a failure with no message still says something useful', () {
      final content = downloadNotificationFor(
        task(phase: DownloadPhase.failed),
        modelName: 'Phi-4-mini-instruct',
      )!;

      expect(content.body, isNotEmpty);
      expect(content.body, isNot(contains('null')));
    });

    test('a cancellation dismisses the notification', () {
      final content = downloadNotificationFor(
        task(phase: DownloadPhase.cancelled),
        modelName: 'Phi-4-mini-instruct',
      )!;

      expect(content.kind, DownloadNotificationKind.dismiss);
      expect(content.isOngoing, isFalse);
      expect(content.hasProgressBar, isFalse);
    });
  });

  group('phases that should stay silent', () {
    test('queued and awaiting-confirmation announce nothing', () {
      expect(
        downloadNotificationFor(
          task(phase: DownloadPhase.queued),
          modelName: 'Phi-4-mini-instruct',
        ),
        isNull,
      );
      expect(
        downloadNotificationFor(
          task(phase: DownloadPhase.awaitingConfirmation),
          modelName: 'Phi-4-mini-instruct',
        ),
        isNull,
      );
    });
  });

  group('notification channels', () {
    test('progress and verification use the silent default channel', () {
      for (final kind in [
        DownloadNotificationKind.progress,
        DownloadNotificationKind.verifying,
      ]) {
        expect(
          downloadNotificationChannelFor(kind),
          kDownloadProgressChannelId,
        );
        expect(
          downloadNotificationImportanceFor(kind),
          Importance.defaultImportance,
        );
        expect(
          downloadNotificationPriorityFor(kind),
          Priority.defaultPriority,
        );
        expect(downloadNotificationPlaysSoundFor(kind), isFalse);
        expect(downloadNotificationVibratesFor(kind), isFalse);
      }
      final content = downloadNotificationFor(
        task(),
        modelName: 'Phi-4-mini-instruct',
      )!;
      expect(content.alertsOnce, isTrue);
      expect(content.hasCancelAction, isTrue);
    });

    test('complete and failed use their own alerting channel', () {
      for (final kind in [
        DownloadNotificationKind.complete,
        DownloadNotificationKind.failed,
      ]) {
        expect(
          downloadNotificationChannelFor(kind),
          kDownloadTerminalChannelId,
        );
        expect(downloadNotificationImportanceFor(kind), Importance.high);
        expect(downloadNotificationPriorityFor(kind), Priority.high);
        expect(downloadNotificationPlaysSoundFor(kind), isTrue);
        expect(downloadNotificationVibratesFor(kind), isTrue);
      }
    });
  });
}
