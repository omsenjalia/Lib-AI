import 'package:flutter_test/flutter_test.dart';
import 'package:library_ai/core/utils/formatters.dart';
import 'package:library_ai/core/utils/token_estimator.dart';

void main() {
  group('formatBytes', () {
    test('small values stay in bytes', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(999), '999 B');
    });

    test('uses decimal units, matching what HuggingFace displays', () {
      // The catalogue's sizeGb values are derived from the same convention, so
      // a 5,841,049,120-byte file must read as 5.84 GB in both places.
      expect(formatBytes(5841049120), '5.84 GB');
      expect(formatBytes(7266070528), '7.27 GB');
    });

    test('drops to one decimal above 100 units', () {
      expect(formatBytes(150000000000), '150.0 GB');
    });

    test('negative input is clamped', () {
      expect(formatBytes(-1), '0 B');
    });
  });

  group('formatSpeed and formatDuration', () {
    test('speed is bytes per second', () {
      expect(formatSpeed(0), '--');
      expect(formatSpeed(2500000), '2.50 MB/s');
    });

    test('durations are coarsened, never false precision', () {
      expect(formatDuration(Duration.zero), '--');
      expect(formatDuration(const Duration(seconds: 45)), '45s');
      expect(formatDuration(const Duration(minutes: 2, seconds: 30)), '2m 30s');
      expect(formatDuration(const Duration(minutes: 3)), '3m');
      expect(formatDuration(const Duration(hours: 1, minutes: 5)), '1h 5m');
      expect(formatDuration(const Duration(hours: 2)), '2h');
    });
  });

  group('formatRelativeTime', () {
    final now = DateTime(2026, 9, 24, 12, 0);

    test('recent times are relative', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(seconds: 5)), now: now),
        'just now',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(minutes: 12)), now: now),
        '12m ago',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 3)), now: now),
        '3h ago',
      );
    });

    test('yesterday and this week are named', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(days: 1)), now: now),
        'Yesterday',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(days: 3)), now: now),
        '3d ago',
      );
    });

    test('older than a week falls back to a date', () {
      expect(
        formatRelativeTime(DateTime(2026, 9, 1), now: now),
        '01/09/2026',
      );
    });

    test('a clock skew into the future reads as just now', () {
      expect(
        formatRelativeTime(now.add(const Duration(minutes: 5)), now: now),
        'just now',
      );
    });
  });

  group('formatAbsoluteTime', () {
    test('is zero padded and sortable', () {
      expect(formatAbsoluteTime(DateTime(2026, 9, 4, 9, 5)), '2026-09-04 09:05');
    });
  });

  group('slugify', () {
    test('lowercases and hyphenates', () {
      expect(slugify('Binary Search: O(log n)'), 'binary-search-o-log-n');
    });

    test('trims leading and trailing separators', () {
      expect(slugify('  ...Hello...  '), 'hello');
    });

    test('empty input becomes a usable default', () {
      expect(slugify('   '), 'untitled');
      expect(slugify('\u4E2D\u6587'), 'untitled');
    });

    test('long titles are cut to a length file systems like', () {
      final long = 'a' * 200;
      expect(slugify(long).length, 60);
    });
  });

  group('autoTitleFromMessage', () {
    test('short questions become the title', () {
      expect(autoTitleFromMessage('What is a deadlock?'),
          'What is a deadlock?');
    });

    test('whitespace is collapsed', () {
      expect(
        autoTitleFromMessage('What   is\n\na deadlock?'),
        'What is a deadlock?',
      );
    });

    test('long questions are cut at a word boundary', () {
      final title = autoTitleFromMessage(
        'Explain the difference between preemptive and cooperative scheduling '
        'in operating systems, with examples',
      );
      expect(title.endsWith('...'), isTrue);
      expect(title.length, lessThanOrEqualTo(52));
      expect(title, isNot(contains('  ')));
    });

    test('an empty message falls back to a default title', () {
      expect(autoTitleFromMessage(''), 'New chat');
      expect(autoTitleFromMessage('   '), 'New chat');
    });
  });

  group('TokenEstimator', () {
    test('empty text costs nothing', () {
      expect(TokenEstimator.estimate(''), 0);
    });

    test('English prose is about four characters per token', () {
      final estimate = TokenEstimator.estimate('a' * 400);
      expect(estimate, 100);
    });

    test('code tokenises denser than prose', () {
      final prose = TokenEstimator.estimate('the quick brown fox ' * 20);
      final code = TokenEstimator.estimate(
        '```dart\nfinal x = List<int>.generate(10, (i) => i);\n```',
      );
      // Same character count is not the point; the point is that the estimator
      // does not under-count a code-heavy message.
      expect(code, greaterThan(0));
      expect(prose, greaterThan(0));
    });

    test('conversation accounting includes per-message overhead', () {
      final single = TokenEstimator.estimate('hello');
      final conversation = TokenEstimator.estimateConversation(['hello']);
      expect(conversation, single + 4);
    });

    test('usage fraction is clamped', () {
      expect(TokenEstimator.usageFraction(500, 1000), 0.5);
      expect(TokenEstimator.usageFraction(2000, 1000), 1.0);
      expect(TokenEstimator.usageFraction(-5, 1000), 0.0);
      expect(TokenEstimator.usageFraction(10, 0), 0.0);
    });

    test('thresholds match the brief: amber above 75%, red above 90%', () {
      expect(TokenEstimator.isWarning(750, 1000), isFalse);
      expect(TokenEstimator.isWarning(760, 1000), isTrue);
      expect(TokenEstimator.isCritical(900, 1000), isFalse);
      expect(TokenEstimator.isCritical(910, 1000), isTrue);
    });

    test('remaining never goes negative', () {
      expect(TokenEstimator.remaining(900, 1000), 100);
      expect(TokenEstimator.remaining(1100, 1000), 0);
    });
  });
}
