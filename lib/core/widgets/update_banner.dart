import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The dismissible banner that announces an available model update.
///
/// The one rule this widget exists to enforce: it never downloads anything. Its
/// action is "Review", which opens the model card; the download only starts from
/// an explicit tap there. The brief is explicit that an update notification must
/// not become an automatic transfer, so there is deliberately no "Update now"
/// path from here.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({
    super.key,
    required this.title,
    required this.message,
    required this.onReview,
    required this.onDismiss,
    this.badgeCount = 1,
  });

  final String title;
  final String message;

  /// Opens the model library, focused on the first model with an update.
  final VoidCallback onReview;

  /// Hides the banner for this session.
  final VoidCallback onDismiss;

  /// How many models have updates; drives the plural wording.
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = scheme.brightness == Brightness.light;

    // Amber-tinted, not red: an available update is an opportunity, not a fault.
    final background = isLight
        ? AppColors.lightAccentMuted
        : AppColors.accentMuted.withValues(alpha: 0.55);
    final border = AppColors.accent.withValues(alpha: 0.45);
    final foreground = isLight ? AppColors.lightAccent : AppColors.accent;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(Icons.system_update_alt_rounded,
                  size: 18, color: foreground),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: foreground,
                          ),
                        ),
                      ),
                      if (badgeCount > 1)
                        Text(
                          '$badgeCount models',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: foreground.withValues(alpha: 0.8),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: scheme.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      InkWell(
                        onTap: onReview,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: Text(
                            'Review',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: foreground,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Updates are never downloaded automatically',
                        style: TextStyle(
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          color: scheme.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              tooltip: 'Dismiss',
              icon: Icon(
                Icons.close_rounded,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
