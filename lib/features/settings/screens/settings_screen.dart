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
import '../../../core/theme/claude_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/claude_sheet.dart';
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
          // The rows carry the 16 dp gutter themselves; a list inset on top of
          // that would put them 28 dp in while the sidebar sits at 16.
          padding: const EdgeInsets.only(bottom: ClaudeSpacing.xl),
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
    final tokens = context.tokens;
    final hasCustomPrompt = settings.systemPrompt != null;

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
        _SegmentedRow<ChatFontFamily>(
          label: 'Chat font',
          value: settings.chatFont,
          options: {
            for (final family in ChatFontFamily.values)
              family: family.label,
          },
          onChanged: controller.setChatFont,
        ),
        ClaudeRow(
          label: 'System prompt',
          subtitle: hasCustomPrompt
              ? _oneLine(settings.systemPrompt!)
              : 'Built-in study prompt',
          onTap: () => _editSystemPrompt(settings.systemPrompt),
          trailing: Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: tokens.mutedSoft,
          ),
        ),
        const _Note(
          'Both themes are designed rather than derived: the light theme is a '
          'warm paper surface, not an inverted dark one. The chat font applies '
          'to messages only, never to the app chrome.',
        ),
      ],
    );
  }

  /// A prompt shown as a row subtitle: one line, clipped sensibly.
  String _oneLine(String prompt) {
    final collapsed = prompt.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= 72) return collapsed;
    return '${collapsed.substring(0, 71)}…';
  }

  /// Edits the user's default system prompt.
  ///
  /// An empty field clears the override and returns to the built-in study
  /// prompt, which is what the dialog's second button does in one tap.
  Future<void> _editSystemPrompt(String? current) async {
    final next = await showDialog<String>(
      context: context,
      builder: (_) => _SystemPromptDialog(initial: current),
    );
    if (!mounted || next == null) return;
    await ref.read(settingsControllerProvider.notifier).setSystemPrompt(next);
  }

  // ------------------------------------------------------------ model/context

  Widget _modelSection(
    AppSettings settings,
    SettingsController controller,
    ModelCatalogue? catalogue,
    List<ModelInstallation> installs,
  ) {
    final tokens = context.tokens;
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
        const SizedBox(height: ClaudeSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: ClaudeSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Context length',
                      style: ClaudeType.bodySmall.copyWith(
                        color: tokens.bodyStrong,
                      ),
                    ),
                  ),
                  Text(
                    '$value total · '
                    '${AppConstants.perChatContextLength(value)} per '
                    'chat',
                    style: ClaudeType.caption.copyWith(
                      color: tokens.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Slider(
                value: value.toDouble(),
                min: min.toDouble(),
                max: max.toDouble(),
                // The usable range spans 512 to 262144, so a linear slider
                // would be unusable at the low end. Divisions pick round steps.
                divisions: _divisionsFor(min, max),
                label: '$value',
                onChanged: (next) => controller.setContextLength(next.round()),
                onChangeEnd: (next) =>
                    controller.setContextLength(next.round()),
              ),
              Row(
                children: [
                  Text(
                    '$min',
                    style: ClaudeType.caption.copyWith(color: tokens.muted),
                  ),
                  const Spacer(),
                  Text(
                    '$max',
                    style: ClaudeType.caption.copyWith(color: tokens.muted),
                  ),
                ],
              ),
            ],
          ),
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
            'The engine runs four llama.cpp slots per model and divides this '
            'between them, so each conversation gets a quarter of the number '
            'above. Memory is charged for the total, not the quarter.',
            tone: _NoteTone.honest,
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
        ClaudeRow(
          label: 'Check for model updates',
          subtitle: 'Asked at most once every 24 hours per model, when you '
              'reconnect to the internet, and only for models you have '
              'downloaded.',
          trailing: Switch(
            value: settings.autoUpdateCheckEnabled,
            onChanged: controller.setAutoUpdateCheck,
          ),
        ),
        const _Note(
          'A check only reads HuggingFace metadata. Updates are never '
          'downloaded automatically: when something has changed you get a '
          'badge and a banner, and the download starts only from the Update '
          'button. The 27B model is never checked on mobile data.',
          tone: _NoteTone.honest,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ClaudeSpacing.md,
            ClaudeSpacing.sm,
            ClaudeSpacing.md,
            0,
          ),
          child: Align(
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
    final tokens = context.tokens;
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
    // Resolved here rather than inside the row, because the subtitle colour has
    // to match the text: an access warning is not a description.
    final locationSubtitle = location.when(
      loading: () => 'Checking storage access…',
      error: (_, __) => 'App storage',
      data: (status) => '${status.displayName} · '
          '${formatBytes(status.bytesUsed)}'
          '${status.warning == null ? '' : '\n${status.warning}'}',
    );

    return _Section(
      title: 'Storage',
      children: [
        ClaudeRow(
          label: 'Model files location',
          subtitle: locationSubtitle,
          subtitleColor:
              storageStatus?.warning == null ? null : tokens.errorText,
          leading: const Icon(Icons.folder_open_outlined, size: 19),
          trailing: Icon(
            Icons.chevron_right_rounded,
            size: 19,
            color: tokens.mutedSoft,
          ),
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
          ClaudeRow(
            label: 'Use app storage',
            subtitle: 'Store future downloads in the app-private models '
                'folder.',
            leading: const Icon(Icons.phone_android_rounded, size: 18),
            onTap: () => _usePrivateModelStorage(
              context,
              installs: installs,
              catalogue: catalogue,
            ),
          ),
        if (installs.isEmpty)
          const _Note('No models are stored on this device.')
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ClaudeSpacing.md,
              vertical: ClaudeSpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Models on this device',
                    style: ClaudeType.bodySmall.copyWith(
                      color: tokens.bodyStrong,
                    ),
                  ),
                ),
                Text(
                  formatBytes(totalBytes),
                  style: ClaudeType.caption.copyWith(
                    color: tokens.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          for (final installation in installs)
            _StorageRow(
              name: catalogue?.byId(installation.modelId)?.displayName ??
                  installation.modelId,
              quant: installation.quant,
              bytes: installation.totalBytes,
              onDelete: () => _deleteModel(context, ref, installation),
            ),
          if (catalogue != null)
            ClaudeRow(
              label:
                  movePending ? 'Resume model move' : 'Move existing models',
              subtitle: movePending
                  ? 'Continues verified, per-model moves after an '
                      'interruption.'
                  : 'Copies installed models to the selected folder. '
                      'Originals stay until each copy verifies.',
              leading: Icon(
                movePending
                    ? Icons.play_arrow_rounded
                    : Icons.drive_file_move_outlined,
                size: 18,
              ),
              onTap: () => _runModelMove(
                context,
                installs: installs,
                catalogue: catalogue,
                resume: movePending,
              ),
            ),
        ],
        Divider(
          height: ClaudeSpacing.lg,
          thickness: 1,
          color: tokens.hairline,
        ),
        ClaudeRow(
          label: 'Export all conversations (ZIP of PDFs)',
          subtitle: 'Writes one PDF per conversation into a single archive.',
          leading: const Icon(Icons.folder_zip_outlined, size: 18),
          onTap: () => _exportEverything(context, ref),
        ),
        ClaudeRow(
          label: 'Clean up unfinished downloads',
          subtitle: 'Discards saved partial model files. Resume from the '
              'Model Library to keep and continue them.',
          leading: const Icon(Icons.cleaning_services_outlined, size: 18),
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
      if (!context.mounted) return;
      if (latestInstalls.isEmpty ||
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
        final activeDialogContext = dialogContext;
        if (activeDialogContext != null && activeDialogContext.mounted) {
          Navigator.of(activeDialogContext).pop();
        }
      },
      onError: (Object error, StackTrace stack) {
        final activeDialogContext = dialogContext;
        if (activeDialogContext != null && activeDialogContext.mounted) {
          Navigator.of(activeDialogContext).pop();
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
        // The diagnostics are key/value pairs, not rows: they read as one
        // block, so a single hairline closes the group instead of one rule per
        // pair.
        Divider(height: 1, thickness: 1, color: context.tokens.hairline),
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
    final tokens = context.tokens;
    final secondary = tokens.muted;

    return _Section(
      title: 'About',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ClaudeSpacing.md,
            vertical: ClaudeSpacing.xs,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(ClaudeSpacing.xs),
                decoration: BoxDecoration(
                  color: tokens.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(ClaudeRadius.lg),
                ),
                child: Icon(
                  Icons.auto_stories_rounded,
                  size: 22,
                  color: tokens.primary,
                ),
              ),
              const SizedBox(width: ClaudeSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppConstants.appName,
                      style: ClaudeType.bodySmall.copyWith(
                        color: tokens.bodyStrong,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      AppConstants.tagline,
                      style: ClaudeType.caption.copyWith(color: secondary),
                    ),
                    Text(
                      _version == null
                          ? 'Version unknown'
                          : 'Version $_version',
                      style: ClaudeType.caption.copyWith(color: secondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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

/// A Settings group: an uppercase header over a flat, hairline-separated list.
///
/// The same header the sidebar uses, so the two lists read as one system. There
/// is no card and no border: the group sits directly on the canvas and the rows
/// draw the only horizontal rules on the screen.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClaudeSectionHeader(
          title: title,
          padding: const EdgeInsets.fromLTRB(
            ClaudeSpacing.md,
            ClaudeSpacing.lg,
            ClaudeSpacing.md,
            ClaudeSpacing.xs,
          ),
        ),
        ...children,
      ],
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ClaudeSpacing.md,
        6,
        ClaudeSpacing.md,
        6,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: ClaudeType.caption.copyWith(color: tokens.muted),
            ),
          ),
          const SizedBox(width: ClaudeSpacing.sm),
          Expanded(
            child: SelectableText(
              value,
              style: ClaudeType.code.copyWith(color: tokens.body),
            ),
          ),
        ],
      ),
    );
  }
}

