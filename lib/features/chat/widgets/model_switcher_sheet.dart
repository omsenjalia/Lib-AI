import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/database.dart';
import '../../../core/models/model_catalogue.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/claude_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/claude_sheet.dart';
import '../../../core/widgets/status_badge.dart';
import '../../model_library/screens/model_library_screen.dart';

/// Bottom sheet for switching the active model.
///
/// Three facts are surfaced here that the rest of the UI only hints at:
///
///  * A model swap does not unload the previous one immediately — fllama keeps
///    its context for around two minutes — so peak memory briefly holds both.
///    The sheet says so rather than letting a subsequent out-of-memory failure
///    look mysterious.
///  * Only models that are actually on disk can be selected, because an offline
///    app cannot answer with a model it has not downloaded.
///  * Models that are *not* on disk are listed too, but their action is
///    "Download", which opens Model Library. Downloads through a second code
///    path in a sheet would mean a second place to get storage permissions and
///    progress notifications wrong.
class ModelSwitcherSheet extends ConsumerWidget {
  /// Private: the sheet is only ever built inside [show], which is what supplies
  /// the scroll controller the draggable sheet hands down. A public constructor
  /// would invite a second entry point with no controller to give it.
  const ModelSwitcherSheet._({required this.scrollController});

  /// Opens the sheet. Returns the model id the user chose, if any.
  static Future<String?> show(BuildContext context) {
    final tokens = context.tokens;
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.sheetSurface,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(ClaudeRadius.sheet)),
      ),
      builder: (context) => DraggableScrollableSheet(
        // Half the screen to start, most of it at most: the common case is two
        // or three models, and a sheet that opens full-height for those would
        // read as a screen rather than a switcher.
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => ModelSwitcherSheet._(
          scrollController: scrollController,
        ),
      ),
    );
  }

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final installations = ref.watch(installationsProvider);
    final catalogue = ref.watch(catalogueProvider);
    final activeId = ref.watch(activeModelIdProvider);
    final settings = ref.watch(currentSettingsProvider);

    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(),
          const SheetTitle(title: 'Switch model'),
          Expanded(
            child: installations.when(
              loading: () => Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tokens.primary,
                ),
              ),
              error: (error, stack) => Padding(
                padding: const EdgeInsets.all(ClaudeSpacing.md),
                child: Text(
                  'Could not read installed models: $error',
                  style: ClaudeType.bodySmall.copyWith(color: tokens.muted),
                ),
              ),
              data: (rows) {
                final models = catalogue.valueOrNull;
                final installedIds = rows.map((r) => r.modelId).toSet();
                final downloadable = <CatalogueModel>[
                  if (models != null)
                    for (final model in models.models)
                      if (!installedIds.contains(model.id)) model,
                ];

                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.only(bottom: ClaudeSpacing.lg),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        ClaudeSpacing.md,
                        0,
                        ClaudeSpacing.md,
                        ClaudeSpacing.sm,
                      ),
                      child: Text(
                        'Only models already on this device can answer offline.',
                        textAlign: TextAlign.center,
                        style: ClaudeType.caption.copyWith(
                          fontWeight: FontWeight.w400,
                          color: tokens.muted,
                        ),
                      ),
                    ),
                    if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(ClaudeSpacing.lg),
                        child: Text(
                          'No models are installed yet. Download one below to '
                          'get started.',
                          textAlign: TextAlign.center,
                          style: ClaudeType.bodySmall
                              .copyWith(color: tokens.muted),
                        ),
                      ),
                    for (final installation in rows)
                      _InstalledModelRow(
                        installation: installation,
                        model: models?.byId(installation.modelId),
                        isActive: installation.modelId == activeId,
                        isDefault:
                            settings.defaultModelId == installation.modelId,
                        onSelect: () =>
                            Navigator.of(context).pop(installation.modelId),
                      ),
                    if (activeId != null) const _MemoryNote(),
                    if (downloadable.isNotEmpty)
                      const ClaudeSectionHeader(
                        title: 'Available to download',
                        padding: EdgeInsets.fromLTRB(
                          ClaudeSpacing.md,
                          ClaudeSpacing.md,
                          ClaudeSpacing.md,
                          ClaudeSpacing.xs,
                        ),
                      ),
                    for (final model in downloadable)
                      ClaudeRow(
                        label: model.displayName,
                        subtitle:
                            '${model.parameterCount} · ${model.sizeClass} · '
                            '${model.recommendedQuant}',
                        trailing: Text(
                          'Download',
                          style: ClaudeType.bodySmall.copyWith(
                            color: tokens.primaryActive,
                          ),
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ModelLibraryScreen(),
                            ),
                          );
                        },
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One installed model: name, its chips, and the active/ready state.
class _InstalledModelRow extends ConsumerWidget {
  const _InstalledModelRow({
    required this.installation,
    required this.model,
    required this.isActive,
    required this.isDefault,
    required this.onSelect,
  });

