import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/models/model_catalogue.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/pdf_export_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../../../core/widgets/meter_bar.dart';
import '../../../core/widgets/tag_chip.dart';
import '../../../core/widgets/update_banner.dart';
import '../../conversations/widgets/conversation_sidebar.dart';
import '../../model_library/screens/model_library_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../providers/chat_controller.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_composer.dart';
import '../widgets/model_switcher_sheet.dart';
import '../widgets/persona_picker_sheet.dart';
import '../widgets/tag_picker_sheet.dart';

/// The main screen: conversation sidebar (drawer) plus chat panel.
///
/// There is one of these. The sidebar is a drawer over the panel rather than a
/// separate route, which is what keeps the "cold start to chat-ready" budget
/// achievable on a phone: there is no second screen to build before the
/// composer is usable.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _scrollController = ScrollController();
  final _exportService = const PdfExportService();

  /// Lets the user hide the out-of-memory card without hunting for a setting.
  bool _dismissedError = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider);
    final settings = ref.watch(currentSettingsProvider);
    final catalogue = ref.watch(catalogueProvider).valueOrNull;
    final activeModelId = ref.watch(activeModelIdProvider);
    final model = catalogue?.byId(activeModelId);
    final conversations = ref.watch(conversationsProvider).valueOrNull;
    final updates = ref.watch(updateStateProvider).valueOrNull;
    final bannerDismissed = ref.watch(updateBannerDismissedProvider);

    final conversation = _conversationFor(conversations, chat.conversationId);
    final tag = _tagFor(ref, conversation?.subjectTagId);
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
      key: _scaffoldKey,
      drawer: const Drawer(child: ConversationSidebar()),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          tooltip: 'Conversations',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        titleSpacing: 0,
        title: _title(context, conversation),
        actions: [
          _ModelButton(
            model: model,
            installationMissing: activeModelId != null && model == null,
            onPressed: () => _switchModel(context, chat),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsScreen(),
              ),
            ),
          ),
          _OverflowMenu(
            onRename: conversation == null
                ? null
                : () => _rename(context, chat, conversation),
            onDuplicate: conversation == null
                ? null
                : () => chat.duplicateConversation(conversation.id),
            onExport: conversation == null
                ? null
                : (share) => _export(
                      chat,
                      conversation,
                      tag,
                      persona,
                      model,
                      share: share,
                    ),
            onDelete: conversation == null
                ? null
                : () => _deleteConversation(context, conversation),
          ),
        ],
        bottom: conversation == null && tag == null && persona == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(34),
                child: _ChipsRow(
                  tag: tag,
                  persona: persona,
                  onTapTag: () => _pickTag(context, chat, conversation),
                  onTapPersona: () =>
                      _pickPersona(context, chat, conversation),
                ),
              ),
      ),
      body: Column(
        children: [
          if (pendingUpdates.isNotEmpty && !bannerDismissed)
            UpdateBanner(
              title: 'Model update available',
              message: _updateMessage(pendingUpdates, catalogue),
              badgeCount: pendingUpdates.length,
              onReview: () {
                ref.read(updateBannerDismissedProvider.notifier).state = true;
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ModelLibraryScreen(),
                  ),
                );
              },
              onDismiss: () =>
                  ref.read(updateBannerDismissedProvider.notifier).state = true,
            ),
          if (_dismissedError || chat.lastError == null)
            const SizedBox.shrink()
          else
            _EngineErrorCard(
              error: chat.lastError!,
              onDismiss: () => setState(() => _dismissedError = true),
            ),
          Expanded(child: _body(context, chat, model, conversation)),
          if (chat.isGenerating && chat.streamingText.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: LoadingIndicator(
                  label: chat.statusLabel ?? 'Generating',
                ),
              ),
            ),
          MessageComposer(
            isGenerating: chat.isGenerating,
            visionAvailable: chat.visionAvailable,
            enabled: activeModelId != null,
            disabledReason: 'No model installed yet. Open Model Library to '
                'download one - after that, everything works offline.',
            onSend: (text, imagePath) =>
                chat.send(text, imagePath: imagePath),
            onStop: chat.stop,
            header: ContextMeter(
              usedTokens: chat.usedTokens,
              maxTokens: chat.contextLength,
              isEstimate: !chat.tokensAreExact,
            ),
            trailing: _ComposerTrailing(
              temperature: settings.temperature,
              onOpenSettings: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _title(BuildContext context, Conversation? conversation) {
    if (conversation == null) {
      return const Text('Library AI', style: TextStyle(fontSize: 16));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          conversation.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
        if (conversation.contextLengthOverride != null)
          Text(
            'Context ${conversation.contextLengthOverride}',
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.textSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    ChatController chat,
    CatalogueModel? model,
    Conversation? conversation,
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
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ModelLibraryScreen()),
          ),
          icon: const Icon(Icons.library_books_rounded, size: 17),
          label: const Text('Open Model Library'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: const Color(0xFF1A1A2E),
          ),
        ),
      );
    }

    if (!chat.hasMessages && !chat.isGenerating) {
      return _WelcomePrompt(
        modelName: model?.displayName ?? activeModelId,
        personaName: _personaFor(ref, conversation?.personaId)?.name,
        onPick: (text) => chat.send(text),
      );
    }

    final messages = chat.messages;
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(top: 10, bottom: 14),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isStreamingRow = chat.isGenerating &&
            message.id == chat.streamingMessageId;
        final isLast = index == messages.length - 1;

        return MessageBubble(
          key: ValueKey(message.id),
          message: message,
          modelName: model?.displayName ?? 'Assistant',
          streamingText: isStreamingRow ? chat.streamingText : null,
          isStreaming: isStreamingRow,
          statusLabel: chat.statusLabel,
          onToggleRenderMath: message.role == 'assistant' && !message.isError
              ? () => chat.toggleRenderMath(message)
              : null,
          onRegenerate: isLast && message.role == 'assistant'
              ? chat.regenerate
              : null,
          showRegenerate: isLast &&
              !chat.isGenerating &&
              message.role == 'assistant',
        );
      },
    );
  }

  void _maybeScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final nearBottom =
        position.maxScrollExtent - position.pixels < 220;
    if (!nearBottom) return;
    _scrollController.animateTo(
      position.maxScrollExtent,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
    );
  }

  // ------------------------------------------------------------------ actions

  Future<void> _switchModel(BuildContext context, ChatController chat) async {
    final chosen = await ModelSwitcherSheet.show(context);
    if (chosen == null) return;
    await ref.read(settingsControllerProvider.notifier).setDefaultModel(chosen);
    if (!mounted) return;
    try {
      await chat.ensureModelLoaded();
    } on AppException catch (error) {
      // `context` is the method parameter, so guard it with its own `mounted`;
      // `mounted` alone covers the State, not this BuildContext.
      if (!mounted || !context.mounted) return;
      setState(() => _dismissedError = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('${error.message} ${error.recovery ?? ''}'.trim()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickTag(
    BuildContext context,
    ChatController chat,
    Conversation? conversation,
  ) async {
    final chosen = await TagPickerSheet.show(
      context,
      selectedId: conversation?.subjectTagId,
    );
    if (chosen == null) return;
    await chat.setSubjectTag(chosen == -1 ? null : chosen);
  }

  Future<void> _pickPersona(
    BuildContext context,
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

  Future<void> _rename(
    BuildContext context,
    ChatController chat,
    Conversation conversation,
  ) async {
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
    await chat.renameConversation(conversation.id, newTitle);
  }

  Future<void> _deleteConversation(
    BuildContext context,
    Conversation conversation,
  ) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete conversation?',
      message: '"${conversation.title}" and all of its messages will be '
          'removed from this device.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed) return;
    if (!context.mounted) return;

    await ConversationSidebar.deleteWithUndo(context, ref, conversation);
  }

  Future<void> _export(
    ChatController chat,
    Conversation conversation,
    SubjectTag? tag,
    Persona? persona,
    CatalogueModel? model, {
    required bool share,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Building PDF...'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    final bundle = ConversationExport(
      conversation: conversation,
      messages: chat.messages,
      tag: tag,
      personaName: persona?.name,
      modelName: model?.displayName,
    );

    try {
      if (share) {
        await _exportService.sharePdf(bundle);
        return;
      }
      final file = await _exportService.writePdf(bundle);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Saved to ${file.path}'),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Export failed: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ------------------------------------------------------------------ lookups

  static Conversation? _conversationFor(
    List<Conversation>? rows,
    int? id,
  ) {
    if (rows == null || id == null) return null;
    for (final row in rows) {
      if (row.id == id) return row;
    }
    return null;
  }

  static SubjectTag? _tagFor(WidgetRef ref, int? tagId) {
    if (tagId == null) return null;
    final tags = ref.watch(subjectTagsProvider).valueOrNull;
    if (tags == null) return null;
    for (final tag in tags) {
      if (tag.id == tagId) return tag;
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

/// The subject/persona chip row under the app bar.
class _ChipsRow extends StatelessWidget {
  const _ChipsRow({
    required this.tag,
    required this.persona,
    required this.onTapTag,
    required this.onTapPersona,
  });

  final SubjectTag? tag;
  final Persona? persona;
  final VoidCallback onTapTag;
  final VoidCallback onTapPersona;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).brightness == Brightness.dark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          if (tag != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: TagChip(
                name: tag!.name,
                colorValue: tag!.colorValue,
                onTap: onTapTag,
              ),
            )
          else
            _AddChip(label: 'Subject', onTap: onTapTag, color: secondary),
          if (persona != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: ActionChip(
                avatar: Text(persona!.emoji,
                    style: const TextStyle(fontSize: 12)),
                label: Text(
                  persona!.name,
                  style: const TextStyle(fontSize: 11.5),
                ),
                onPressed: onTapPersona,
                visualDensity: VisualDensity.compact,
                side: BorderSide(
                  color: AppColors.accent.withValues(alpha: 0.4),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: _AddChip(
                label: 'Persona',
                onTap: onTapPersona,
                color: secondary,
              ),
            ),
        ],
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  const _AddChip({
    required this.label,
    required this.onTap,
    required this.color,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(Icons.add_rounded, size: 13, color: color),
      label: Text(label, style: TextStyle(fontSize: 11.5, color: color)),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color.withValues(alpha: 0.3)),
    );
  }
}

/// Model name plus a switch affordance, kept in the app bar where it is always
/// visible: which model is answering is the single most important piece of
/// context in the screen.
class _ModelButton extends StatelessWidget {
  const _ModelButton({
    required this.model,
    required this.installationMissing,
    required this.onPressed,
  });

  final CatalogueModel? model;
  final bool installationMissing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = installationMissing
        ? 'Missing model'
        : (model?.displayName ?? 'Choose model');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: installationMissing
              ? AppColors.error
              : scheme.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 36),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(Icons.expand_more_rounded, size: 15),
          ],
        ),
      ),
    );
  }
}

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({
    required this.onRename,
    required this.onDuplicate,
    required this.onExport,
    required this.onDelete,
  });

  final VoidCallback? onRename;
  final VoidCallback? onDuplicate;
  final void Function(bool share)? onExport;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (value) {
        switch (value) {
          case 'rename':
            onRename?.call();
          case 'duplicate':
            onDuplicate?.call();
          case 'share_pdf':
            onExport?.call(true);
          case 'save_pdf':
            onExport?.call(false);
          case 'delete':
            onDelete?.call();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'rename',
          enabled: onRename != null,
          child: const _MenuRow(Icons.edit_outlined, 'Rename'),
        ),
        PopupMenuItem(
          value: 'duplicate',
          enabled: onDuplicate != null,
          child: const _MenuRow(Icons.copy_all_outlined, 'Duplicate'),
        ),
        PopupMenuItem(
          value: 'save_pdf',
          enabled: onExport != null,
          child: const _MenuRow(Icons.save_alt_rounded, 'Save as PDF'),
        ),
        PopupMenuItem(
          value: 'share_pdf',
          enabled: onExport != null,
          child: const _MenuRow(Icons.ios_share_rounded, 'Share PDF'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          enabled: onDelete != null,
          child: const _MenuRow(
            Icons.delete_outline_rounded,
            'Delete conversation',
            destructive: true,
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label, {this.destructive = false});

  final IconData icon;
  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.error : null;
    return Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 13, color: color)),
      ],
    );
  }
}

