import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/database.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/pdf_export_service.dart';
import '../../../core/theme/claude_tokens.dart';
import '../../../core/widgets/claude_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../chat/providers/chat_controller.dart';
import 'conversation_sidebar.dart';

/// What a long press on a conversation row offers: rename, duplicate, export,
/// delete.
///
/// These actions used to live in a top-bar overflow menu. They moved here when
/// the top bar took the reference's shape, which has exactly three elements —
/// a menu button, the model name and a compose button — and no room for a
/// fourth. A conversation's own actions sitting on the conversation's own row is
/// also the more direct mapping: the sheet acts on the thing that was pressed.
class ConversationActionsSheet extends ConsumerWidget {
  const ConversationActionsSheet({
    super.key,
    required this.conversation,
    this.onClosed,
  });

  final Conversation conversation;

  /// Called after an action that changes what the list should show, so the host
  /// can close the sidebar.
  final VoidCallback? onClosed;

  static Future<void> show(
    BuildContext context,
    Conversation conversation, {
    VoidCallback? onClosed,
  }) {
    final tokens = context.tokens;
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: tokens.sheetSurface,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(ClaudeRadius.sheet)),
      ),
      builder: (_) => ConversationActionsSheet(
        conversation: conversation,
        onClosed: onClosed,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ClaudeSpacing.md,
              ClaudeSpacing.sm,
              ClaudeSpacing.md,
              ClaudeSpacing.xs,
            ),
            child: Text(
              conversation.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: ClaudeType.titleSmall.copyWith(color: tokens.ink),
            ),
          ),
          ClaudeRow(
            label: 'Open',
            leading: Icon(Icons.chat_bubble_outline, size: 18, color: tokens.muted),
            onTap: () {
              Navigator.of(context).pop();
              ref.read(chatControllerProvider).openConversation(conversation.id);
              onClosed?.call();
            },
          ),
          ClaudeRow(
            label: 'Rename',
            leading: Icon(Icons.edit_outlined, size: 18, color: tokens.muted),
            onTap: () {
              Navigator.of(context).pop();
              _rename(context, ref);
            },
          ),
          ClaudeRow(
            label: 'Duplicate',
            leading:
                Icon(Icons.copy_all_outlined, size: 18, color: tokens.muted),
            onTap: () {
              Navigator.of(context).pop();
              ref
                  .read(chatControllerProvider)
                  .duplicateConversation(conversation.id);
              onClosed?.call();
            },
          ),
          ClaudeRow(
            label: 'Save as PDF',
            leading: Icon(Icons.save_alt_rounded, size: 18, color: tokens.muted),
            onTap: () {
              Navigator.of(context).pop();
              _export(context, ref, share: false);
            },
          ),
          ClaudeRow(
            label: 'Share PDF',
            leading: Icon(Icons.ios_share_rounded, size: 18, color: tokens.muted),
            onTap: () {
              Navigator.of(context).pop();
              _export(context, ref, share: true);
            },
          ),
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
              Navigator.of(context).pop();
              _delete(context, ref);
            },
          ),
          const SizedBox(height: ClaudeSpacing.xs),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: conversation.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename conversation'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 200,
          decoration: const InputDecoration(counterText: ''),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newTitle == null) return;
    await ref
        .read(chatControllerProvider)
        .renameConversation(conversation.id, newTitle);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete conversation?',
      message: '"${conversation.title}" and all of its messages will be '
          'removed from this device.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed || !context.mounted) return;
    await ConversationSidebar.deleteWithUndo(context, ref, conversation);
  }

  /// The same export path the composer used to offer, now that a conversation's
  /// actions live on its row.
  Future<void> _export(
    BuildContext context,
    WidgetRef ref, {
    required bool share,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Building PDF...'),
        duration: Duration(seconds: 2),
      ),
    );

    final database = ref.read(databaseProvider);
    final messages = await database.messagesFor(conversation.id);
    final catalogue = ref.read(catalogueProvider).valueOrNull;
    final personas = ref.read(personasProvider).valueOrNull;

    String? personaName;
    final personaId = conversation.personaId;
    if (personaId != null && personas != null) {
      for (final persona in personas) {
        if (persona.id == personaId) personaName = persona.name;
      }
    }

    final bundle = ConversationExport(
      conversation: conversation,
      messages: messages,
      personaName: personaName,
      modelName: conversation.modelId == null
          ? null
          : catalogue?.byId(conversation.modelId!)?.displayName,
    );

    const service = PdfExportService();
    try {
      if (share) {
        await service.sharePdf(bundle);
        return;
      }
      final file = await service.writePdf(bundle);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Saved to ${file.path}'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (error) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Export failed: $error')),
      );
    }
  }
}
