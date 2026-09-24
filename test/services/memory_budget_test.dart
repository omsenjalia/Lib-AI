import 'package:flutter_test/flutter_test.dart';
import 'package:library_ai/core/services/memory_budget.dart';

/// The preflight exists to turn a native allocation failure into a message, so
/// the arithmetic that decides "refuse or try" is worth pinning down: a check
/// that refuses too eagerly blocks models that would have worked.
void main() {
  group('parseMemAvailable', () {
    // Trimmed from a real /proc/meminfo on Android 15.
    const sample = '''
MemTotal:        7594584 kB
MemFree:          281932 kB
MemAvailable:    2417664 kB
Buffers:           41204 kB
Cached:          2548160 kB
''';

    test('reads MemAvailable in bytes', () {
      expect(
        MemoryBudget.parseMemAvailable(sample),
        2417664 * 1024,
      );
    });

    test('returns null when the line is absent', () {
      expect(
        MemoryBudget.parseMemAvailable('MemTotal: 7594584 kB\n'),
        isNull,
      );
    });

    test('returns null when the value is not a number', () {
      expect(MemoryBudget.parseMemAvailable('MemAvailable:   lots kB\n'), isNull);
    });

    test('tolerates the line arriving last without a trailing newline', () {
      expect(
        MemoryBudget.parseMemAvailable('MemFree: 1 kB\nMemAvailable: 2048 kB'),
        2048 * 1024,
      );
    });
  });

  group('peakRequirementBytes', () {
    test('is the model requirement when nothing else is resident', () {
      expect(
        MemoryBudget.peakRequirementBytes(requirementGb: 2.5),
        2500000000,
      );
    });

    test('adds the model being swapped out', () {
      // llama.cpp keeps the previous model for around two minutes, so the peak
      // during a swap holds both.
      expect(
        MemoryBudget.peakRequirementBytes(
          requirementGb: 2.0,
          alsoResidentGb: 1.5,
        ),
        3500000000,
      );
    });

    test('leaves the requirement alone at or below the recommended context', () {
      expect(
        MemoryBudget.peakRequirementBytes(
          requirementGb: 2.0,
          contextLength: 4096,
          recommendedContextLength: 4096,
        ),
        2000000000,
      );
      expect(
        MemoryBudget.peakRequirementBytes(
          requirementGb: 2.0,
          contextLength: 2048,
          recommendedContextLength: 4096,
        ),
        2000000000,
      );
    });

    test('adds KV headroom above the recommended context', () {
      // 4096 tokens over the recommended length is four 1024-token steps.
      final bytes = MemoryBudget.peakRequirementBytes(
        requirementGb: 2.0,
        contextLength: 8192,
        recommendedContextLength: 4096,
      );
      expect(
        bytes,
        2000000000 + 4 * MemoryBudget.kvBytesPer1024Tokens,
      );
    });

    test('rounds the KV allowance up rather than down', () {
      final bytes = MemoryBudget.peakRequirementBytes(
        requirementGb: 0,
        contextLength: 1025,
        recommendedContextLength: 1024,
      );
      expect(bytes, MemoryBudget.kvBytesPer1024Tokens);
    });
  });

  group('fits', () {
    test('accepts a requirement covered with headroom to spare', () {
      expect(
        MemoryBudget.fits(available: 3000000000, required: 2500000000),
        isTrue,
      );
    });

    test('refuses a requirement that only just fits', () {
      // 2.5 GB needed against 2.6 GB free is inside the headroom, and this is
      // the case that ends in a native abort rather than a caught exception.
      expect(
        MemoryBudget.fits(available: 2600000000, required: 2500000000),
        isFalse,
      );
    });

    test('refuses outright when there is less free than required', () {
      expect(
        MemoryBudget.fits(available: 1000000000, required: 2500000000),
        isFalse,
      );
    });
  });
}