/// The system-prompt editor.
///
/// Returns the new prompt, or an empty string for "back to the built-in study
/// prompt". `null` means the user cancelled.
class _SystemPromptDialog extends StatefulWidget {
  const _SystemPromptDialog({this.initial});

  final String? initial;

  @override
  State<_SystemPromptDialog> createState() => _SystemPromptDialogState();
}

class _SystemPromptDialogState extends State<_SystemPromptDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isCustom = widget.initial != null;

    return AlertDialog(
      backgroundColor: tokens.surfaceCard,
      title: Text(
        'System prompt',
        style: ClaudeType.titleSmall.copyWith(color: tokens.bodyStrong),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sent before every conversation. Leave it empty to use the '
              'built-in study prompt.',
              style: ClaudeType.caption.copyWith(color: tokens.muted),
            ),
            const SizedBox(height: ClaudeSpacing.sm),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 4,
              maxLines: 8,
              maxLength: 2000,
              style: ClaudeType.bodySmall.copyWith(color: tokens.bodyStrong),
              decoration: InputDecoration(
                hintText: 'e.g. You are a patient tutor. Answer in short '
                    'paragraphs and always define new terms.',
                hintStyle: ClaudeType.bodySmall.copyWith(
                  color: tokens.mutedSoft,
                ),
                counterStyle: ClaudeType.caption.copyWith(
                  color: tokens.mutedSoft,
                ),
              ),
            ),
            if (isCustom)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(''),
                  child: const Text('Reset to built-in prompt'),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
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
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final base = tokens.muted;

    final (color, background, border) = switch (tone) {
      _NoteTone.normal => (base, Colors.transparent, Colors.transparent),
      _NoteTone.honest => (
          base,
          tokens.primary.withValues(alpha: 0.05),
          tokens.primary.withValues(alpha: 0.22),
        ),
      _NoteTone.warning => (
          isDark ? tokens.warning : tokens.errorText,
          tokens.warning.withValues(alpha: 0.08),
          tokens.warning.withValues(alpha: 0.3),
        ),
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(
        ClaudeSpacing.md,
        ClaudeSpacing.xs,
        ClaudeSpacing.md,
        ClaudeSpacing.xxs,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: ClaudeSpacing.xs,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(ClaudeRadius.md),
        border: Border.all(color: border),
      ),
      child: Text(text, style: ClaudeType.caption.copyWith(color: color)),
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
    return ClaudeRow(
      label: label,
      trailing: SegmentedButton<T>(
        segments: [
          for (final entry in options.entries)
            ButtonSegment<T>(value: entry.key, label: Text(entry.value)),
        ],
        selected: {value},
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          textStyle: WidgetStatePropertyAll(ClaudeType.button),
        ),
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
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
    final tokens = context.tokens;

    return ClaudeRow(
      label: label,
      trailing: SizedBox(
        width: 168,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: items.containsKey(value) ? value : items.keys.first,
            isExpanded: true,
            isDense: true,
            alignment: Alignment.centerRight,
            icon: Icon(
              Icons.unfold_more_rounded,
              size: 18,
              color: tokens.muted,
            ),
            style: ClaudeType.bodySmall.copyWith(color: tokens.bodyStrong),
            dropdownColor: tokens.surfaceCard,
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
                    textAlign: TextAlign.right,
                    style: ClaudeType.bodySmall.copyWith(
                      color: tokens.bodyStrong,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
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
    final tokens = context.tokens;
    final clamped = value.clamp(min, max);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ClaudeSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: ClaudeType.bodySmall.copyWith(
                    color: tokens.bodyStrong,
                  ),
                ),
              ),
              Text(
                display,
                style: ClaudeType.caption.copyWith(
                  color: tokens.primary,
                  fontWeight: FontWeight.w700,
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
      ),
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
    final tokens = context.tokens;

    return ClaudeRow(
      label: name,
      subtitle: '$quant · ${formatBytes(bytes)}',
      trailing: IconButton(
        tooltip: 'Delete',
        onPressed: onDelete,
        iconSize: 18,
        color: tokens.errorText,
        icon: const Icon(Icons.delete_outline_rounded),
      ),
    );
  }
}
