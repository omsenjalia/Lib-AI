import 'package:flutter/material.dart';

import '../theme/claude_tokens.dart';

/// A horizontal progress/level bar with a threshold-aware colour.
///
/// Used by the per-model storage bars in Settings, which pass explicit
/// thresholds of null so the colour stays neutral, and by any other level
/// read-out that needs the same treatment. The chat's context meter is drawn in
/// the top bar rather than here — see `ClaudeTopBar`.
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
    final tokens = context.tokens;
    final track = backgroundColor ?? tokens.surfaceStrong;

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
    final tokens = context.tokens;
    if (criticalThreshold != null && fraction >= criticalThreshold!) {
      return tokens.errorText;
    }
    if (warningThreshold != null && fraction >= warningThreshold!) {
      return tokens.warning;
    }
    return tokens.primary;
  }
}
