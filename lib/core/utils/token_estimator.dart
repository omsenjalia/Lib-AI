import '../constants/app_constants.dart';

/// Token accounting for the context-window meter.
///
/// There are two numbers the UI needs, and they have different fidelities:
///
///  * **Exact** counts, from the model's own vocabulary via
///    `fllamaTokenize`. These are authoritative but cost a model load, so they
///    are computed when a turn completes and when a conversation is opened.
///  * **Estimated** counts, from a characters-per-token ratio, used while a
///    response is streaming so the meter moves live without tokenising on every
///    callback.
///
/// The meter labels which one is on screen, so it never presents a guess as a
/// measurement.
abstract final class TokenEstimator {
  /// Rough token count for [text].
  ///
  /// Models in this catalogue tokenise English at roughly 4 characters per
  /// token. Code and LaTeX tokenise worse (more punctuation, more symbols), so
  /// those are weighted denser rather than pretending one ratio fits all.
  static int estimate(String text) {
    if (text.isEmpty) return 0;

    final codeFences = RegExp(r'```[\s\S]*?```').allMatches(text).length;
    final mathSpans = RegExp(r'\$\$[\s\S]*?\$\$').allMatches(text).length;

    var ratio = AppConstants.averageCharsPerToken;
    if (codeFences > 0) ratio -= 0.8; // code: ~3.2 chars/token
    if (mathSpans > 0) ratio -= 0.4; // math: ~3.6 chars/token
    if (ratio < 2.5) ratio = 2.5;

    return (text.length / ratio).ceil();
  }

  /// Estimated tokens for a whole conversation's worth of message bodies.
  static int estimateConversation(Iterable<String> messageBodies) {
    var total = 0;
    for (final body in messageBodies) {
      total += estimate(body);
      // Per-message role/turn overhead in the chat template.
      total += 4;
    }
    return total;
  }

  /// Fraction of the context window in use, clamped to 0..1.
  static double usageFraction(int usedTokens, int contextLength) {
    if (contextLength <= 0) return 0;
    final fraction = usedTokens / contextLength;
    if (fraction < 0) return 0;
    if (fraction > 1) return 1;
    return fraction;
  }

  /// True once the meter should turn amber (brief: >75% full).
  static bool isWarning(int usedTokens, int contextLength) =>
      usageFraction(usedTokens, contextLength) > 0.75;

  /// True once the meter should turn red (brief: >90% full).
  static bool isCritical(int usedTokens, int contextLength) =>
      usageFraction(usedTokens, contextLength) > 0.90;

  /// How many tokens remain before the window is full.
  static int remaining(int usedTokens, int contextLength) {
    final left = contextLength - usedTokens;
    return left < 0 ? 0 : left;
  }
}
