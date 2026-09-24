import 'package:flutter/material.dart';

import '../theme/claude_tokens.dart';

/// The single confirmation dialog used by the whole app.
///
/// Having one implementation matters more than it sounds: the brief requires
/// that deleting a conversation and hard-blocking a 27B download on mobile data
/// both feel deliberate, and a bespoke `AlertDialog` per call site is how those
/// invariants drift.
///
/// [destructive] recolours the confirm action red. [confirmLabel] is always
/// explicit ("Delete", "Continue on mobile data") so the button never just says
/// OK.
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.cancelLabel = 'Cancel',
    this.destructive = false,
    this.icon,
    this.details = const [],
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final IconData? icon;

  /// Bullet points shown between the message and the buttons, for spelling out
  /// consequences (extra storage, changed checksums, and so on).
  final List<String> details;

  /// Shows the dialog and resolves to the user's choice.
  ///
  /// Returns false when dismissed by tapping outside or pressing back.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    String cancelLabel = 'Cancel',
    bool destructive = false,
    IconData? icon,
    List<String> details = const [],
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => ConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        destructive: destructive,
        icon: icon,
        details: details,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final accent = destructive ? tokens.errorText : tokens.primaryActive;
    final secondary = tokens.muted;

    return AlertDialog(
      icon: icon == null
          ? null
          : Icon(icon, color: accent, size: 26),
      title: Text(
        title,
        textAlign: TextAlign.center,
        style: ClaudeType.titleSmall.copyWith(color: context.tokens.ink),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: ClaudeType.bodySmall.copyWith(color: secondary),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final detail in details)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 5, right: 8),
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          detail,
                          style: ClaudeType.caption.copyWith(
                            fontWeight: FontWeight.w400,
                            color: secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: secondary),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: accent,
          ),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
