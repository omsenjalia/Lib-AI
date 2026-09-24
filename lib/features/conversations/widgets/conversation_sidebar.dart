import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/data/database.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/claude_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/claude_mark.dart';
import '../../chat/providers/chat_controller.dart';
import '../../model_library/screens/model_library_screen.dart';
import '../../notes/screens/notes_screen.dart';
import '../../personas/screens/personas_screen.dart';
import '../../settings/screens/settings_screen.dart';
import 'conversation_actions_sheet.dart';

/// The recents panel, and the host that slides it in.
///
/// ## Why this is not a Material [Drawer]
///
/// The panel's width (85 %), its travel time (280 ms with the documented
/// ease-out) and its scrim (black at 40 %) are all specified, and none of the
/// three is configurable on [Scaffold]'s drawer. Rather than accept a 246 ms
/// slide at Material's own scrim the host owns one [AnimationController], which
/// also lets the panel track a finger during an edge swipe instead of only
/// playing a fixed animation.
///
/// The host handles what a drawer would otherwise provide for free: the scrim
/// tap, a left-edge drag to open, a leftward drag on the panel to close, and the
/// system back gesture.
class SidebarHost extends StatefulWidget {
  const SidebarHost({
    super.key,
    required this.child,
    required this.sidebar,
    this.edgeDragWidth = 20,
  });

  /// The screen behind the panel.
  final Widget child;

  /// The panel itself.
  final Widget sidebar;

  /// How far in from the left edge a drag may start an open gesture.
  final double edgeDragWidth;

  @override
  State<SidebarHost> createState() => SidebarHostState();
}

class SidebarHostState extends State<SidebarHost>
    with SingleTickerProviderStateMixin {
  /// 0 = closed, 1 = fully open. Driven by the animation or by a drag.
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: ClaudeMotion.base,
    reverseDuration: ClaudeMotion.base,
  );

  /// The panel's share of the screen width.
  static const double _widthFactor = 0.85;

  bool get isOpen => _progress.value > 0.0;

  void open() => _progress.forward();

  void close() => _progress.reverse();

  void toggle() => isOpen ? close() : open();

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  /// Drag handling shared by the edge strip and the panel.
  void _onDragUpdate(DragUpdateDetails details) {
    final width = MediaQuery.sizeOf(context).width * _widthFactor;
    if (width <= 0) return;
    _progress.value = (_progress.value + details.delta.dx / width).clamp(0, 1);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    // A decisive flick wins over position; otherwise the panel settles to
    // whichever end it is closer to.
    if (velocity.abs() > 350) {
      velocity > 0 ? open() : close();
      return;
    }
    _progress.value >= 0.5 ? open() : close();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final panelWidth = screenWidth * _widthFactor;

    return PopScope(
      // A back gesture closes the panel first, and does not leave the screen.
      canPop: !isOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isOpen) close();
      },
      child: Stack(
        children: [
          widget.child,

          // Left-edge strip. Only present while closed, so it cannot swallow
          // drags that belong to the transcript.
          if (!isOpen)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: widget.edgeDragWidth,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
              ),
            ),

          // Scrim: fades in with the panel, and only takes taps once it is
          // actually visible.
          AnimatedBuilder(
            animation: _progress,
            builder: (context, _) {
              final value = _progress.value;
              return IgnorePointer(
                ignoring: value == 0,
                child: GestureDetector(
                  key: const Key('sidebar-scrim'),
                  behavior: HitTestBehavior.opaque,
                  onTap: close,
                  child: ColoredBox(
                    color: tokens.scrim.withValues(
                      alpha: tokens.scrim.a * value,
                    ),
                  ),
                ),
              );
            },
          ),

          AnimatedBuilder(
            animation: _progress,
            builder: (context, child) {
              final value = Curves.easeOutCubic.transform(
                _progress.value.clamp(0.0, 1.0),
              );
              return Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: panelWidth,
                child: FractionalTranslation(
                  translation: Offset(value - 1, 0),
                  child: GestureDetector(
                    key: const Key('sidebar-panel'),
                    onHorizontalDragUpdate: _onDragUpdate,
                    onHorizontalDragEnd: _onDragEnd,
                    child: child,
                  ),
                ),
              );
            },
            child: Material(
              color: tokens.sidebarSurface,
              child: widget.sidebar,
            ),
          ),
        ],
      ),
    );
  }
}

/// The conversation list panel.
///
/// Ordering and search are both local: the list is a stream from SQLite, and
/// what the user types filters that in-memory list. Nothing here touches the
/// network, which is what lets the sidebar work in airplane mode like every
/// other screen.
class ConversationSidebar extends ConsumerStatefulWidget {
  const ConversationSidebar({super.key, this.onNavigate});

  /// Called when a row has opened a conversation, so the host can close the
  /// panel.
  final VoidCallback? onNavigate;

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
        margin: const EdgeInsets.all(ClaudeSpacing.md),
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

