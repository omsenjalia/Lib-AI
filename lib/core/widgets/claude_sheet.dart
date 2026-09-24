import 'package:flutter/material.dart';

import '../theme/claude_tokens.dart';

/// The 32 × 4 dp grab handle at the top of every bottom sheet.
///
/// Drawn explicitly rather than left to `showDragHandle`, because Material's own
/// handle is a different size and colour from the tokens and the sheet widgets
/// in this app need the exact one.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: ClaudeSpacing.xs),
      child: Center(
        child: Container(
          width: 32,
          height: 4,
          decoration: BoxDecoration(
            color: context.tokens.mutedSoft,
            borderRadius: BorderRadius.circular(ClaudeRadius.full),
          ),
        ),
      ),
    );
  }
}

/// A sheet title, centred under the handle.
class SheetTitle extends StatelessWidget {
  const SheetTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ClaudeSpacing.md,
        ClaudeSpacing.sm,
        ClaudeSpacing.md,
        ClaudeSpacing.xs,
      ),
      child: Align(
        alignment: Alignment.center,
        child: Text(
          title,
          style: ClaudeType.titleSmall.copyWith(color: context.tokens.bodyStrong),
        ),
      ),
    );
  }
}

/// The uppercase group header used by the sidebar and by Settings.
///
/// 12 px, uppercase, 1.5 px tracking, muted — the same treatment in both places
/// so the two lists read as one system.
class ClaudeSectionHeader extends StatelessWidget {
  const ClaudeSectionHeader({
    super.key,
    required this.title,
    this.padding = const EdgeInsets.fromLTRB(
      ClaudeSpacing.md,
      ClaudeSpacing.md,
      ClaudeSpacing.md,
      ClaudeSpacing.xs,
    ),
  });

  final String title;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        title.toUpperCase(),
        style: ClaudeType.captionCaps.copyWith(color: context.tokens.muted),
      ),
    );
  }
}

/// A flat, hairline-separated row: label on the left, value or control on the
/// right. Used by Settings and by the sheets, so the two agree on height and
/// padding.
class ClaudeRow extends StatelessWidget {
  const ClaudeRow({
    super.key,
    required this.label,
    this.subtitle,
    this.trailing,
    this.leading,
    this.onTap,
    this.height = 56,
    this.labelColor,
    this.showDivider = true,
  });

  final String label;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;
  final VoidCallback? onTap;
  final double height;
  final Color? labelColor;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ClaudeSpacing.md,
                vertical: ClaudeSpacing.xs,
              ),
              child: Row(
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: ClaudeSpacing.sm),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          label,
                          style: ClaudeType.bodySmall.copyWith(
                            color: labelColor ?? tokens.bodyStrong,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: ClaudeType.caption.copyWith(
                              color: tokens.muted,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: ClaudeSpacing.sm),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: tokens.hairline),
      ],
    );
  }
}
