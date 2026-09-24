import 'package:flutter/material.dart';

import '../theme/claude_tokens.dart';

/// The small pills used across the model cards and the chat header.
///
/// Every badge in the app routes through here so that "High RAM" on the model
/// card and "Wi-Fi only" in the download sheet cannot drift apart visually.
enum BadgeTone {
  /// Neutral information: quant label, parameter count.
  neutral,

  /// Amber. Used for the design language's accent states, e.g. "Update
  /// available" and "Wi-Fi only".
  accent,

  /// Red. Reserved for genuinely blocking conditions, currently only the 27B's
  /// "High RAM" badge.
  danger,

  /// Green. Installed / up to date.
  success,

  /// Muted. Vision-capable, which is informational rather than a state.
  muted,
}

/// A compact status pill.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.tone = BadgeTone.neutral,
    this.icon,
    this.dense = false,
  });

  final String label;
  final BadgeTone tone;
  final IconData? icon;

  /// Smaller padding and text, for use inside dense rows.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (foreground, background) = _colors(context);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(dense ? 4 : 6),
        border: Border.all(color: foreground.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 10 : 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: ClaudeType.caption.copyWith(
              color: foreground,
              fontSize: dense ? 10 : 11,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  /// Foreground and wash for each tone.
  ///
  /// Every wash is the tone's own hue at low alpha over the surface, which is
  /// what keeps five badge kinds from introducing five new colours — the
  /// single-accent rule does not allow a palette of pastels.
  (Color, Color) _colors(BuildContext context) {
    final tokens = context.tokens;
    switch (tone) {
      case BadgeTone.neutral:
        return (tokens.muted, tokens.surfaceStrong);
      case BadgeTone.accent:
        return (
          tokens.primaryActive,
          tokens.primary.withValues(alpha: 0.14),
        );
      case BadgeTone.danger:
        return (
          tokens.errorText,
          tokens.error.withValues(alpha: 0.14),
        );
      case BadgeTone.success:
        return (
          tokens.success,
          tokens.success.withValues(alpha: 0.14),
        );
      case BadgeTone.muted:
        return (tokens.muted, tokens.surfaceCard);
    }
  }
}
