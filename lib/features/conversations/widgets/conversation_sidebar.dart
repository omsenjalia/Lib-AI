import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/database.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state.dart';
import '../../chat/providers/chat_controller.dart';
import '../../notes/screens/notes_screen.dart';
import '../../personas/screens/personas_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../../model_library/screens/model_library_screen.dart';

/// The conversation list, shown as the chat screen's drawer.
///
/// Ordering and search are both local: the list is a stream from SQLite, and
/// what the user types filters that in-memory list. Nothing here touches the
/// network, which is what lets the sidebar work in airplane mode like every
/// other screen.
///
/// Swipe-to-delete is paired with undo rather than a confirmation dialog: a
/// swipe is easy to trigger by accident, and an undo bar is a lighter way to
/// make that recoverable than a modal for every deletion.
class ConversationSidebar extends ConsumerStatefulWidget {
  const ConversationSidebar({super.key});

  /// Deletes [conversation], leaving an undo bar in its place.
  ///
  /// Shared with the chat screen's overflow menu so that deleting from either
  /// place behaves identically, including the undo.
  static Future<void> deleteWithUndo(
    BuildContext context,
    WidgetRef ref,
    Conversation conversation,
  ) async {
    final database = ref.read(databaseProvider);
    final chat = ref.read(chatControllerProvider);

    // Read the messages before deleting so undo can restore the thread rather
    // than only its title.
    final messages = await database.messagesFor(conversation.id);
    await database.deleteConversation(conversation.id);
    if (chat.conversationId == conversation.id) chat.startNewChat();

    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('Deleted "${conversation.title}"'),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            final newId = await database.createConversation(
              title: conversation.title,
              modelId: conversation.modelId,
              personaId: conversation.personaId,
            );
            for (final message in messages) {
              await database.addMessage(
                conversationId: newId,
                role: message.role,
                content: message.content,
                imagePath: message.imagePath,
                isError: message.isError,
                tokenCount: message.tokenCount,
                isEstimatedTokens: message.isEstimatedTokens,
              );
            }
          },
        ),
      ),
    );
  }

  @override
  ConsumerState<ConversationSidebar> createState() =>
      _ConversationSidebarState();
}

class _ConversationSidebarState extends ConsumerState<ConversationSidebar> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = scheme.brightness == Brightness.light;
    final conversations = ref.watch(conversationsProvider);
    final chat = ref.watch(chatControllerProvider);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          _searchField(context, isLight),
          const Divider(height: 1),
          Expanded(
            child: conversations.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Could not load conversations: $error'),
              ),
              data: (rows) {
                final filtered = _filter(rows);
                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.forum_outlined,
                    title: rows.isEmpty
                        ? 'No conversations yet'
                        : 'Nothing matches',
                    message: rows.isEmpty
                        ? 'Ask a question and your conversations will appear here.'
                        : 'Try a different search term.',
                  );
                }
                return _conversationList(filtered, chat);
              },
            ),
          ),
          const Divider(height: 1),
          _footer(context, ref),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Library AI',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'New chat',
            onPressed: () {
              ref.read(chatControllerProvider).startNewChat();
              Navigator.of(context).maybePop();
            },
            icon: const Icon(Icons.edit_square),
            iconSize: 19,
            color: AppColors.accent,
          ),
        ],
      ),
    );
  }

  Widget _searchField(BuildContext context, bool isLight) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: TextField(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search conversations',
          hintStyle: TextStyle(
            fontSize: 13,
            color: isLight
                ? AppColors.lightTextSecondary
                : AppColors.textSecondary,
          ),
          prefixIcon: const Icon(Icons.search_rounded, size: 18),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 34, minHeight: 34),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  iconSize: 16,
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: isLight ? AppColors.lightOutline : AppColors.outline,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  /// Applies the search box to the local conversation stream.
  List<Conversation> _filter(List<Conversation> rows) {
    final query = _searchController.text.trim().toLowerCase();

    return rows.where((conversation) {
      if (query.isEmpty) return true;
      return conversation.title.toLowerCase().contains(query) ||
          (conversation.modelId?.toLowerCase().contains(query) ?? false);
    }).toList(growable: false);
  }

  Widget _conversationList(
    List<Conversation> rows,
    ChatController chat,
  ) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [for (final conversation in rows) _tile(conversation, chat)],
    );
  }

  Widget _tile(Conversation conversation, ChatController chat) {
    final scheme = Theme.of(context).colorScheme;
    final isActive = chat.conversationId == conversation.id;

    return Dismissible(
      key: ValueKey('conversation-${conversation.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        color: AppColors.error.withValues(alpha: 0.85),
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      // Confirm before removing: the delete is undoable, but a Dismissible that
      // returns true is gone from the tree immediately, so the undo bar is what
      // the user actually sees.
      confirmDismiss: (_) async {
        await ConversationSidebar.deleteWithUndo(context, ref, conversation);
        return false;
      },
      child: Material(
        color: isActive
            ? AppColors.accent.withValues(alpha: 0.10)
            : Colors.transparent,
        child: ListTile(
          dense: true,
          selected: isActive,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          title: Text(
            conversation.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              color: scheme.onSurface,
            ),
          ),
          subtitle: Text(
            formatRelativeTime(conversation.updatedAt),
            style: TextStyle(
              fontSize: 10.5,
              color: scheme.brightness == Brightness.dark
                  ? AppColors.textSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
          onTap: () {
            chat.openConversation(conversation.id);
            Navigator.of(context).maybePop();
          },
        ),
      ),
    );
  }

  Widget _footer(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.brightness == Brightness.dark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;

    void push(Widget screen) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => screen),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          _footerTile(
            icon: Icons.library_books_rounded,
            label: 'Model Library',
            trailing: _modelBadge(ref),
            onTap: () => push(const ModelLibraryScreen()),
            secondary: secondary,
          ),
          _footerTile(
            icon: Icons.school_rounded,
            label: 'Study Personas',
            onTap: () => push(const PersonasScreen()),
            secondary: secondary,
          ),
          _footerTile(
            icon: Icons.note_alt_outlined,
            label: 'My Notes',
            trailing: const Text(
              'Coming soon',
              style: TextStyle(fontSize: 10, color: AppColors.accent),
            ),
            onTap: () => push(const NotesScreen()),
            secondary: secondary,
          ),
          _footerTile(
            icon: Icons.settings_rounded,
            label: 'Settings',
            onTap: () => push(const SettingsScreen()),
            secondary: secondary,
          ),
        ],
      ),
    );
  }

  /// Number of installed models, or nothing while the list is loading.
  Widget? _modelBadge(WidgetRef ref) {
    final installs = ref.watch(installationsProvider).valueOrNull;
    if (installs == null) return null;
    if (installs.isEmpty) {
      return const Text(
        'No model',
        style: TextStyle(fontSize: 10, color: AppColors.error),
      );
    }
    return Text(
      '${installs.length} installed',
      style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
    );
  }

  Widget _footerTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color secondary,
    Widget? trailing,
  }) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18),
      leading: Icon(icon, size: 18, color: secondary),
      title: Text(
        label,
        style: const TextStyle(fontSize: 12.5),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
