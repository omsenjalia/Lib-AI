import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/models/model_catalogue.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/claude_tokens.dart';
import '../../../core/widgets/claude_mark.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/update_banner.dart';
import '../../conversations/widgets/conversation_sidebar.dart';
import '../../model_library/screens/model_library_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../providers/chat_controller.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_composer.dart';
import '../widgets/model_switcher_sheet.dart';
import '../widgets/persona_picker_sheet.dart';

/// The main screen: the transcript, with the recents panel sliding over it.
///
/// There is one of these. The sidebar is an overlay rather than a route, which
/// is what keeps the "cold start to chat-ready" budget achievable on a phone:
/// there is no second screen to build before the composer is usable.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _sidebarKey = GlobalKey<SidebarHostState>();
  final _scrollController = ScrollController();
  final _composerKey = GlobalKey<MessageComposerState>();

  /// Lets the user hide the out-of-memory card without hunting for a setting.
  bool _dismissedError = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final chat = ref.watch(chatControllerProvider);
    final catalogue = ref.watch(catalogueProvider).valueOrNull;
    final activeModelId = ref.watch(activeModelIdProvider);
    final model = catalogue?.byId(activeModelId);
    final conversations = ref.watch(conversationsProvider).valueOrNull;
    final updates = ref.watch(updateStateProvider).valueOrNull;
    final bannerDismissed = ref.watch(updateBannerDismissedProvider);
    final storageStatus = ref.watch(modelStorageStatusProvider).valueOrNull;
    final storageWarningDismissed =
        ref.watch(storageWarningDismissedProvider);

    final conversation = _conversationFor(conversations, chat.conversationId);
    final persona = _personaFor(ref, conversation?.personaId);

    // Auto-scroll only when the user is already near the bottom, so reading back
    // through a long answer is not interrupted by new content.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeScroll());

    final pendingUpdates = updates?.values
            .where((u) => u.updateAvailable)
            .map((u) => u.modelId)
            .toList(growable: false) ??
        const <String>[];

    return Scaffold(
      backgroundColor: tokens.canvas,
      // The composer is in the column, not floating over the list, so the
      // system's inset resizing is what keeps it above the keyboard.
      resizeToAvoidBottomInset: true,
      body: SidebarHost(
        key: _sidebarKey,
        sidebar: ConversationSidebar(
          onNavigate: () => _sidebarKey.currentState?.close(),
        ),
        child: Column(
          children: [
            ClaudeTopBar(
              title: activeModelId == null
                  ? 'Choose model'
                  : (model?.displayName ?? 'Missing model'),
              titleColor: activeModelId != null && model == null
                  ? tokens.errorText
                  : tokens.bodyStrong,
              contextFraction: chat.contextLength <= 0
                  ? 0
                  : chat.usedTokens / chat.contextLength,
              contextLabel:
                  '${(100 * chat.usedTokens / chat.contextLength).clamp(0, 100).round()}% '
                  'of ${_formatTokens(chat.contextLength)} context'
                  '${chat.tokensAreExact ? '' : ' (estimated)'}',
              onMenu: () => _sidebarKey.currentState?.toggle(),
              onTitle: () => _switchModel(chat),
              onCompose: () {
                chat.startNewChat();
                _sidebarKey.currentState?.close();
              },
            ),
            if (storageStatus?.warning != null && !storageWarningDismissed)
              MaterialBanner(
                content: Text(storageStatus!.warning!),
                leading: Icon(
                  Icons.folder_off_outlined,
                  color: tokens.muted,
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      ref.read(storageWarningDismissedProvider.notifier).state =
                          true;
                      _openSettings();
                    },
                    child: const Text('Choose folder'),
                  ),
                  TextButton(
                    onPressed: () => ref
                        .read(storageWarningDismissedProvider.notifier)
                        .state = true,
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            if (pendingUpdates.isNotEmpty && !bannerDismissed)
              UpdateBanner(
                title: 'Model update available',
                message: _updateMessage(pendingUpdates, catalogue),
                badgeCount: pendingUpdates.length,
                onReview: () {
                  ref.read(updateBannerDismissedProvider.notifier).state = true;
                  _openModelLibrary();
                },
                onDismiss: () =>
                    ref.read(updateBannerDismissedProvider.notifier).state =
                        true,
              ),
            if (!_dismissedError && chat.lastError != null)
              _EngineErrorCard(
                error: chat.lastError!,
                onDismiss: () => setState(() => _dismissedError = true),
              ),
            if (conversation != null || persona != null)
              _PersonaChipRow(
                persona: persona,
                onTapPersona: () => _pickPersona(chat, conversation),
              ),
            Expanded(child: _body(context, chat, model)),
            MessageComposer(
              key: _composerKey,
              isGenerating: chat.isGenerating,
              visionAvailable: chat.visionAvailable,
              enabled: activeModelId != null,
              disabledReason: 'No model installed yet. Open Model Library to '
                  'download one - after that, everything works offline.',
              onSend: (text, imagePath) => chat.send(text, imagePath: imagePath),
              onStop: chat.stop,
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    ChatController chat,
    CatalogueModel? model,
  ) {
    final activeModelId = ref.watch(activeModelIdProvider);

    if (activeModelId == null) {
      return EmptyState(
        icon: Icons.download_rounded,
        title: 'No model installed',
        message: 'Library AI needs a model on the device before it can answer '
            'anything. Downloads happen once; after that the app is fully '
            'offline.',
        action: FilledButton.icon(
          onPressed: _openModelLibrary,
          icon: const Icon(Icons.library_books_rounded, size: 17),
          label: const Text('Open Model Library'),
        ),
      );
    }

    if (!chat.hasMessages && !chat.isGenerating) {
      return HomeView(
        onPick: (text) => _composerKey.currentState?.setText(text),
      );
    }

    final messages = chat.messages;
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(
        top: ClaudeSpacing.md,
        bottom: ClaudeSpacing.lg,
      ),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isStreamingRow =
            chat.isGenerating && message.id == chat.streamingMessageId;
        final isLast = index == messages.length - 1;

        return MessageBubble(
          key: ValueKey(message.id),
          message: message,
          modelName: model?.displayName ?? 'Assistant',
          streamingText: isStreamingRow ? chat.streamingText : null,
          isStreaming: isStreamingRow,
          statusLabel: chat.statusLabel,
          fontFamily: ref.watch(currentSettingsProvider).chatFont,
          onToggleRenderMath: message.role == 'assistant' && !message.isError
              ? () => chat.toggleRenderMath(message)
              : null,
          onRegenerate: isLast && message.role == 'assistant'
              ? chat.regenerate
              : null,
          showRegenerate:
              isLast && !chat.isGenerating && message.role == 'assistant',
          onDelete: () => chat.deleteMessage(message),
        );
      },
    );
  }

  void _maybeScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final nearBottom = position.maxScrollExtent - position.pixels < 220;
    if (!nearBottom) return;
    _scrollController.animateTo(
      position.maxScrollExtent,
      duration: ClaudeMotion.fast,
      curve: ClaudeMotion.easeOut,
    );
  }

  // ------------------------------------------------------------------ actions

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  void _openModelLibrary() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ModelLibraryScreen()),
    );
  }

  Future<void> _switchModel(ChatController chat) async {
    final chosen = await ModelSwitcherSheet.show(context);
    if (chosen == null) return;
    await ref.read(settingsControllerProvider.notifier).setDefaultModel(chosen);
    if (!mounted) return;

    // Loading the new model here would put a second model in memory while the
    // current one is still answering: fllama holds the previous model for about
    // two minutes, and a load cancels only the generation, not the memory.
    // Defer to the next send, which is the first moment the model is actually
    // needed.
    if (chat.isGenerating) return;

    try {
      await chat.ensureModelLoaded();
    } on AppException catch (error) {
      if (!mounted || !context.mounted) return;
      setState(() => _dismissedError = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('${error.message} ${error.recovery ?? ''}'.trim()),
        ),
      );
    }
  }

  Future<void> _pickPersona(
    ChatController chat,
    Conversation? conversation,
  ) async {
    final chosen = await PersonaPickerSheet.show(
      context,
      selectedId: conversation?.personaId,
    );
    if (chosen == null) return;
    await chat.setPersona(chosen == -1 ? null : chosen);
  }

  // ------------------------------------------------------------------ lookups

  static Conversation? _conversationFor(List<Conversation>? rows, int? id) {
    if (rows == null || id == null) return null;
    for (final row in rows) {
      if (row.id == id) return row;
    }
    return null;
  }

  static Persona? _personaFor(WidgetRef ref, int? personaId) {
    if (personaId == null) return null;
    final personas = ref.watch(personasProvider).valueOrNull;
    if (personas == null) return null;
    for (final persona in personas) {
      if (persona.id == personaId) return persona;
    }
    return null;
  }

  static String _formatTokens(int tokens) {
    if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(1)}M';
    if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(0)}k';
    return '$tokens';
  }

  static String _updateMessage(
    List<String> modelIds,
    ModelCatalogue? catalogue,
  ) {
    if (catalogue == null) return 'A downloaded model has changed upstream.';
    final names = [
      for (final id in modelIds) catalogue.byId(id)?.displayName ?? id,
    ];
    if (names.length == 1) {
      return '${names.first} has changed on HuggingFace. Reviewing it is '
          'optional, and nothing is downloaded until you choose to update.';
    }
    return '${names.length} models have changed on HuggingFace. Nothing is '
        'downloaded until you choose to update.';
  }
}

