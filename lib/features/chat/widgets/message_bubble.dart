import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/data/database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/loading_indicator.dart';
import 'message_content.dart';

/// One turn in the chat panel.
///
/// The layout follows Claude.ai rather than a messaging app: the user's turn is
/// a tinted block on the right, and the assistant's answer is unboxed body text
/// on the left, so long explanations read as a document instead of as a wall of
/// chat bubbles.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.modelName,
    this.streamingText,
    this.isStreaming = false,
    this.statusLabel,
    this.onToggleRenderMath,
    this.onRegenerate,
    this.onCopy,
    this.showRegenerate = false,
  });

  final Message message;

  /// Display name of the model that answered, shown above assistant turns.
  final String modelName;

  /// Live text while this message is still being generated. Null when the turn
  /// is finished.
  final String? streamingText;

  final bool isStreaming;

  /// Engine progress text, e.g. "Loading weights into memory".
  final String? statusLabel;

  final VoidCallback? onToggleRenderMath;
  final VoidCallback? onRegenerate;
  final VoidCallback? onCopy;
  final bool showRegenerate;

  bool get _isUser => message.role == 'user';

  /// Content to render: the live buffer while streaming, the stored text
  /// otherwise. During a stream SQLite only has a stale copy, so the buffer is
  /// the authority.
  String get _content => streamingText ?? message.content;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: _isUser ? _buildUser(context) : _buildAssistant(context),
    );
  }

  // --------------------------------------------------------------------- user

  Widget _buildUser(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = scheme.brightness == Brightness.light;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              decoration: BoxDecoration(
                color: isLight
                    ? AppColors.userBubbleLight
                    : AppColors.userBubbleDark,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(4),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.imagePath != null)
                    _attachedImage(context, message.imagePath!),
                  if (_content.isNotEmpty)
                    SelectableText(
                      _content,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: scheme.onSurface,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    formatAbsoluteTime(message.createdAt),
                    style: TextStyle(
                      fontSize: 9.5,
                      color: isLight
                          ? AppColors.lightTextSecondary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        _rowActions(context, alignEnd: true),
      ],
    );
  }

  Widget _attachedImage(BuildContext context, String path) {
    final file = File(path);
    if (!file.existsSync()) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          'Attached image is no longer on disk.',
          style: TextStyle(
            fontSize: 11.5,
            fontStyle: FontStyle.italic,
            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.9),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          file,
          height: 160,
          fit: BoxFit.cover,
          // A corrupt or unreadable image should degrade to a label rather than
          // throw during layout.
          errorBuilder: (context, error, stack) => Container(
            height: 60,
            alignment: Alignment.center,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Text('Image could not be displayed',
                style: TextStyle(fontSize: 11.5)),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- assistant

  Widget _buildAssistant(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = scheme.brightness == Brightness.light;

    if (message.isError) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _assistantGutter(context, isError: true),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: scheme.error.withValues(alpha: isLight ? 0.07 : 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: scheme.error.withValues(alpha: 0.35),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 15,
                        color: scheme.error,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Could not answer',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: scheme.error,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message.content,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: scheme.onSurface.withValues(alpha: 0.9),
                    ),
                  ),
                  if (showRegenerate && onRegenerate != null) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: onRegenerate,
                      icon: const Icon(Icons.refresh_rounded, size: 15),
                      label: const Text('Try again'),
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _assistantGutter(context),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    modelName,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatAbsoluteTime(message.createdAt),
                    style: TextStyle(
                      fontSize: 9.5,
                      color: isLight
                          ? AppColors.lightTextSecondary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (_content.isEmpty && isStreaming)
                LoadingIndicator(
                  label: statusLabel ?? 'Thinking',
                  compact: true,
                )
              else
                MessageContent(
                  content: _content,
                  forceMath: message.renderMath,
                ),
              const SizedBox(height: 4),
              _assistantActions(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _assistantGutter(BuildContext context, {bool isError = false}) {
    final scheme = Theme.of(context).colorScheme;
    final tone = isError ? scheme.error : scheme.primary;
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Icon(
        isError ? Icons.priority_high_rounded : Icons.auto_stories_rounded,
        size: 14,
        color: tone,
      ),
    );
  }

  /// Per-message controls.
  ///
  /// The "Render math" toggle is always available on assistant turns, not only
  /// when the message looks like it contains maths: the whole reason it exists
  /// is that the model sometimes emits LaTeX without delimiters, and the app
  /// cannot reliably tell that apart from ordinary backslashes.
  Widget _assistantActions(BuildContext context) {
    final secondary = Theme.of(context).brightness == Brightness.dark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;

    return Row(
      children: [
        _ActionButton(
          icon: Icons.content_copy_rounded,
          label: 'Copy',
          tooltip: 'Copy message',
          onPressed: onCopy,
          color: secondary,
        ),
        if (onToggleRenderMath != null)
          _ActionButton(
            icon: message.renderMath
                ? Icons.functions_rounded
                : Icons.functions_outlined,
            label: message.renderMath ? 'Math on' : 'Render math',
            tooltip: message.renderMath
                ? 'Showing undelimited LaTeX as maths'
                : 'Render undelimited LaTeX in this message as maths',
            onPressed: onToggleRenderMath,
            color: message.renderMath
                ? Theme.of(context).colorScheme.primary
                : secondary,
          ),
        if (showRegenerate && onRegenerate != null)
          _ActionButton(
            icon: Icons.refresh_rounded,
            label: 'Regenerate',
            tooltip: 'Discard this answer and ask again',
            onPressed: onRegenerate,
            color: secondary,
          ),
      ],
    );
  }

  Widget _rowActions(BuildContext context, {required bool alignEnd}) {
    final secondary = Theme.of(context).brightness == Brightness.dark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;

    return _ActionButton(
      icon: Icons.content_copy_rounded,
      label: 'Copy',
      tooltip: 'Copy message',
      onPressed: onCopy ??
          () async {
            await Clipboard.setData(ClipboardData(text: _content));
          },
      color: secondary,
      iconOnly: true,
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.color,
    this.onPressed,
    this.iconOnly = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final Color color;
  final VoidCallback? onPressed;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    if (onPressed == null) return const SizedBox.shrink();

    if (iconOnly) {
      return IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        iconSize: 15,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        color: color,
        icon: Icon(icon),
      );
    }

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
