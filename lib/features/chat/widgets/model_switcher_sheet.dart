import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/database.dart';
import '../../../core/models/model_catalogue.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/status_badge.dart';

/// Bottom sheet for switching the active model.
///
/// Two facts are surfaced here that the rest of the UI only hints at:
///
///  * A model swap does not unload the previous one immediately - fllama keeps
///    its context for around two minutes - so peak memory briefly holds both.
///    The sheet says so rather than letting a subsequent out-of-memory failure
///    look mysterious.
///  * Only models that are actually on disk are listed, because an offline app
///    cannot offer a model it has not downloaded.
class ModelSwitcherSheet extends ConsumerWidget {
  const ModelSwitcherSheet({super.key});

  /// Opens the sheet. Returns the model id the user chose, if any.
  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const ModelSwitcherSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final installations = ref.watch(installationsProvider);
    final catalogue = ref.watch(catalogueProvider);
    final activeId = ref.watch(activeModelIdProvider);
    final settings = ref.watch(currentSettingsProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Model',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              'Only models already on this device can be used offline.',
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.brightness == Brightness.dark
                    ? AppColors.textSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 12),
            installations.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stack) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('Could not read installed models: $error'),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'No models are installed yet.',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Open Model Library to download one.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final models = catalogue.valueOrNull;
                final switchingAway = activeId != null;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final installation in rows)
                      _ModelTile(
                        installation: installation,
                        model: models?.byId(installation.modelId),
                        isActive: installation.modelId == activeId,
                        isDefault:
                            settings.defaultModelId == installation.modelId,
                        onTap: () =>
                            Navigator.of(context).pop(installation.modelId),
                      ),
                    if (switchingAway) ...[
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.memory_rounded,
                            size: 14,
                            color: AppColors.accent.withValues(alpha: 0.8),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Switching keeps the previous model in memory for '
                              'about two minutes, so peak memory briefly holds '
                              'both. If a switch fails with an out-of-memory '
                              'error, wait a minute and try again.',
                              style: TextStyle(
                                fontSize: 10.5,
                                height: 1.4,
                                color: scheme.brightness == Brightness.dark
                                    ? AppColors.textSecondary
                                    : AppColors.lightTextSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelTile extends ConsumerWidget {
  const _ModelTile({
    required this.installation,
    required this.model,
    required this.isActive,
    required this.isDefault,
    required this.onTap,
  });

  final ModelInstallation installation;
  final CatalogueModel? model;
  final bool isActive;
  final bool isDefault;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final name = model?.displayName ?? installation.modelId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isActive
            ? AppColors.accent.withValues(alpha: 0.10)
            : (scheme.brightness == Brightness.dark
                ? AppColors.surfaceHigh.withValues(alpha: 0.4)
                : AppColors.lightSurfaceHigh),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isActive
                    ? AppColors.accent.withValues(alpha: 0.6)
                    : Colors.transparent,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isActive)
                      const Icon(Icons.check_circle_rounded,
                          size: 16, color: AppColors.accent)
                    else if (isDefault)
                      const StatusBadge(
                        label: 'Default',
                        tone: BadgeTone.muted,
                        dense: true,
                      ),
                  ],
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
                    if (model?.visionSupported ?? false)
                      const StatusBadge(
                        label: 'Vision',
                        tone: BadgeTone.accent,
                        icon: Icons.visibility_outlined,
                        dense: true,
                      ),
                    if (installation.mmprojPath == null &&
                        (model?.visionSupported ?? false))
                      const StatusBadge(
                        label: 'Text only (no projector)',
                        tone: BadgeTone.muted,
                        dense: true,
                      ),
                  ],
                ),
                if (!isActive) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () async {
                          await ref
                              .read(settingsControllerProvider.notifier)
                              .setDefaultModel(installation.modelId);
                          if (context.mounted) {
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                              SnackBar(
                                content: Text('$name is now the default model'),
                                duration:
                                    const Duration(milliseconds: 1400),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.star_border_rounded, size: 15),
                        label: const Text('Use by default'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.accent,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 30),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
