import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/models/model_catalogue.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../widgets/model_card.dart';

/// The model library: five catalogued models, their quantisations, and the
/// controls to download, update or delete them.
///
/// This is the only screen in the app allowed to talk to the network, and every
/// transfer on it starts from a tap. The catalogue itself is a bundled asset, so
/// the screen renders identically offline.
class ModelLibraryScreen extends ConsumerWidget {
  const ModelLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogue = ref.watch(catalogueProvider);
    final installs = ref.watch(installationsProvider).valueOrNull ?? const [];
    final tasks = ref.watch(downloadTasksProvider).valueOrNull ?? const {};
    final updates = ref.watch(updateStateProvider).valueOrNull ?? const {};
    final defaultModelId = ref.watch(currentSettingsProvider).defaultModelId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Model Library', style: TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            tooltip: 'Check for updates now',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _checkNow(context, ref),
          ),
        ],
      ),
      body: catalogue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'The bundled model catalogue could not be read.\n\n$error',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
        ),
        data: (data) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
            children: [
              _targetDeviceNote(context, data),
              const SizedBox(height: 12),
              for (final model in data.models)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: ModelCard(
                    model: model,
                    installation: _installationFor(installs, model.id),
                    task: tasks[model.id],
                    update: updates[model.id],
                    isDefault: defaultModelId == model.id,
                    onDownload: () => _download(context, ref, model),
                    onCancel: () =>
                        ref.read(downloadManagerProvider).cancel(model.id),
                    onDelete: () => _delete(context, ref, model),
                    onUpdate: () => _download(
                      context,
                      ref,
                      model,
                      // An update re-downloads the same quantisation, then
                      // swaps. The old file stays until the new one verifies.
                      existingQuant: _installationFor(installs, model.id)?.quant,
                    ),
                    onSetDefault: () async {
                      await ref
                          .read(settingsControllerProvider.notifier)
                          .setDefaultModel(model.id);
                      if (!context.mounted) return;
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        SnackBar(
                          content: Text(
                            '${model.displayName} is now the default model',
                          ),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(milliseconds: 1500),
                        ),
                      );
                    },
                  ),
                ),
              _storageSummary(context, ref),
            ],
          );
        },
      ),
    );
  }

  static ModelInstallation? _installationFor(
    List<ModelInstallation> installs,
    String modelId,
  ) {
    for (final installation in installs) {
      if (installation.modelId == modelId) return installation;
    }
    return null;
  }

  Widget _targetDeviceNote(BuildContext context, ModelCatalogue catalogue) {
    final device = catalogue.targetDevice;
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.brightness == Brightness.dark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.brightness == Brightness.dark
            ? AppColors.surfaceHigh.withValues(alpha: 0.35)
            : AppColors.lightSurfaceHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.phone_android_rounded, size: 14, color: secondary),
              const SizedBox(width: 6),
              Text(
                device.name,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Sizes and fit ratings are computed against ${device.usableRamGb} GB '
            'of usable RAM on this device. Downloads are verified against the '
            'published SHA-256 before a model is marked as ready.',
            style: TextStyle(fontSize: 10.5, height: 1.4, color: secondary),
          ),
        ],
      ),
    );
  }

  Widget _storageSummary(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(totalModelBytesProvider);
    final secondary = Theme.of(context).brightness == Brightness.dark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(Icons.sd_storage_outlined, size: 14, color: secondary),
          const SizedBox(width: 6),
          Text(
            bytes.when(
              data: (value) => 'Models use ${formatBytes(value)} on this device',
              loading: () => 'Measuring model storage...',
              error: (error, stack) => 'Storage could not be measured',
            ),
            style: TextStyle(fontSize: 11, color: secondary),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ actions

  /// Starts a download, after the two gates the brief requires.
  ///
  /// Gates, in order:
  ///  1. Wi-Fi - a hard requirement for models flagged `wifiOnly`, checked
  ///     before a byte is requested. Mobile data is refused outright; the only
  ///     way through is to connect to Wi-Fi.
  ///  2. Confirmation - a dialog spelling out the size and the RAM risk, so a
  ///     multi-gigabyte transfer is never accidental.
  Future<void> _download(
    BuildContext context,
    WidgetRef ref,
    CatalogueModel model, {
    String? existingQuant,
  }) async {
    final connectivity = ref.read(connectivityServiceProvider);
    final quant = model.quants.firstWhere(
      (q) => q.quant == (existingQuant ?? model.recommendedQuant),
      orElse: () => model.recommendedQuantInfo ?? model.quants.first,
    );

    // Gate 1: the hard Wi-Fi block.
    if (model.wifiOnly) {
      final unmetered = await connectivity.isOnUnmeteredConnection();
      if (!unmetered) {
        if (!context.mounted) return;
        await ConfirmDialog.show(
          context,
          title: 'Wi-Fi required',
          message: '${model.displayName} is a '
              '${formatBytes(quant.sizeBytes)} download and is blocked on '
              'mobile data.',
          confirmLabel: 'OK',
          icon: Icons.wifi_off_rounded,
          destructive: true,
          details: const [
            'This restriction is deliberate: this model is far larger than the '
                'others and a download over mobile data would be expensive.',
            'Connect to Wi-Fi and the download will be available immediately.',
          ],
        );
        return;
      }
    }

    // Gate 2: an explicit confirmation with the real numbers.
    final includeMmproj = model.mmproj != null;
    final total = model.totalDownloadBytes(
      quant,
      includeMmproj: includeMmproj,
    );
    final usedBytes = await ref.read(databaseProvider).totalModelBytes();

    if (!context.mounted) return;
    final details = <String>[
      'Download size: ${formatBytes(total)}'
          '${includeMmproj ? ' (model plus vision projector)' : ''}',
      'Approximate RAM needed to run: ${model.ramRequirementGb.toStringAsFixed(1)} GB',
      if (usedBytes > 0)
        'Models already on this device: ${formatBytes(usedBytes)}',
      if (!model.fitsTargetDevice)
        'This model will not load on this device. It is listed for reference '
            'and will almost certainly fail with an out-of-memory error.',
      if (model.wifiOnly) 'Allowed on Wi-Fi only.',
    ];

    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Download ${model.displayName}?',
      message: 'The file downloads once and is then available offline '
          'permanently. It is verified with SHA-256 before use.',
      confirmLabel: 'Download',
      icon: Icons.download_rounded,
      destructive: !model.fitsTargetDevice,
      details: details,
    );
    if (!confirmed) return;

    try {
      await ref.read(downloadManagerProvider).start(
            model: model,
            quant: quant,
            includeMmproj: includeMmproj,
          );
    } on WifiRequiredException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('${error.message} ${error.recovery ?? ''}'.trim()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on AppException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(error.message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    CatalogueModel model,
  ) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete ${model.displayName}?',
      message: 'The downloaded files are removed from this device. The model '
          'stays in the library and can be downloaded again later.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_outline_rounded,
      details: const [
        'Conversations that used this model are kept.',
        'If it was your default model, you will need to choose another.',
      ],
    );
    if (!confirmed) return;

    await ref.read(downloadManagerProvider).deleteModel(model.id);
    await ref
        .read(settingsControllerProvider.notifier)
        .clearDefaultModelIf(model.id);
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('${model.displayName} deleted'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _checkNow(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final settings = ref.read(currentSettingsProvider);
    if (!settings.autoUpdateCheckEnabled) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Update checks are turned off in Settings.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Checking HuggingFace for changes...'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await ref.read(updateSchedulerProvider).checkNow();
    if (!context.mounted) return;

    if (ref.read(updateCheckerProvider).firstPending == null) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Everything on this device is up to date.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

}