  /// Ids mid-collapse, so a delete animates the row away before the list
  /// rebuilds without it.
  final _collapsing = <int>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final conversations = ref.watch(conversationsProvider);
    final chat = ref.watch(chatControllerProvider);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          _newChatButton(context),
          _searchField(context),
          Expanded(
            child: conversations.when(
              loading: () => Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tokens.primary,
                ),
              ),
              error: (error, stack) => Padding(
                padding: const EdgeInsets.all(ClaudeSpacing.md),
                child: Text(
                  'Could not load conversations: $error',
                  style: ClaudeType.bodySmall.copyWith(color: tokens.muted),
                ),
              ),
              data: (rows) {
                final filtered = _filter(rows);
                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(ClaudeSpacing.lg),
                      child: Text(
                        rows.isEmpty
                            ? 'No conversations yet.\nAsk something and it '
                                'will appear here.'
                            : 'Nothing matches that search.',
                        textAlign: TextAlign.center,
                        style: ClaudeType.bodySmall.copyWith(
                          color: tokens.muted,
                        ),
                      ),
                    ),
                  );
                }
                return _conversationList(filtered, chat);
              },
            ),
          ),
          _footer(context),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ClaudeSpacing.md,
        ClaudeSpacing.md,
        ClaudeSpacing.md,
        ClaudeSpacing.xs,
      ),
      child: Row(
        children: [
          ClaudeMark(size: 20, color: tokens.primary),
          const SizedBox(width: ClaudeSpacing.xs),
          Text(
            AppConstants.appName,
            style: ClaudeType.titleSmall.copyWith(color: tokens.ink),
          ),
        ],
      ),
    );
  }

  Widget _newChatButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ClaudeSpacing.md),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () {
            ref.read(chatControllerProvider).startNewChat();
            widget.onNavigate?.call();
          },
          icon: const Icon(Icons.edit_outlined, size: 17),
          label: const Text('New chat'),
        ),
      ),
    );
  }

  Widget _searchField(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ClaudeSpacing.md,
        ClaudeSpacing.sm,
        ClaudeSpacing.md,
        ClaudeSpacing.xs,
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        style: ClaudeType.bodySmall.copyWith(color: tokens.ink),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: tokens.surfaceSoft,
          hintText: 'Search conversations',
          hintStyle: ClaudeType.bodySmall.copyWith(color: tokens.muted),
          prefixIcon: Icon(Icons.search_rounded, size: 18, color: tokens.muted),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 40, minHeight: 40),
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
            borderRadius: BorderRadius.circular(ClaudeRadius.pill),
            borderSide: BorderSide(color: tokens.hairline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(ClaudeRadius.pill),
            borderSide: BorderSide(color: tokens.hairline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(ClaudeRadius.pill),
            borderSide: BorderSide(color: tokens.primary),
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

  /// Groups by recency, in the order the reference uses: a search result set is
  /// not re-grouped, because a search is about finding one row rather than
  /// browsing a timeline.
  Widget _conversationList(List<Conversation> rows, ChatController chat) {
    if (_searchController.text.trim().isNotEmpty) {
      return ListView(
        padding: const EdgeInsets.only(bottom: ClaudeSpacing.md),
        children: [for (final row in rows) _tile(row, chat)],
      );
    }

    final now = DateTime.now();
    final buckets = <String, List<Conversation>>{
      'Today': [],
      'Yesterday': [],
      'Previous 7 days': [],
      'Older': [],
    };

    for (final row in rows) {
      buckets[_bucketFor(row.updatedAt, now)]!.add(row);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: ClaudeSpacing.md),
      children: [
        for (final entry in buckets.entries)
          if (entry.value.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ClaudeSpacing.md,
                ClaudeSpacing.md,
                ClaudeSpacing.md,
                ClaudeSpacing.xs,
              ),
              child: Text(
                entry.key.toUpperCase(),
                style: ClaudeType.captionCaps.copyWith(
                  color: context.tokens.muted,
                ),
              ),
            ),
            for (final conversation in entry.value) _tile(conversation, chat),
          ],
      ],
    );
  }

  static String _bucketFor(DateTime updatedAt, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(updatedAt.year, updatedAt.month, updatedAt.day);
    final days = today.difference(that).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 7) return 'Previous 7 days';
    return 'Older';
  }

  Widget _tile(Conversation conversation, ChatController chat) {
    final tokens = context.tokens;
    final isActive = chat.conversationId == conversation.id;
    final collapsing = _collapsing.contains(conversation.id);

    final row = Material(
      color: isActive ? tokens.surfaceSoft : Colors.transparent,
      child: InkWell(
        onTap: () {
          chat.openConversation(conversation.id);
          widget.onNavigate?.call();
        },
        // Long press is where a conversation's own actions live: rename,
        // duplicate, export and delete all act on the row that was pressed.
        onLongPress: () => ConversationActionsSheet.show(
          context,
          conversation,
          onClosed: widget.onNavigate,
        ),
        child: SizedBox(
          height: ClaudeSpacing.sidebarRowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ClaudeSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        conversation.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ClaudeType.bodySmall.copyWith(
                          fontWeight: FontWeight.w500,
                          color: tokens.bodyStrong,
                        ),
                      ),
                      if (_personaName(conversation) != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: _SubjectTag(
                            label: _personaName(conversation)!,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: ClaudeSpacing.xs),
                Text(
                  formatRelativeTime(conversation.updatedAt),
                  style: ClaudeType.caption.copyWith(
                    fontWeight: FontWeight.w400,
                    color: tokens.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Dismissible(
      key: ValueKey('conversation-${conversation.id}'),
      direction: DismissDirection.endToStart,
      // The red affordance is exactly the width of the delete target, so what
      // the user reveals is what they are about to hit.
      background: Container(
        alignment: Alignment.centerRight,
        color: tokens.error,
        width: 48,
        padding: const EdgeInsets.only(right: ClaudeSpacing.md),
        child: Icon(
          Icons.delete_outline_rounded,
          color: tokens.onPrimary,
          size: 20,
        ),
      ),
      confirmDismiss: (_) async {
        // Collapse the row first, then delete: the list is a database stream,
        // so a row that vanished without a transition would read as a glitch.
        setState(() => _collapsing.add(conversation.id));
        await Future<void>.delayed(ClaudeMotion.base);
        if (!mounted) return false;
        // If the delete fails the row stays in the list; un-collapsing it after
        // the fact is better than leaving an invisible row behind.
        Future<void>.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _collapsing.remove(conversation.id));
        });
        await ConversationSidebar.deleteWithUndo(
          context,
          ref,
          conversation,
        );
        return false;
      },
      child: ClipRect(
        child: AnimatedAlign(
          alignment: Alignment.centerLeft,
          heightFactor: collapsing ? 0 : 1,
          duration: ClaudeMotion.base,
          curve: ClaudeMotion.easeOut,
          child: AnimatedOpacity(
            opacity: collapsing ? 0 : 1,
            duration: ClaudeMotion.base,
            curve: ClaudeMotion.easeOut,
            child: row,
          ),
        ),
      ),
    );
  }

  String? _personaName(Conversation conversation) {
    final personaId = conversation.personaId;
    if (personaId == null) return null;
    final personas = ref.watch(personasProvider).valueOrNull;
    if (personas == null) return null;
    for (final persona in personas) {
      if (persona.id == personaId) return persona.name;
    }
    return null;
  }

  Widget _footer(BuildContext context) {
    final tokens = context.tokens;
    final activeModel = ref.watch(activeModelIdProvider);

    void push(Widget screen) {
      // Navigating from the panel closes it, so returning from a pushed screen
      // lands on the conversation rather than on an open drawer.
      widget.onNavigate?.call();
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => screen),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, thickness: 1, color: tokens.hairline),
        _footerRow(
          icon: Icons.library_books_rounded,
          label: 'Model Library',
          trailing: Text(
            activeModel == null ? 'No model' : 'Ready',
            style: ClaudeType.caption.copyWith(
              fontWeight: FontWeight.w400,
              color: activeModel == null ? tokens.errorText : tokens.muted,
            ),
          ),
          onTap: () => push(const ModelLibraryScreen()),
        ),
        _footerRow(
          icon: Icons.school_rounded,
          label: 'Study Personas',
          onTap: () => push(const PersonasScreen()),
        ),
        _footerRow(
          icon: Icons.note_alt_outlined,
          label: 'My Notes',
          onTap: () => push(const NotesScreen()),
        ),
        _footerRow(
          icon: Icons.settings_rounded,
          label: 'Settings',
          onTap: () => push(const SettingsScreen()),
          showDivider: false,
        ),
        Divider(height: 1, thickness: 1, color: tokens.hairline),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ClaudeSpacing.md,
            vertical: ClaudeSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.surfaceStrong,
                  shape: BoxShape.circle,
                  border: Border.all(color: tokens.hairline),
                ),
                child: Text(
                  'AI',
                  style: ClaudeType.caption.copyWith(
                    fontSize: 10,
                    color: tokens.bodyStrong,
                  ),
                ),
              ),
              const SizedBox(width: ClaudeSpacing.sm),
              Expanded(
                child: Text(
                  AppConstants.appName,
                  style: ClaudeType.bodySmall.copyWith(
                    color: tokens.bodyStrong,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Settings',
                iconSize: 18,
                color: tokens.muted,
                onPressed: () => push(const SettingsScreen()),
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _footerRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Widget? trailing,
    bool showDivider = true,
  }) {
    final tokens = context.tokens;
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ClaudeSpacing.md,
              ),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: tokens.muted),
                  const SizedBox(width: ClaudeSpacing.sm),
                  Expanded(
                    child: Text(
                      label,
                      style: ClaudeType.bodySmall.copyWith(
                        color: tokens.bodyStrong,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing,
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: tokens.hairlineSoft),
      ],
    );
  }
}

/// The 10 px subject tag on a conversation row.
class _SubjectTag extends StatelessWidget {
  const _SubjectTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: tokens.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(ClaudeRadius.xs),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: ClaudeType.caption.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w400,
          color: tokens.primaryActive,
        ),
      ),
    );
  }
}
