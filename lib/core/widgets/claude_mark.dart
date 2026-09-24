import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/claude_tokens.dart';

/// The radial-spike mark that anchors the interface.
///
/// Claude's mark is a burst of twelve tapered spokes around a solid core, and it
/// does the brand's identity work in three places in this shell: the home
/// screen, the assistant's avatar on every reply, and the sidebar header.
///
/// It is drawn rather than shipped as an asset: a painter scales to any size
/// without a raster asset per density, it takes the accent colour from the
/// tokens so it tracks the theme, and it keeps the repository free of another
/// binary. The proportions were measured off the reference capture — twelve
/// spokes at 30° intervals, a core of roughly a quarter of the radius, spokes
/// about a fifth of the radius thick with rounded tips, and an alternating
/// length so the burst does not read as a gear.
class ClaudeMark extends StatelessWidget {
  const ClaudeMark({
    super.key,
    this.size = 44,
    this.color,
    this.semanticLabel = 'Library AI',
  });

  final double size;

  /// Defaults to the accent. Pass a token colour to override.
  final Color? color;

  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      label: semanticLabel,
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _MarkPainter(
            color: color ?? tokens.primary,
            spokes: 12,
            // Every third spoke is a touch shorter, matching the reference.
            shortSpokeRatio: 0.84,
          ),
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({
    required this.color,
    required this.spokes,
    required this.shortSpokeRatio,
  });

  final Color color;
  final int spokes;
  final double shortSpokeRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final paint = Paint()..color = color;

    // Core.
    canvas.drawCircle(center, radius * 0.26, paint);

    // Arms: a rounded bar from just outside the core to the tip, so the inner
    // end tucks under the core circle and the outer end keeps a rounded cap.
    final armWidth = radius * 0.21;
    for (var i = 0; i < spokes; i++) {
      final angle = (2 * math.pi / spokes) * i;
      final long = i % 3 != 0;
      final tip = radius * (long ? 1.0 : shortSpokeRatio);
      final inner = radius * 0.10;
      final length = tip - inner;

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(inner, -armWidth / 2, length, armWidth),
          Radius.circular(armWidth / 2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) =>
      old.color != color ||
      old.spokes != spokes ||
      old.shortSpokeRatio != shortSpokeRatio;
}

/// The circular button used in the top bar: a flat disc on the canvas with a
/// hairline edge, optionally filled with the accent.
///
/// The reference uses these for the back/menu control and the compose control
/// rather than the borderless Material [IconButton], and the difference is
/// visible enough to matter — a bare glyph in a 56 dp bar reads as unanchored.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.filled = false,
    this.size = 32,
    this.iconSize = 18,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  /// Accent fill with an [ClaudeColors.onPrimary] glyph — the compose button.
  final bool filled;

  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final background = filled ? tokens.primary : tokens.canvas;
    final foreground = filled ? tokens.onPrimary : tokens.ink;

    final button = Material(
      color: onPressed == null ? tokens.surfaceSoft : background,
      shape: CircleBorder(
        side: BorderSide(color: filled ? Colors.transparent : tokens.hairline),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: iconSize,
            color: onPressed == null ? tokens.muted : foreground,
          ),
        ),
      ),
    );

    // The visual disc is 32 dp; the touch target is not. Wrap rather than grow
    // the disc, so the bar keeps the reference's proportions.
    final target = SizedBox(
      width: ClaudeSpacing.minTouchTarget,
      height: ClaudeSpacing.minTouchTarget,
      child: Center(child: button),
    );

    return tooltip == null ? target : Tooltip(message: tooltip!, child: target);
  }
}
