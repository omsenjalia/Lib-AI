import 'package:flutter_test/flutter_test.dart';
import 'package:library_ai/core/constants/app_constants.dart';

/// The engine divides the requested context across four llama.cpp slots, so the
/// figure the user picks in Settings is not the figure a conversation gets.
/// Everything that budgets prompt tokens depends on this arithmetic being
/// right, and the failure mode when it is wrong is invisible: the server
/// context-shifts and drops the system prompt without saying anything.
void main() {
  group('perChatContextLength', () {
    test('takes a quarter of the requested total', () {
      expect(AppConstants.perChatContextLength(8192), 2048);
      expect(AppConstants.perChatContextLength(4096), 1024);
      expect(AppConstants.perChatContextLength(32768), 8192);
      expect(AppConstants.perChatContextLength(262144), 65536);
    });

    test('floors a total that does not divide evenly', () {
      // Rounding down is the safe direction: a budget built on the padded
      // figure would let the prompt overrun the slot.
      expect(AppConstants.perChatContextLength(5000), 1250);
      expect(AppConstants.perChatContextLength(2049), 512);
    });

    test('never reports a window below the llama.cpp minimum', () {
      // Below 1024 the engine pads the slot up to 256, so 256 is the real
      // floor and a smaller answer would make the budget uselessly strict.
      expect(AppConstants.perChatContextLength(1024), 256);
      expect(AppConstants.perChatContextLength(512), 256);
    });

    test('never exceeds what was asked for', () {
      for (final requested in [1, 100, 255, 300, 512, 1000, 8192, 262144]) {
        expect(
          AppConstants.perChatContextLength(requested),
          lessThanOrEqualTo(requested),
          reason: 'requested $requested',
        );
      }
    });

    test('passes nonsense through rather than inventing a window', () {
      expect(AppConstants.perChatContextLength(0), 0);
      expect(AppConstants.perChatContextLength(-1), -1);
    });

    test('the default context still leaves room for a conversation', () {
      // 0.70 of the per-chat window is the prompt budget; a slot of a few
      // hundred tokens would make every answer a one-liner.
      final perChat =
          AppConstants.perChatContextLength(AppConstants.defaultContextLength);
      expect(perChat, greaterThanOrEqualTo(256));
    });
  });
}
