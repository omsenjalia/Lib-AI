import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

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
    final scheme = Theme.of(context).colorScheme;
    final isLight = scheme.brightness == Brightness.light;
    final (foreground, background) = _colors(isLight);

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
            style: TextStyle(
              color: foreground,
              fontSize: dense ? 10 : 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color) _colors(bool isLight) {
    switch (tone) {
      case BadgeTone.neutral:
        return isLight
            ? (AppColors.lightTextSecondary, AppColors.lightSurfaceHigh)
            : (AppColors.textSecondary, AppColors.surfaceHigh);
      case BadgeTone.accent:
        return isLight
            ? (AppColors.lightAccent, AppColors.lightAccentMuted)
            : (AppColors.accent, AppColors.accentMuted);
      case BadgeTone.danger:
        return isLight
            ? (AppColors.lightError, const Color(0xFFF7E4E4))
            : (AppColors.error, const Color(0xFF3A1F1F));
      case BadgeTone.success:
        return isLight
            ? (AppColors.lightSuccess, const Color(0xFFE4EEDE))
            : (AppColors.success, const Color(0xFF1F2E1A));
      case BadgeTone.muted:
        return isLight
            ? (AppColors.lightTextSecondary, AppColors.lightSurfaceHigh)
            : (AppColors.textSecondary, AppColors.surface);
    }
  }
}