/// The 56 dp bar: a circular menu button, the model name (which opens the
/// switcher), a circular accent compose button, and the context meter as a 2 dp
/// rule along the bottom edge.
class ClaudeTopBar extends StatelessWidget {
  const ClaudeTopBar({
    super.key,
    required this.title,
    required this.onMenu,
    required this.onTitle,
    required this.onCompose,
    this.titleColor,
    this.contextFraction = 0,
    this.contextLabel,
  });

  final String title;
  final VoidCallback onMenu;
  final VoidCallback onTitle;
  final VoidCallback onCompose;
  final Color? titleColor;

  /// 0..1 share of the context window in use.
  final double contextFraction;

  /// Spoken and long-pressed form of [contextFraction].
  final String? contextLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: ClaudeSpacing.topBarHeight,
          child: Row(
            children: [
              RoundIconButton(
                icon: Icons.menu_rounded,
                tooltip: 'Conversations',
                onPressed: onMenu,
              ),
              Expanded(
                child: Center(
                  child: Tooltip(
                    message: contextLabel ?? 'Context window',
                    child: InkWell(
                      onTap: onTitle,
                      borderRadius: BorderRadius.circular(ClaudeRadius.md),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ClaudeSpacing.xs,
                          vertical: ClaudeSpacing.xxs,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ClaudeType.bodySmall.copyWith(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: titleColor ?? tokens.body,
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: tokens.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              RoundIconButton(
                icon: Icons.add_rounded,
                tooltip: 'New chat',
                filled: true,
                onPressed: onCompose,
              ),
            ],
          ),
        ),
        // The border and the meter share the last two pixels of the bar, so the
        // meter grows out of the border instead of adding a second line.
        Stack(
          alignment: Alignment.bottomLeft,
          children: [
            Container(height: 1, color: tokens.hairline),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: contextFraction.clamp(0, 1)),
              duration: ClaudeMotion.base,
              curve: ClaudeMotion.easeOut,
              builder: (context, value, _) => FractionallySizedBox(
                widthFactor: value,
                child: Container(height: 2, color: tokens.primary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The home screen: the mark, the greeting, and four suggestions.
///
/// The order is the critique's: the mark and the greeting are the invitation,
/// the suggestions are the affordance, and the composer below them is the
/// answer to both. Chips arrive on a 60 ms stagger and retire together on the
/// first keystroke, because a suggestion that lingers behind a message the user
/// has started writing is noise.
class HomeView extends StatefulWidget {
  const HomeView({super.key, required this.onPick});

  /// Fills the composer with a suggestion. It deliberately does not send:
  /// choosing a starter should still leave the user able to edit it.
  final void Function(String text) onPick;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView>
    with SingleTickerProviderStateMixin {
  static const List<String> _suggestions = [
    'Quiz me on a topic',
    'Explain it step by step',
    'Summarise my notes',
    'Work through a problem',
  ];

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: ClaudeMotion.slow,
  )..forward();

  bool _retired = false;

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: ClaudeSpacing.lg,
        vertical: ClaudeSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: ClaudeSpacing.xl),
          ClaudeMark(size: 44, color: tokens.primary),
          const SizedBox(height: ClaudeSpacing.lg),
          Text(
            _greeting,
            textAlign: TextAlign.center,
            style: ClaudeType.greeting.copyWith(color: tokens.ink),
          ),
          const SizedBox(height: ClaudeSpacing.xl),
          // The chips retire as one: the stagger is an entrance, not a
          // perpetual animation.
          AnimatedOpacity(
            opacity: _retired ? 0 : 1,
            duration: ClaudeMotion.fast,
            curve: ClaudeMotion.easeOut,
            child: IgnorePointer(
              ignoring: _retired,
              child: Column(
                children: [
                  for (var row = 0; row < 2; row++)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: ClaudeSpacing.sm,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var column = 0; column < 2; column++) ...[
                            if (column > 0)
                              const SizedBox(width: ClaudeSpacing.sm),
                            Expanded(
                              child: _staggered(
                                index: row * 2 + column,
                                child: _SuggestionChip(
                                  label: _suggestions[row * 2 + column],
                                  onTap: () {
                                    setState(() => _retired = true);
                                    widget.onPick(
                                      _suggestions[row * 2 + column],
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 12 dp rise plus a fade, offset 60 ms per chip.
  Widget _staggered({required int index, required Widget child}) {
    final start = (index * ClaudeMotion.chipStagger.inMilliseconds) /
        ClaudeMotion.slow.inMilliseconds;
    final animation = CurvedAnimation(
      parent: _entrance,
      curve: Interval(start.clamp(0.0, 0.7), 1, curve: ClaudeMotion.easeOut),
    );

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 12 / 60),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Material(
      color: tokens.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ClaudeRadius.lg),
        side: BorderSide(color: tokens.hairline),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ClaudeRadius.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ClaudeSpacing.md,
              vertical: ClaudeSpacing.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ClaudeType.body.copyWith(
                  fontSize: 15,
                  color: tokens.body,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Optional persona control under the top bar. Conversation subjects are not
/// assigned or surfaced; personas remain an explicit, per-thread choice.
class _PersonaChipRow extends StatelessWidget {
  const _PersonaChipRow({
    required this.persona,
    required this.onTapPersona,
  });

  final Persona? persona;
  final VoidCallback onTapPersona;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: ClaudeSpacing.md,
          vertical: ClaudeSpacing.xxs,
        ),
        children: [
          if (persona != null)
            ActionChip(
              avatar: Text(persona!.emoji, style: const TextStyle(fontSize: 12)),
              label: Text(
                persona!.name,
                style: ClaudeType.caption.copyWith(color: tokens.bodyStrong),
              ),
              onPressed: onTapPersona,
              visualDensity: VisualDensity.compact,
              backgroundColor: tokens.surfaceCard,
              side: BorderSide(
                color: tokens.primary.withValues(alpha: 0.4),
              ),
            )
          else
            ActionChip(
              avatar: Icon(Icons.add_rounded, size: 13, color: tokens.muted),
              label: Text(
                'Persona',
                style: ClaudeType.caption.copyWith(color: tokens.muted),
              ),
              onPressed: onTapPersona,
              visualDensity: VisualDensity.compact,
              backgroundColor: tokens.surfaceCard,
              side: BorderSide(color: tokens.hairline),
            ),
        ],
      ),
    );
  }
}

/// Surfaces an engine failure with its recovery advice.
///
/// Out-of-memory is the case that matters here: the message names a smaller
/// quantisation and a lower context length, and this card offers the two taps
/// that act on that advice.
class _EngineErrorCard extends StatelessWidget {
  const _EngineErrorCard({required this.error, required this.onDismiss});

  final AppException error;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isOom = error is InsufficientMemoryException;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ClaudeSpacing.sm,
        ClaudeSpacing.xs,
        ClaudeSpacing.sm,
        0,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: tokens.error.withValues(alpha: tokens.isDark ? 0.16 : 0.07),
          borderRadius: BorderRadius.circular(ClaudeRadius.lg),
          border: Border.all(color: tokens.error.withValues(alpha: 0.4)),
        ),
        padding: const EdgeInsets.fromLTRB(
          ClaudeSpacing.sm,
          ClaudeSpacing.sm,
          ClaudeSpacing.xxs,
          ClaudeSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isOom ? Icons.memory_rounded : Icons.error_outline_rounded,
                  size: 16,
                  color: tokens.errorText,
                ),
                const SizedBox(width: ClaudeSpacing.xs),
                Expanded(
                  child: Text(
                    error.message,
                    style: ClaudeType.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: tokens.errorText,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onDismiss,
                  iconSize: 15,
                  tooltip: 'Dismiss',
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            if (error.recovery != null) ...[
              const SizedBox(height: ClaudeSpacing.xxs),
              Text(
                error.recovery!,
                style: ClaudeType.caption.copyWith(
                  fontWeight: FontWeight.w400,
                  color: tokens.body,
                ),
              ),
            ],
            const SizedBox(height: ClaudeSpacing.xxs),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ModelLibraryScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.library_books_rounded, size: 15),
                  label: const Text('Try a smaller quant'),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.tune_rounded, size: 15),
                  label: const Text('Lower context length'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