  final ModelInstallation installation;
  final CatalogueModel? model;
  final bool isActive;
  final bool isDefault;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final name = model?.displayName ?? installation.modelId;
    final visionReady = model?.visionSupported ?? false;

    return InkWell(
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: ClaudeSpacing.md,
          vertical: ClaudeSpacing.sm,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: tokens.hairline)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: ClaudeType.bodySmall.copyWith(
                      fontWeight: FontWeight.w500,
                      color: tokens.bodyStrong,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      StatusBadge(label: installation.quant, dense: true),
                      StatusBadge(
                        label: formatBytes(installation.totalBytes),
                        dense: true,
                      ),
                      if (visionReady)
                        const StatusBadge(
                          label: 'Vision',
                          tone: BadgeTone.accent,
                          icon: Icons.visibility_outlined,
                          dense: true,
                        ),
                      if (installation.mmprojPath == null && visionReady)
                        const StatusBadge(
                          label: 'Text only (no projector)',
                          tone: BadgeTone.muted,
                          dense: true,
                        ),
                    ],
                  ),
                  if (!isActive) ...[
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () async {
                        await ref
                            .read(settingsControllerProvider.notifier)
                            .setDefaultModel(installation.modelId);
                        if (!context.mounted) return;
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(
                            content: Text('$name is now the default model'),
                            duration: const Duration(milliseconds: 1400),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isDefault
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              size: 14,
                              color: isDefault
                                  ? tokens.primary
                                  : tokens.muted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isDefault ? 'Default model' : 'Use by default',
                              style: ClaudeType.caption.copyWith(
                                color: isDefault
                                    ? tokens.primaryActive
                                    : tokens.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: ClaudeSpacing.sm),
            // Active gets the accent check; downloaded but idle gets a muted
            // one, so "which model is answering right now" is a colour glance
            // rather than a read.
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: isActive ? tokens.primary : tokens.mutedSoft,
                  ),
                  if (isActive) ...[
                    const SizedBox(width: 4),
                    Text(
                      'Active',
                      style: ClaudeType.caption.copyWith(
                        color: tokens.primaryActive,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The peak-memory warning, kept verbatim from the previous sheet: it is the
/// difference between an out-of-memory error and an explainable one.
class _MemoryNote extends StatelessWidget {
  const _MemoryNote();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ClaudeSpacing.md,
        ClaudeSpacing.sm,
        ClaudeSpacing.md,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.memory_rounded, size: 14, color: tokens.primary),
          const SizedBox(width: ClaudeSpacing.xs),
          Expanded(
            child: Text(
              'Switching keeps the previous model in memory for about two '
              'minutes, so peak memory briefly holds both. If a switch fails '
              'with an out-of-memory error, wait a minute and try again.',
              style: ClaudeType.caption.copyWith(
                fontWeight: FontWeight.w400,
                color: tokens.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
