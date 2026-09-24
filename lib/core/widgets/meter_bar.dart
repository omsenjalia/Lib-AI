import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A horizontal progress/level bar with a threshold-aware colour.
///
/// Used for two things that look alike but mean different things:
///
///  * the chat context-window meter, where crossing 75% turns amber and 90%
///    turns red, and
///  * the per-model storage bars in Settings, which pass explicit thresholds of
///    null so the colour stays neutral.
///
/// [isIndeterminate] is for the "waiting for the first token" state, where the
/// true value is unknown and a fake percentage would be a lie.
class MeterBar extends StatelessWidget {
  const MeterBar({
    super.key,
    required this.value,
    this.height = 6,
    this.warningThreshold,
    this.criticalThreshold,
    this.isIndeterminate = false,
    this.backgroundColor,
    this.animate = true,
  });

  /// 0..1. Clamped, so a caller that miscounts cannot paint outside the track.
  final double value;

  final double height;

  /// Fraction at or above which the bar turns amber.
  final double? warningThreshold;

  /// Fraction at or above which the bar turns red.
  final double? criticalThreshold;

  final bool isIndeterminate;
  final Color? backgroundColor;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final track = backgroundColor ??
        (scheme.brightness == Brightness.dark
            ? AppColors.surfaceHigh
            : AppColors.lightSurfaceHigh);

    if (isIndeterminate) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(
          minHeight: height,
          backgroundColor: track,
          valueColor: AlwaysStoppedAnimation<Color>(_colorFor(context, value)),
        ),
      );
    }

    final clamped = value.clamp(0.0, 1.0);
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Stack(
        children: [
          Container(height: height, color: track),
          FractionallySizedBox(
            widthFactor: clamped,
            child: Container(height: height, color: _colorFor(context, clamped)),
          ),
        ],
      ),
    );

    if (!animate) return bar;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: clamped, end: clamped),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      builder: (context, _, child) => child!,
      child: bar,
    );
  }

  Color _colorFor(BuildContext context, double fraction) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = scheme.brightness == Brightness.light;

    if (criticalThreshold != null && fraction >= criticalThreshold!) {
      return isLight ? AppColors.lightError : AppColors.meterCritical;
    }
    if (warningThreshold != null && fraction >= warningThreshold!) {
      return AppColors.meterWarning;
    }
    return isLight ? AppColors.lightAccent : AppColors.accent;
  }
}

/// The context-window meter shown above the composer.
///
/// Kept as its own widget because the readout is opinionated in two ways the
/// brief asks for: the percentage is always visible (a bare bar gives no sense
/// of how close to the limit you are), and the estimate is labelled as an
/// estimate until the tokeniser confirms it.
class ContextMeter extends StatelessWidget {
  const ContextMeter({
    super.key,
    required this.usedTokens,
    required this.maxTokens,
    this.isEstimate = true,
    this.compact = false,
  });

  final int usedTokens;
  final int maxTokens;
  final bool isEstimate;
  final bool compact;

  double get fraction => maxTokens <= 0 ? 0 : usedTokens / maxTokens;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final percent = (fraction * 100).clamp(0, 100).round();
    final nearLimit = fraction >= 0.75;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MeterBar(
          value: fraction,
          height: compact ? 4 : 5,
          warningThreshold: 0.75,
          criticalThreshold: 0.90,
        ),
        if (!compact) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '$percent% of ${_formatTokens(maxTokens)} context',
                style: TextStyle(
                  fontSize: 10.5,
                  color: nearLimit
                      ? AppColors.meterWarning
                      : AppColors.textSecondary,
                  fontWeight: nearLimit ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              const Spacer(),
              Text(
                isEstimate ? 'estimated' : 'exact',
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.brightness == Brightness.dark
                      ? AppColors.textSecondary.withValues(alpha: 0.7)
                      : AppColors.lightTextSecondary.withValues(alpha: 0.7),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  static String _formatTokens(int tokens) {
    if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(1)}M';
    if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(0)}k';
    return '$tokens';
  }
}
