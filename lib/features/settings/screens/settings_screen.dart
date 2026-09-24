import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/data/database.dart';
import '../../../core/models/app_settings.dart';
import '../../../core/models/model_catalogue.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/model_adoption_service.dart';
import '../../../core/services/model_migration_service.dart';
import '../../../core/services/pdf_export_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../model_library/screens/model_library_screen.dart';

/// Settings: appearance, model and context, sampling, storage, updates, about.
///
/// The Top-k entry is deliberately not wired to inference and says so in the
/// UI rather than pretending: fllama's `OpenAiRequest` exposes temperature,
/// top-p and the two penalties, but no top-k. Its saved value is retained for
/// compatibility. GPU layers are shown only when the native engine reports a
/// usable backend; otherwise Settings clearly explains the CPU-only fallback.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _version;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = '${info.version}+${info.buildNumber}');
    } catch (_) {
      // Version display is cosmetic; a failure must not break the screen.
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final catalogue = ref.watch(catalogueProvider).valueOrNull;
    final installs = ref.watch(installationsProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontSize: 16)),
      ),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Settings could not be loaded: $error'),
          ),
        ),
        data: (value) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
          children: [
            _appearance(context, value, controller),
            _modelSection(value, controller, catalogue, installs),
            _samplingSection(context, value, controller),
            _advancedSection(context, value, controller),
            _updatesSection(context, value, controller),
            _storageSection(context, installs, catalogue),
            _notificationDiagnosticsSection(),
            _aboutSection(context),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- appearance

  Widget _appearance(
    BuildContext context,
    AppSettings settings,
    SettingsController controller,
  ) {
    return _Section(
      title: 'Appearance',
      children: [
        _SegmentedRow<ThemeMode>(
          label: 'Theme',
          value: settings.themeMode,
          options: const {
            ThemeMode.dark: 'Dark',
            ThemeMode.light: 'Light',
            ThemeMode.system: 'System',
          },
          onChanged: controller.setThemeMode,
        ),
        const _Note(
          'Both themes are designed rather than derived: the light theme is a '
          'warm paper surface, not an inverted dark one.',
        ),
      ],
    );
  }

  // ------------------------------------------------------------ model/context

  Widget _modelSection(
    AppSettings settings,
    SettingsController controller,
    ModelCatalogue? catalogue,
    List<ModelInstallation> installs,
  ) {
    // The slider's ceiling comes from the model in play, so it can never be set
    // to a value the model does not support.
    final activeId = settings.defaultModelId ??
        (installs.isEmpty ? null : installs.first.modelId);
    final model = catalogue?.byId(activeId);
    final (min, max) = SettingsService.contextBoundsFor(
      modelMaxContext: model?.maxContextLength ??
          (catalogue?.models.isNotEmpty ?? false
              ? catalogue!.models.first.maxContextLength
              : null),
    );

    final value = settings.contextLength.clamp(min, max);
    final isUnsafe = value < AppConstants.unsafeContextLength;

    return _Section(
      title: 'Defaults',
      children: [
        if (installs.isEmpty)
          const _Note('No models are installed yet. Download one from the Model '
              'Library to choose a default.')
        else
          _DropdownRow<String?>(
            label: 'Default model',
            value: settings.defaultModelId ?? installs.first.modelId,
            items: {
              for (final installation in installs)
                installation.modelId:
                    catalogue?.byId(installation.modelId)?.displayName ??
                        installation.modelId,
            },
            onChanged: controller.setDefaultModel,
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Expanded(
              child: Text('Context length', style: TextStyle(fontSize: 13)),
            ),
            Text(
              '$value tokens',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          // The usable range spans 512 to 262144, so a linear slider would be
          // unusable at the low end. Divisions pick round steps.
          divisions: _divisionsFor(min, max),
          label: '$value',
          onChanged: (next) => controller.setContextLength(next.round()),
          onChangeEnd: (next) => controller.setContextLength(next.round()),
        ),
        Row(
          children: [
            Text('$min', style: const TextStyle(fontSize: 10)),
            const Spacer(),
            Text('$max', style: const TextStyle(fontSize: 10)),
          ],
        ),
        if (isUnsafe)
          const _Note(
            'A context this small may be shorter than the persona prompt plus '
            'your question, which can produce an empty or confused answer. '
            '2048 is a safer floor for real use.',
            tone: _NoteTone.warning,
          )
        else
          _Note(
            model == null
                ? 'Applies to new conversations.'
                : 'Default in new conversations. ${model.displayName} supports '
                    'up to ${model.maxContextLength} tokens, and larger windows '
                    'need more RAM.',
          ),
        const _Note(
          'Lowering this is the quickest fix for an out-of-memory error, and it '
          'takes effect the next time a model loads.',
        ),
      ],
    );
  }

  /// Slider divisions that give sane steps across a very wide range.
  int _divisionsFor(int min, int max) {
    if (max <= 4096) return ((max - min) / 256).round().clamp(2, 64);
    return 64;
  }

  // ---------------------------------------------------------------- sampling

  Widget _samplingSection(
    BuildContext context,
    AppSettings settings,
    SettingsController controller,
  ) {
    final repetitionRisk =
        settings.temperature < AppConstants.repetitionRiskTemperature;

    return _Section(
      title: 'Sampling',
      children: [
        _SliderRow(
          label: 'Temperature',
          value: settings.temperature,
          min: 0,
          max: 1.5,
          divisions: 30,
          display: settings.temperature.toStringAsFixed(2),
          onChanged: (value) => controller.setSampling(temperature: value),
        ),
        if (repetitionRisk)
          const _Note(
            'Temperature is below '
            '${AppConstants.repetitionRiskTemperature}. The Qwythos and Mythos '
            'model cards document repetition loops below this value, so answers '
            'may start repeating themselves.',
            tone: _NoteTone.warning,
          )
        else
          const _Note(
            'Lower is more focused, higher is more varied. '
            'A value between 0.4 and 0.8 suits study answers.',
          ),
        const SizedBox(height: 8),
        _SliderRow(
          label: 'Top-p',
          value: settings.topP,
          min: 0.1,
          max: 1,
          divisions: 18,
          display: settings.topP.toStringAsFixed(2),
          onChanged: (value) => controller.setSampling(topP: value),
        ),
        const SizedBox(height: 8),
        _SliderRow(
          label: 'Top-k',
          value: settings.topK.toDouble(),
          min: 0,
          max: 100,
          divisions: 20,
          display: '${settings.topK}',
          onChanged: (value) => controller.setSampling(topK: value.round()),
        ),
        const _Note(
          'Top-k is saved but not applied by the current engine build: the '
          'llama.cpp binding this app uses exposes temperature, top-p and the '
          'penalties, and has no top-k parameter. Your value is kept for the '
          'engine upgrade planned for the next version.',
          tone: _NoteTone.honest,
        ),
      ],
    );
  }

  Widget _advancedSection(
    BuildContext context,
    AppSettings settings,
    SettingsController controller,
  ) {
    final gpuAvailability = ref.watch(gpuOffloadAvailabilityProvider);
    final gpuLayers = settings.gpuLayers.clamp(0, 99).toDouble();

    return _Section(
      title: 'Advanced',
      initiallyExpanded: false,
      children: [
        if (gpuAvailability.isLoading)
          const _Note('Checking the native inference backend for GPU support...')
        else if (gpuAvailability.valueOrNull == true) ...[
          _SliderRow(
            label: 'GPU layers',
            value: gpuLayers,
            min: 0,
            max: 99,
            divisions: 99,
            display: gpuLayers == 0 ? '0 (CPU)' : '${gpuLayers.round()}',
            onChanged: (value) =>
                controller.setSampling(gpuLayers: value.round()),
          ),
          const _Note(
            'A native GPU backend was detected. This layer setting is applied '
            'when the model loads; if GPU warm-up fails, the engine retries on '
            'CPU.',
            tone: _NoteTone.honest,
          ),
        ] else
          const _Note(
            'CPU inference is active: the pinned fllama Android build does not '
            'enable an OpenCL or Vulkan backend, so the Galaxy S25 Adreno GPU '
            'cannot receive model layers in this build. The engine detects the '
            'missing backend, forces n_gpu_layers to 0, and falls back to CPU. '
            'GPU acceleration needs a native-engine build that actually ships '
            'a supported Android backend; changing this app setting alone '
            'cannot enable it.',
            tone: _NoteTone.honest,
          ),
      ],
    );
  }

  // ----------------------------------------------------------------- updates

  Widget _updatesSection(
    BuildContext context,
    AppSettings settings,
    SettingsController controller,
  ) {
    final checker = ref.read(updateCheckerProvider);

    return _Section(
      title: 'Model updates',
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: settings.autoUpdateCheckEnabled,
          onChanged: controller.setAutoUpdateCheck,
          title: const Text(
            'Check for model updates',
            style: TextStyle(fontSize: 13),
          ),
          subtitle: const Text(
            'Asked at most once every 24 hours per model, when you reconnect '
            'to the internet, and only for models you have downloaded.',
            style: TextStyle(fontSize: 10.5, height: 1.4),
          ),
        ),
        const _Note(
          'A check only reads HuggingFace metadata. Updates are never '
          'downloaded automatically: when something has changed you get a '
          'badge and a banner, and the download starts only from the Update '
          'button. The 27B model is never checked on mobile data.',
          tone: _NoteTone.honest,
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () async {
              final messenger = ScaffoldMessenger.maybeOf(context);
              await ref.read(updateSchedulerProvider).checkNow();
              if (!context.mounted) return;
              final pending = checker.firstPending;
              messenger?.showSnackBar(
                SnackBar(
                  content: Text(
                    pending == null
                        ? 'All downloaded models are up to date.'
                        : 'An update is available. See Model Library.',
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Check now'),
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- storage

  Widget _storageSection(
    BuildContext context,
    List<ModelInstallation> installs,
    ModelCatalogue? catalogue,
  ) {
    final totalBytes =
        installs.fold<int>(0, (sum, item) => sum + item.totalBytes);
    final location = ref.watch(modelStorageStatusProvider);
    final storageStatus = location.valueOrNull;
    final fragilePrivateDataMessage = storageStatus != null &&
            storageStatus.hasFragileUserData
        ? storageStatus.isUserFolder
            ? 'App-private storage still contains '
                '${formatBytes(storageStatus.privateBytesUsed)} of model data. '
                'Uninstalling the app deletes it; move these models to the '
                'user-selected folder to keep them.'
            : 'App-private storage still contains '
                '${formatBytes(storageStatus.privateBytesUsed)} of model data. '
                'Uninstalling the app deletes it. Choose a folder, then move '
                'these models there to keep them.'
        : null;
    final movePending = ref.watch(pendingModelMoveProvider).valueOrNull ?? false;
    final configuredTreeUri =
        ref.watch(currentSettingsProvider).modelStorageTreeUri;

    return _Section(
      title: 'Storage',
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.folder_open_outlined, size: 19),
          title: const Text('Model files location', style: TextStyle(fontSize: 13)),
          subtitle: location.when(
            loading: () => const Text('Checking storage access…'),
            error: (_, __) => const Text('App storage'),
            data: (status) => Text(
              '${status.displayName} · ${formatBytes(status.bytesUsed)}'
              '${status.warning == null ? '' : '\n${status.warning}'}',
              style: TextStyle(
                fontSize: 10.5,
                color: status.warning == null
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ),
          trailing: const Icon(Icons.chevron_right_rounded, size: 19),
          onTap: () => _chooseModelStorageFolder(
            context,
            installs: installs,
            catalogue: catalogue,
          ),
        ),
        const _Note(
          'Choose a folder through Android’s system picker. Access is limited '
          'to that folder; no broad storage permission is requested.',
        ),
        if (fragilePrivateDataMessage != null)
          _Note(
            fragilePrivateDataMessage,
            tone: _NoteTone.warning,
          ),
        const _Note(
          'App-private models are deleted when you uninstall. Models in a '
          'user-selected folder survive app deletion, but Android removes the '
          'app’s folder grant; after reinstall, choose that folder again to '
          'restore access.',
          tone: _NoteTone.honest,
        ),
        if (configuredTreeUri != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.phone_android_rounded, size: 18),
            title: const Text('Use app storage', style: TextStyle(fontSize: 13)),
            subtitle: const Text(
              'Store future downloads in the app-private models folder.',
              style: TextStyle(fontSize: 10.5),
            ),
            onTap: () => _usePrivateModelStorage(
              context,
              installs: installs,
              catalogue: catalogue,
            ),
          ),
        if (installs.isEmpty)
          const _Note('No models are stored on this device.')
        else ...[
          Row(
            children: [
              const Expanded(
                child: Text('Models on this device',
                    style: TextStyle(fontSize: 13)),
              ),
              Text(
                formatBytes(totalBytes),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final installation in installs)
            _StorageRow(
              name: catalogue?.byId(installation.modelId)?.displayName ??
                  installation.modelId,
              quant: installation.quant,
              bytes: installation.totalBytes,
              onDelete: () => _deleteModel(context, ref, installation),
            ),
          if (catalogue != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                movePending ? Icons.resume_rounded : Icons.drive_file_move_outlined,
                size: 18,
              ),
              title: Text(
                movePending ? 'Resume model move' : 'Move existing models',
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                movePending
                    ? 'Continues verified, per-model moves after an interruption.'
                    : 'Copies installed models to the selected folder. Originals '
                        'stay until each copy verifies.',
                style: const TextStyle(fontSize: 10.5),
              ),
              onTap: () => _runModelMove(
                context,
                installs: installs,
                catalogue: catalogue,
                resume: movePending,
              ),
            ),
        ],
        const Divider(height: 22),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.folder_zip_outlined, size: 18),
          title: const Text(
            'Export all conversations (ZIP of PDFs)',
            style: TextStyle(fontSize: 13),
          ),
          subtitle: const Text(
            'Writes one PDF per conversation into a single archive.',
            style: TextStyle(fontSize: 10.5),
          ),
          onTap: () => _exportEverything(context, ref),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.cleaning_services_outlined, size: 18),
          title: const Text(
            'Clean up unfinished downloads',
            style: TextStyle(fontSize: 13),
          ),
          subtitle: const Text(
            'Discards saved partial model files. Resume from the Model Library '
            'to keep and continue them.',
            style: TextStyle(fontSize: 10.5),
          ),
          onTap: () => _sweep(context, ref),
        ),
      ],
    );
  }

  bool get _hasActiveDownloads =>
      ref.read(downloadTasksProvider).valueOrNull?.values.any((task) => task.isActive) ??
      false;

  void _showStorageBusyMessage(BuildContext context) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('Wait for active downloads to finish before changing storage.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _chooseModelStorageFolder(
    BuildContext context, {
    required List<ModelInstallation> installs,
    required ModelCatalogue? catalogue,
  }) async {
    if (_hasActiveDownloads) {
      _showStorageBusyMessage(context);
      return;
    }
    final previousUri = ref.read(currentSettingsProvider).modelStorageTreeUri;
    try {
      final folder =
          await ref.read(storagePathsProvider).pickModelStorageFolder();
      if (folder == null || !context.mounted) return;
      await ref
          .read(settingsControllerProvider.notifier)
          .setModelStorageLocation(treeUri: folder.uri, folderName: folder.name);
      ref.read(storageWarningDismissedProvider.notifier).state = false;
      ref.invalidate(modelStorageStatusProvider);

      ModelAdoptionReport? adoptionReport;
      if (catalogue != null) {
        adoptionReport = await ref
            .read(modelAdoptionServiceProvider)
            .adopt(catalogue);
        ref.invalidate(installationsProvider);
        ref.invalidate(modelStorageStatusProvider);
      }
      if (!context.mounted) return;
      if (adoptionReport != null &&
          (adoptionReport.adopted.isNotEmpty ||
              adoptionReport.failures.isNotEmpty)) {
        await _showAdoptionReport(context, adoptionReport);
      }

      final latestInstalls = await ref.read(databaseProvider).allInstallations();
      if (!context.mounted ||
          latestInstalls.isEmpty ||
          previousUri == folder.uri ||
          catalogue == null) {
        if (adoptionReport == null ||
            (adoptionReport.adopted.isEmpty &&
                adoptionReport.failures.isEmpty)) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text('Model storage set to ${folder.name}/models.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final shouldMove = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Move existing models?'),
              content: Text(
                'New downloads will use ${folder.name}/models. Existing model '
                'files are still in their current location. Move them now? '
                'Each file is checksum-verified before its installation record '
                'changes; the original is kept until then.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Not now'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Move models'),
                ),
              ],
            ),
          ) ??
          false;
      if (shouldMove && context.mounted) {
        await _runModelMove(
          context,
          installs: latestInstalls,
          catalogue: catalogue,
        );
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Could not select model storage: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _usePrivateModelStorage(
    BuildContext context, {
    required List<ModelInstallation> installs,
    required ModelCatalogue? catalogue,
  }) async {
    if (_hasActiveDownloads) {
      _showStorageBusyMessage(context);
      return;
    }
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Use app storage?'),
            content: const Text(
              'New downloads will use app-private storage. Existing models '
              'stay where they are unless you choose to move them.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Keep current folder'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Use app storage'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;

    await ref
        .read(settingsControllerProvider.notifier)
        .clearModelStorageLocation();
    ref.read(storageWarningDismissedProvider.notifier).state = false;
    ref.invalidate(modelStorageStatusProvider);
    if (installs.isEmpty || catalogue == null || !context.mounted) return;

    final shouldMove = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Move models to app storage?'),
            content: const Text(
              'Installed files remain in the selected folder for now. Move '
              'them to app storage? The original is kept until each copy '
              'passes its checksum and the installation is updated.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Move models'),
              ),
            ],
          ),
        ) ??
        false;
    if (shouldMove && context.mounted) {
      await _runModelMove(
        context,
        installs: installs,
        catalogue: catalogue,
      );
    }
  }

  Future<void> _showAdoptionReport(
    BuildContext context,
    ModelAdoptionReport report,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Model folder scanned'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (report.adopted.isNotEmpty) ...[
                  Text(
                    '${report.adopted.length} verified model(s) adopted without '
                    'downloading again:',
                  ),
                  const SizedBox(height: 8),
                  for (final model in report.adopted)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• ${model.modelName} · ${model.quant}'),
                    ),
                ],
                if (report.failures.isNotEmpty) ...[
                  if (report.adopted.isNotEmpty) const SizedBox(height: 12),
                  const Text('Files that could not be verified:'),
                  const SizedBox(height: 8),
                  for (final failure in report.failures)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${failure.modelName} · ${failure.fileName}'),
                          Text(
                            failure.reason,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ModelLibraryScreen(
                                    reDownloadModelId: failure.modelId,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.download_rounded, size: 16),
                            label: const Text('Re-download this model'),
                          ),
                        ],
                      ),
                    ),
                ],
                if (report.adopted.isEmpty && report.failures.isEmpty)
                  const Text(
                    'No catalogue-known model files were found. Choose a model '
                    'in the Model Library to download it.',
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _runModelMove(
    BuildContext context, {
    required List<ModelInstallation> installs,
    required ModelCatalogue catalogue,
    bool resume = false,
  }) async {
    final service = ref.read(modelMigrationServiceProvider);
    ModelMigrationProgress? progress;
    StateSetter? setDialogState;
    BuildContext? dialogContext;
    final operation = resume
        ? service.resumePendingMoves(
            catalogue: catalogue,
            onProgress: (next) {
              progress = next;
              setDialogState?.call(() {});
            },
          )
        : service.moveExistingModels(
            installations: installs,
            catalogue: catalogue,
            onProgress: (next) {
              progress = next;
              setDialogState?.call(() {});
            },
          );

    final dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (routeContext) {
        dialogContext = routeContext;
        return PopScope(
          canPop: false,
          child: StatefulBuilder(
            builder: (context, updateDialog) {
              setDialogState = updateDialog;
              final current = progress;
              final value = current == null || current.totalBytes <= 0
                  ? null
                  : (current.copiedBytes / current.totalBytes)
                      .clamp(0.0, 1.0)
                      .toDouble();
              return AlertDialog(
                title: const Text('Moving models'),
                content: SizedBox(
                  width: 360,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(current?.modelName ?? 'Preparing…'),
                      if (current != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Model ${current.modelIndex} of ${current.modelCount} · '
                          '${formatBytes(current.copiedBytes)} of '
                          '${formatBytes(current.totalBytes)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                      const SizedBox(height: 12),
                      LinearProgressIndicator(value: value),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: service.cancel,
                    child: const Text('Cancel'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
    operation.then<void>(
      (_) {
        if (dialogContext?.mounted ?? false) {
          Navigator.of(dialogContext!).pop();
        }
      },
      onError: (Object error, StackTrace stack) {
        if (dialogContext?.mounted ?? false) {
          Navigator.of(dialogContext!).pop();
        }
      },
    );
    await dialog;

    try {
      final report = await operation;
      ref.invalidate(pendingModelMoveProvider);
      ref.invalidate(modelStorageStatusProvider);
      if (!context.mounted) return;
      final message = report.cancelled
          ? 'Move paused. Resume it from Settings when ready.'
          : report.failures.isEmpty
              ? '${report.movedModelIds.length} model(s) moved and verified.'
              : '${report.movedModelIds.length} model(s) moved; '
                  '${report.failures.length} need attention. Resume from Settings.';
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    } catch (error) {
      ref.invalidate(pendingModelMoveProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Model move could not finish: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deleteModel(
    BuildContext context,
    WidgetRef ref,
    ModelInstallation installation,
  ) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete this model?',
      message: 'The downloaded file is removed from this device. You can '
          'download it again at any time.',
      confirmLabel: 'Delete',
      destructive: true,
      details: [
        'Frees ${formatBytes(installation.totalBytes)}.',
        'Conversations are kept.',
      ],
    );
    if (!confirmed) return;

    await ref.read(downloadManagerProvider).deleteModel(installation.modelId);
    await ref
        .read(settingsControllerProvider.notifier)
        .clearDefaultModelIf(installation.modelId);
  }

  Future<void> _sweep(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await ref
        .read(downloadManagerProvider)
        .sweepPartialDownloads(discardResumable: true);
    if (!context.mounted) return;
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Partial downloads removed.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Builds one PDF per conversation and writes them into a ZIP.
  ///
  /// The archive is written to the exports directory, whose path is shown in
  /// the confirmation. It is not pushed to the share sheet, because sharing a
  /// ZIP through this app's printing integration would hand the system a file
  /// labelled as a PDF. Individual conversations can be shared as real PDFs
  /// from the chat screen's menu.
  Future<void> _exportEverything(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final database = ref.read(databaseProvider);
    final catalogue = ref.read(catalogueProvider).valueOrNull;
    final personas = ref.read(personasProvider).valueOrNull ?? const [];

    final conversations = await database.watchConversations().first;
    if (conversations.isEmpty) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('There are no conversations to export yet.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    messenger?.showSnackBar(
      SnackBar(
        content: Text('Building ${conversations.length} PDFs...'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final bundles = <ConversationExport>[];
      for (final conversation in conversations) {
        final messages = await database.messagesFor(conversation.id);
        if (messages.isEmpty) continue;

        bundles.add(
          ConversationExport(
            conversation: conversation,
            messages: messages,
            personaName: _personaNameFor(personas, conversation.personaId),
            modelName: catalogue?.byId(conversation.modelId)?.displayName,
          ),
        );
      }

      if (bundles.isEmpty) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('None of the conversations have any messages yet.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final file = await const PdfExportService().exportAllAsZip(bundles);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export complete'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${bundles.length} conversations exported as PDFs inside '
                  'one archive.'),
              const SizedBox(height: 10),
              SelectableText(
                file.path,
                style: const TextStyle(fontSize: 11.5, height: 1.4),
              ),
              const SizedBox(height: 10),
              const Text(
                'That folder is this app\'s own storage on the device, so it '
                'can be opened from a file manager or over USB. To send a '
                'single conversation somewhere, use Share PDF from the chat '
                'screen menu instead.',
                style: TextStyle(fontSize: 11, height: 1.5),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
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

  static String? _personaNameFor(List<Persona> personas, int? id) {
    if (id == null) return null;
    for (final persona in personas) {
      if (persona.id == id) return persona.name;
    }
    return null;
  }

  // ------------------------------------------------------ notification status

  Widget _notificationDiagnosticsSection() {
    final diagnostics =
        ref.watch(downloadNotificationServiceProvider).diagnostics;
    final lastApply = diagnostics.lastApplyAt == null
        ? 'No apply call yet'
        : '${diagnostics.lastApplyKind ?? 'unknown'} · '
            '${diagnostics.lastApplyPercent ?? 0}% · '
            '${diagnostics.lastApplyAt!.toLocal().toIso8601String()}';

    return _Section(
      title: 'Notification diagnostics',
      initiallyExpanded: false,
      children: [
        _DiagnosticRow('Service ready', diagnostics.ready ? 'Yes' : 'No'),
        _DiagnosticRow('Permission result', diagnostics.permissionResult),
        _DiagnosticRow('Last apply', lastApply),
        _DiagnosticRow(
          'Last error',
          diagnostics.lastError == null
              ? 'None recorded'
              : '${diagnostics.lastError} · '
                  '${diagnostics.lastErrorAt?.toLocal().toIso8601String() ?? ''}',
        ),
        const _Note(
          'For device logs, run: adb logcat -s flutter. Notification setup '
          'and show failures are logged in release builds too.',
          tone: _NoteTone.honest,
        ),
      ],
    );
  }

  // ------------------------------------------------------------------- about

  Widget _aboutSection(BuildContext context) {
    final secondary = Theme.of(context).brightness == Brightness.dark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;

    return _Section(
      title: 'About',
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.auto_stories_rounded,
                  size: 22, color: AppColors.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    AppConstants.appName,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    AppConstants.tagline,
                    style: TextStyle(fontSize: 11.5, color: secondary),
                  ),
                  Text(
                    _version == null ? 'Version unknown' : 'Version $_version',
                    style: TextStyle(fontSize: 10.5, color: secondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const _Note(
          'Inference runs entirely on this device through llama.cpp. The app '
          'has no account, no telemetry and no server. The only network traffic '
          'it can generate is a model download you start, or a metadata check '
          'for a model you have already downloaded.',
          tone: _NoteTone.honest,
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- small pieces

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.initiallyExpanded = true,
  });

  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = scheme.brightness == Brightness.light;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: BoxDecoration(
          color: isLight ? AppColors.lightSurface : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isLight ? AppColors.lightOutline : AppColors.outline,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: Theme(
          // Nested expansion tiles draw their own dividers; the section border
          // is enough.
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 4),
            title: Text(
              title,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: secondary),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 11, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

enum _NoteTone { normal, honest, warning }

class _Note extends StatelessWidget {
  const _Note(this.text, {this.tone = _NoteTone.normal});

  final String text;
  final _NoteTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final base = isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;

    final (color, background, border) = switch (tone) {
      _NoteTone.normal => (base, Colors.transparent, Colors.transparent),
      _NoteTone.honest => (
          base,
          AppColors.accent.withValues(alpha: 0.05),
          AppColors.accent.withValues(alpha: 0.22),
        ),
      _NoteTone.warning => (
          isDark ? AppColors.meterWarning : AppColors.lightError,
          AppColors.meterWarning.withValues(alpha: 0.08),
          AppColors.meterWarning.withValues(alpha: 0.3),
        ),
    };

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10.5, height: 1.45, color: color),
      ),
    );
  }
}

class _SegmentedRow<T> extends StatelessWidget {
  const _SegmentedRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        const Spacer(),
        SegmentedButton<T>(
          segments: [
            for (final entry in options.entries)
              ButtonSegment<T>(value: entry.key, label: Text(entry.value)),
          ],
          selected: {value},
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11.5)),
          ),
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ],
    );
  }
}

class _DropdownRow<T> extends StatelessWidget {
  const _DropdownRow({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: items.containsKey(value) ? value : items.keys.first,
              isExpanded: true,
              isDense: true,
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onChanged: (next) {
                if (next != null) onChanged(next);
              },
              items: [
                for (final entry in items.entries)
                  DropdownMenuItem<T>(
                    value: entry.key,
                    child: Text(
                      entry.value,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 13)),
            ),
            Text(
              display,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
        Slider(
          value: clamped,
          min: min,
          max: max,
          divisions: divisions,
          label: display,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _StorageRow extends StatelessWidget {
  const _StorageRow({
    required this.name,
    required this.quant,
    required this.bytes,
    required this.onDelete,
  });

  final String name;
  final String quant;
  final int bytes;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).brightness == Brightness.dark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 12.5)),
                Text(
                  '$quant · ${formatBytes(bytes)}',
                  style: TextStyle(fontSize: 10.5, color: secondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: onDelete,
            iconSize: 16,
            color: AppColors.error,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}
