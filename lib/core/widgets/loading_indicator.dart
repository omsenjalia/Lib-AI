import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A three-dot pulse in the assistant's place while the model is loading or the
/// first token is still on its way.
///
/// Deliberately not a spinner. On this device the model load can take tens of
/// seconds, and the surrounding text (see [LoadingIndicator.label]) tells the
/// user which stage it is in - a spinner alone would look identical whether the
/// app were working or hung.
class LoadingIndicator extends StatefulWidget {
  const LoadingIndicator({super.key, this.label, this.compact = false});

  /// Stage text, e.g. "Loading model into memory…". Null hides the line.
  final String? label;

  final bool compact;

  @override
  State<LoadingIndicator> createState() => _LoadingIndicatorState();
}

class _LoadingIndicatorState extends State<LoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.brightness == Brightness.dark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 26,
          height: 10,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => CustomPaint(
              painter: _DotsPainter(
                progress: _controller.value,
                color: AppColors.accent,
              ),
            ),
          ),
        ),
        if (widget.label != null) ...[
          SizedBox(width: widget.compact ? 8 : 12),
          Flexible(
            child: Text(
              widget.label!,
              style: TextStyle(
                fontSize: widget.compact ? 11 : 12,
                color: secondary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dotCount = 3;
    final radius = size.height / 2 - 1;
    final spacing = size.width / dotCount;

    for (var i = 0; i < dotCount; i++) {
      // Each dot peaks a third of a cycle after the previous one.
      final phase = (progress - i / dotCount) % 1.0;
      final wave = (phase < 0.5 ? phase * 2 : (1 - phase) * 2).clamp(0.0, 1.0);
      final opacity = 0.28 + 0.72 * wave;

      canvas.drawCircle(
        Offset(spacing * (i + 0.5), size.height / 2),
        radius * (0.75 + 0.25 * wave),
        Paint()..color = color.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_DotsPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
