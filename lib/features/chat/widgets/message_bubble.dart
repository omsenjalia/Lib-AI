import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/data/database.dart';
import '../../../core/theme/claude_tokens.dart';
import '../../../core/widgets/claude_mark.dart';
import '../../../core/widgets/claude_sheet.dart';
import '../../../core/widgets/loading_indicator.dart';
import 'message_content.dart';

/// One turn in the chat panel.
///
/// The layout is the reference's, and it is the reason a two-hour explanation
/// stays readable: the user's turn is a tinted block on the right, and the
/// assistant's answer is unboxed text on the canvas with only a small mark in
/// the gutter. Nothing about an answer is decorated.
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
    this.onDelete,
    this.showRegenerate = false,
    this.fontFamily = ChatFontFamily.lato,
  });

  final Message message;

  /// Display name of the model that answered, shown in the long-press sheet.
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
  final VoidCallback? onDelete;
  final bool showRegenerate;

  /// Which face the transcript is set in, from the "Chat font" setting.
  final ChatFontFamily fontFamily;

  bool get _isUser => message.role == 'user';

  /// Content to render: the live buffer while streaming, the stored text
  /// otherwise. During a stream SQLite only has a stale copy, so the buffer is
  /// the authority.
  String get _content => streamingText ?? message.content;

  /// 80 % of the pane, as the tokens specify — measured from the pane rather
  /// than the screen so the bubble does not change width with the sidebar.
  double _maxBubbleWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width * 0.8;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ClaudeSpacing.md,
        vertical: ClaudeSpacing.xs,
      ),
      child: _isUser ? _buildUser(context) : _buildAssistant(context),
    );
  }

  // --------------------------------------------------------------------- user

  Widget _buildUser(BuildContext context) {
    final tokens = context.tokens;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _maxBubbleWidth(context)),
            child: GestureDetector(
              onLongPress: () => _showMessageSheet(context),
              child: Container(
                decoration: BoxDecoration(
                  color: tokens.bubble,
                  // One corner is pulled in to 4 dp. It is the only asymmetry in
                  // the interface and it is what says "this is the user".
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(ClaudeRadius.bubble),
                    topRight: Radius.circular(ClaudeRadius.bubble),
                    bottomLeft: Radius.circular(ClaudeRadius.bubble),
                    bottomRight: Radius.circular(ClaudeRadius.bubbleTail),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.imagePath != null)
                      _attachedImage(context, message.imagePath!),
                    if (_content.isNotEmpty)
                      SelectableText(
                        _content,
                        style: ClaudeType.chatBody(fontFamily)
                            .copyWith(color: tokens.ink),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
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
          style: ClaudeType.caption.copyWith(
            fontStyle: FontStyle.italic,
            color: context.tokens.errorText,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ClaudeRadius.md),
        child: Image.file(
          file,
          height: 180,
          fit: BoxFit.cover,
          // A corrupt or unreadable image should degrade to a label rather than
          // throw during layout.
          errorBuilder: (context, error, stack) => Container(
            height: 60,
            alignment: Alignment.center,
            color: context.tokens.surfaceCard,
            child: Text(
              'Image could not be displayed',
              style: ClaudeType.caption.copyWith(color: context.tokens.muted),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- assistant

  Widget _buildAssistant(BuildContext context) {
    final tokens = context.tokens;

    if (message.isError) {
      return _buildError(context);
    }

    return GestureDetector(
      onLongPress: () => _showMessageSheet(context),
      // No background, no border, no padding box: the answer is text on the
      // canvas, and the mark in the gutter is the only thing that marks it as
      // the assistant's.
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // Nudges the mark onto the first line's optical centre.
            padding: const EdgeInsets.only(top: 5),
            child: ClaudeMark(size: 20, color: tokens.primary),
          ),
          const SizedBox(width: ClaudeSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_content.isEmpty && isStreaming)
                  LoadingIndicator(label: statusLabel ?? 'Thinking', compact: true)
                else
                  MessageContent(
                    content: _content,
                    forceMath: message.renderMath,
                    fontFamily: fontFamily,
                    showStreamingCursor: isStreaming,
                  ),
                // The action row only exists once the answer has stopped
                // growing: offering "regenerate" mid-stream invites a tap that
                // throws away work the user cannot see yet.
                if (!isStreaming)
                  Padding(
                    padding: const EdgeInsets.only(top: ClaudeSpacing.xs),
                    child: _AssistantActions(
                      renderMath: message.renderMath,
                      showRegenerate: showRegenerate,
                      onCopy: onCopy ??
                          () => _copy(context, _content, 'Message copied'),
                      onRegenerate: onRegenerate,
                      onToggleRenderMath: onToggleRenderMath,
                      onMore: () => _showMessageSheet(context),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final tokens = context.tokens;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // Matches the mark's optical offset so both turn types start on the
          // same line.
          padding: const EdgeInsets.only(top: 5),
          child: Icon(
            Icons.error_outline_rounded,
            size: 20,
            color: tokens.errorText,
          ),
        ),
        const SizedBox(width: ClaudeSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Could not answer',
                style: ClaudeType.titleSmall.copyWith(color: tokens.errorText),
              ),
              const SizedBox(height: 4),
              Text(
                message.content,
                style: ClaudeType.bodySmall.copyWith(color: tokens.body),
              ),
              if (showRegenerate && onRegenerate != null) ...[
                const SizedBox(height: ClaudeSpacing.xs),
                TextButton.icon(
                  onPressed: onRegenerate,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// The long-press sheet: Copy, Regenerate (assistant turns only), Delete.
  Future<void> _showMessageSheet(BuildContext context) async {
    final tokens = context.tokens;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: tokens.sheetSurface,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(ClaudeRadius.sheet)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            const SizedBox(height: ClaudeSpacing.xs),
            ClaudeRow(
              label: 'Copy',
              leading: Icon(
                Icons.content_copy_rounded,
                size: 18,
                color: tokens.muted,
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _copy(context, _content, 'Message copied');
              },
            ),
            if (!_isUser && onRegenerate != null)
              ClaudeRow(
                label: 'Regenerate',
                leading: Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: tokens.muted,
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onRegenerate!();
                },
              ),
            if (onDelete != null)
              ClaudeRow(
                label: 'Delete',
                labelColor: tokens.errorText,
                leading: Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: tokens.errorText,
                ),
                showDivider: false,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onDelete!();
                },
              ),
            const SizedBox(height: ClaudeSpacing.xs),
          ],
        ),
      ),
    );
  }

  static Future<void> _copy(
    BuildContext context,
    String text,
    String confirmation,
  ) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(confirmation),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }
}

/// Copy / regenerate / maths, aligned left under the answer.
class _AssistantActions extends StatelessWidget {
  const _AssistantActions({
    required this.renderMath,
    required this.showRegenerate,
    required this.onCopy,
    required this.onRegenerate,
    required this.onToggleRenderMath,
    required this.onMore,
  });

  final bool renderMath;
  final bool showRegenerate;
  final VoidCallback onCopy;
  final VoidCallback? onRegenerate;
  final VoidCallback? onToggleRenderMath;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    // Fades in over the fast duration once generation has finished, per the
    // motion tokens.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: ClaudeMotion.fast,
      curve: ClaudeMotion.easeOut,
      builder: (context, value, child) =>
          Opacity(opacity: value, child: child),
      child: Row(
        children: [
          _MessageAction(
            icon: Icons.content_copy_rounded,
            tooltip: 'Copy message',
            onPressed: onCopy,
          ),
          if (onToggleRenderMath != null)
            _MessageAction(
              icon: renderMath
                  ? Icons.functions_rounded
                  : Icons.functions_outlined,
              tooltip: renderMath
                  ? 'Showing undelimited LaTeX as maths'
                  : 'Render undelimited LaTeX in this message as maths',
              active: renderMath,
              onPressed: onToggleRenderMath!,
            ),
          if (showRegenerate && onRegenerate != null)
            _MessageAction(
              icon: Icons.refresh_rounded,
              tooltip: 'Regenerate this answer',
              onPressed: onRegenerate!,
            ),
          _MessageAction(
            icon: Icons.more_horiz_rounded,
            tooltip: 'More actions',
            onPressed: onMore,
            color: tokens.mutedSoft,
          ),
        ],
      ),
    );
  }
}

class _MessageAction extends StatelessWidget {
  const _MessageAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: 16,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
      color: active ? tokens.primary : (color ?? tokens.muted),
      icon: Icon(icon),
    );
  }
}
