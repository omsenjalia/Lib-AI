import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The shared placeholder used by the empty conversation list, the empty model
/// library and the "My Notes" coming-soon screen.
///
/// [action] exists because two of those three states have an obvious next step
/// (start a chat, open the model library) and the third deliberately does not.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.footnote,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  /// Small print under the action, used for things like the storage path of
  /// exported files.
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.brightness == Brightness.dark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.22),
                  ),
                ),
                child: Icon(icon, size: 30, color: scheme.primary),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: secondary,
                  ),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 18),
                action!,
              ],
              if (footnote != null) ...[
                const SizedBox(height: 14),
                Text(
                  footnote!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.4,
                    fontStyle: FontStyle.italic,
                    color: secondary.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