/// First-run guidance shown once a model is installed but no turn has been sent.
class _WelcomePrompt extends StatelessWidget {
  const _WelcomePrompt({
    required this.modelName,
    required this.personaName,
    required this.onPick,
  });

  final String modelName;
  final String? personaName;
  final void Function(String text) onPick;

  static const List<String> _starters = [
    'Explain the difference between a process and a thread.',
    'Walk me through solving a quadratic equation.',
    'Quiz me on the OSI model, one question at a time.',
    'What is the time complexity of binary search, and why?',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.brightness == Brightness.dark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_stories_rounded,
                    size: 22, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ready to study',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      personaName == null
                          ? 'Answering with $modelName, entirely on device'
                          : '$personaName · $modelName · on device',
                      style: TextStyle(fontSize: 11.5, color: secondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            'Try one of these',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: secondary,
            ),
          ),
          const SizedBox(height: 8),
          for (final starter in _starters)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => onPick(starter),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: scheme.brightness == Brightness.dark
                          ? AppColors.outline
                          : AppColors.lightOutline,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          starter,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: scheme.onSurface.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                      Icon(Icons.north_east_rounded, size: 14, color: secondary),
                    ],
                  ),
                ),
              ),
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
    final isOom = error is InsufficientMemoryException;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isOom ? Icons.memory_rounded : Icons.error_outline_rounded,
                  size: 16,
                  color: AppColors.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error.message,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.error,
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
              const SizedBox(height: 4),
              Text(
                error.recovery!,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.85),
                ),
              ),
            ],
            const SizedBox(height: 6),
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
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 30),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.tune_rounded, size: 15),
                  label: const Text('Lower context length'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 30),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One line under the composer showing the sampling temperature in force.
///
/// It is a read-out rather than a control on purpose: sampling is a setting the
/// user changes rarely and deliberately, and a slider inside the composer would
/// be an easy thing to knock by accident mid-question.
class _ComposerTrailing extends StatelessWidget {
  const _ComposerTrailing({
    required this.temperature,
    required this.onOpenSettings,
  });

  final double temperature;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).brightness == Brightness.dark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;

    return Row(
      children: [
        Text(
          'temp ${temperature.toStringAsFixed(2)}',
          style: TextStyle(fontSize: 10, color: secondary),
        ),
        const Spacer(),
        InkWell(
          onTap: onOpenSettings,
          child: Text(
            'Sampling settings',
            style: TextStyle(
              fontSize: 10,
              color: AppColors.accent.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }
}
