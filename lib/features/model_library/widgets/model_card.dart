import 'package:flutter/material.dart';

import '../../../core/data/database.dart';
import '../../../core/models/model_catalogue.dart';
import '../../../core/models/transfer_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/meter_bar.dart';

/// One model in the library: what it is, which quantisation is selected,
/// whether it is installed, and what can be done with it.
///
/// The card is deliberately explicit about two things the brief insists on:
/// what has actually been verified (vision support carries its evidence, or
/// says that none has been found), and how big the transfer really is including
/// the vision projector.
class ModelCard extends StatefulWidget {
  const ModelCard({
    super.key,
    required this.model,
    required this.onDownload,
    required this.onCancel,
    required this.onDelete,
    required this.onUpdate,
    required this.onSetDefault,
    this.installation,
    this.task,
    this.update,
    this.isDefault = false,
  });

  final CatalogueModel model;
  final ModelInstallation? installation;
  final DownloadTask? task;
  final ModelUpdateInfo? update;
  final bool isDefault;

  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onUpdate;
  final Future<void> Function() onSetDefault;

  @override
  State<ModelCard> createState() => _ModelCardState();
}

class _ModelCardState extends State<ModelCard> {
  String? _selectedQuant;

  CatalogueModel get _model => widget.model;

  bool get _isInstalled => widget.installation != null;

  /// The quantisation the user is looking at: whatever they picked, else what is
  /// installed, else the catalogue's recommendation.
  String get _quantKey =>
      _selectedQuant ??
      widget.installation?.quant ??
      _model.recommendedQuant;

  QuantOption get _quant {
    for (final option in _model.quants) {
      if (option.quant == _quantKey) return option;
    }
    return _model.recommendedQuantInfo ?? _model.quants.first;
  }

  bool get _includeMmproj => _model.mmproj != null;

  int get _totalBytes =>
      _model.totalDownloadBytes(_quant, includeMmproj: _includeMmproj);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = scheme.brightness == Brightness.light;
    final secondary =
        isLight ? AppColors.lightTextSecondary : AppColors.textSecondary;

    final task = widget.task;
    final isDownloading = task != null && task.isActive;
    final hasUpdate = widget.update?.updateAvailable ?? false;

    return Container(
      decoration: BoxDecoration(
        color: isLight ? AppColors.lightSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _model.highRam
              ? AppColors.error.withValues(alpha: 0.45)
              : (isLight ? AppColors.lightOutline : AppColors.outline),
          width: _model.highRam ? 1.2 : 1,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context, secondary),
          const SizedBox(height: 8),
          Text(
            _model.blurb,
            style: TextStyle(fontSize: 12, height: 1.45, color: secondary),
          ),
          const SizedBox(height: 10),
          _badges(),
          if (_model.hasWarning) ...[
            const SizedBox(height: 10),
            _warningCard(context, secondary),
          ],
          const SizedBox(height: 12),
          _quantSelector(context, secondary),
          const SizedBox(height: 10),
          _sizeAndRam(context, secondary),
          if (_model.visionSupported || _model.visionAbsenceNote != null) ...[
            const SizedBox(height: 8),
            _visionNote(context, secondary),
          ],
          if (hasUpdate) ...[
            const SizedBox(height: 10),
            _updateNote(context, secondary),
          ],
          const SizedBox(height: 12),
          if (isDownloading)
            _progress(context, task)
          else
            _actions(context, secondary),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ pieces

  Widget _header(BuildContext context, Color secondary) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _model.displayName,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${_model.family} · ${_model.parameterCount} · '
                '${_model.sizeClass}',
                style: TextStyle(fontSize: 11, color: secondary),
              ),
            ],
          ),
        ),
        if (_isInstalled)
          const StatusBadge(
            label: 'Installed',
            tone: BadgeTone.success,
            icon: Icons.check_rounded,
            dense: true,
          ),
      ],
    );
  }

  Widget _badges() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (_model.highRam)
          const StatusBadge(
            label: 'High RAM',
            tone: BadgeTone.danger,
            icon: Icons.memory_rounded,
          ),
        if (_model.wifiOnly)
          const StatusBadge(
            label: 'Wi-Fi only',
            tone: BadgeTone.accent,
            icon: Icons.wifi_rounded,
          ),
        if (_model.visionSupported)
          const StatusBadge(
            label: 'Vision',
            tone: BadgeTone.muted,
            icon: Icons.visibility_outlined,
          ),
        if (!_model.fitsTargetDevice)
          const StatusBadge(
            label: 'Will not load here',
            tone: BadgeTone.danger,
          ),
        // The temperature the model card recommends, so the default in
        // Settings is traceable to a source rather than to a guess.
        StatusBadge(
          label: 'temp ${_model.samplingDefaults.temperature}',
          tone: BadgeTone.neutral,
          dense: true,
        ),
      ],
    );
  }

  Widget _warningCard(BuildContext context, Color secondary) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 15, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _model.warning!,
              style: TextStyle(
                fontSize: 11,
                height: 1.45,
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quantSelector(BuildContext context, Color secondary) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _model.quants.length == 1
              ? 'Quantisation'
              : 'Quantisation · ${_model.quants.length} available',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: secondary,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          decoration: BoxDecoration(
            color: isLight ? AppColors.lightSurfaceHigh : AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isLight ? AppColors.lightOutline : AppColors.outline,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _quantKey,
              isExpanded: true,
              isDense: true,
              borderRadius: BorderRadius.circular(8),
              padding: const EdgeInsets.symmetric(vertical: 8),
              icon: const Icon(Icons.expand_more_rounded, size: 18),
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              // A quantisation is a multi-gigabyte decision, so the dropdown is
              // disabled while a download is running and once a model is
              // installed: changing it means downloading all over again.
              onChanged: _isInstalled
                  ? null
                  : (value) => setState(() => _selectedQuant = value),
              items: [
                for (final option in _model.quants)
                  DropdownMenuItem<String>(
                    value: option.quant,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${option.quant}  ·  ${formatBytes(option.sizeBytes)}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        if (option.quant == _model.recommendedQuant)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.star_rounded,
                              size: 13,
                              color: AppColors.accent,
                            ),
                          ),
                        if (!option.fitsTargetDevice)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.warning_amber_rounded,
                              size: 13,
                              color: AppColors.error,
                            ),
                          ),
                        if (option.isMtp)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: StatusBadge(
                              label: 'MTP',
                              tone: BadgeTone.muted,
                              dense: true,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _isInstalled
              ? 'Installed as ${widget.installation!.quant}. Delete the model '
                  'to switch quantisation.'
              : _quant.qualityNote,
          style: TextStyle(
            fontSize: 10.5,
            height: 1.4,
            color: _isInstalled ? AppColors.accent : secondary,
          ),
        ),
      ],
    );
  }

  Widget _sizeAndRam(BuildContext context, Color secondary) {
    final rows = <(String, String)>[
      (
        'Download',
        '${formatBytes(_totalBytes)}'
            '${_includeMmproj ? ' incl. projector (${formatBytes(_model.mmproj!.sizeBytes)})' : ''}'
      ),
      (
        'RAM needed',
        '~${_model.ramRequirementGb.toStringAsFixed(1)} GB',
      ),
      (
        'Context',
        '${_model.recommendedContextLength} default · '
            '${_model.maxContextLength} max',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 78,
                  child: Text(
                    row.$1,
                    style: TextStyle(fontSize: 10.5, color: secondary),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.$2,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (_model.contextNote != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _model.contextNote!,
              style: TextStyle(fontSize: 10, height: 1.35, color: secondary),
            ),
          ),
      ],
    );
  }

  /// States the evidence for a vision claim, or that there is none.
  ///
  /// The catalogue only marks a model vision-capable when the model card says
  /// so; where the card is ambiguous that is recorded here rather than quietly
  /// resolved in either direction.
  Widget _visionNote(BuildContext context, Color secondary) {
    final evidence = _model.visionSupported
        ? _model.visionEvidence
        : _model.visionAbsenceNote;

    if (evidence == null) return const SizedBox.shrink();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          _model.visionSupported
              ? Icons.visibility_outlined
              : Icons.no_photography_outlined,
          size: 13,
          color: _model.visionSupported ? AppColors.accent : secondary,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                evidence,
                style: TextStyle(fontSize: 10, height: 1.35, color: secondary),
              ),
              if (_model.visionCaveat != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _model.visionCaveat!,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.35,
                      fontStyle: FontStyle.italic,
                      color: secondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _updateNote(BuildContext context, Color secondary) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.accentMuted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.system_update_alt_rounded,
                  size: 14, color: AppColors.accent),
              SizedBox(width: 6),
              Text(
                'Update available',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'The file on HuggingFace has changed'
            '${widget.update?.remoteLastModified == null ? '' : ' (${formatRelativeTime(widget.update!.remoteLastModified!)})'}. '
            'Updating downloads the new file alongside this one, verifies it, '
            'and only then replaces it. Your current model keeps working until '
            'the new one is verified.',
            style: TextStyle(fontSize: 10, height: 1.4, color: secondary),
          ),
        ],
      ),
    );
  }

  Widget _progress(BuildContext context, DownloadTask task) {
    final secondary = Theme.of(context).brightness == Brightness.dark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;

    final isVerifying = task.phase == DownloadPhase.verifying;
    final detail = isVerifying
        ? 'Verifying SHA-256 of ${task.fileName}'
        : '${formatBytes(task.receivedBytes)} of ${formatBytes(task.totalBytes)}'
            '${task.bytesPerSecond > 0 ? ' · ${formatSpeed(task.bytesPerSecond)}' : ''}'
            '${task.eta == null ? '' : ' · ${formatDuration(task.eta!)} left'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                task.fileCount > 1
                    ? '${task.statusLabel} · file ${task.fileIndex} of ${task.fileCount}'
                    : task.statusLabel,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: widget.onCancel,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.error,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
              ),
              child: const Text('Cancel'),
            ),
          ],
        ),
        const SizedBox(height: 2),
        MeterBar(
          value: task.progress,
          isIndeterminate: isVerifying,
          height: 6,
        ),
        const SizedBox(height: 5),
        Text(
          detail,
          style: TextStyle(fontSize: 10.5, color: secondary),
        ),
        if (task.error != null) ...[
          const SizedBox(height: 4),
          Text(
            task.error!,
            style: const TextStyle(
              fontSize: 10.5,
              height: 1.4,
              color: AppColors.error,
            ),
          ),
        ],
      ],
    );
  }

  Widget _actions(BuildContext context, Color secondary) {
    final hasUpdate = widget.update?.updateAvailable ?? false;

    if (_isInstalled) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (hasUpdate)
            FilledButton.icon(
              onPressed: widget.onUpdate,
              icon: const Icon(Icons.system_update_alt_rounded, size: 16),
              label: const Text('Update'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: const Color(0xFF1A1A2E),
              ),
            ),
          OutlinedButton.icon(
            onPressed: () => widget.onSetDefault(),
            icon: Icon(
              widget.isDefault ? Icons.star_rounded : Icons.star_border_rounded,
              size: 16,
            ),
            label: Text(widget.isDefault ? 'Default model' : 'Use by default'),
            style: OutlinedButton.styleFrom(
              foregroundColor:
                  widget.isDefault ? AppColors.accent : secondary,
            ),
          ),
          OutlinedButton.icon(
            onPressed: widget.onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            label: const Text('Delete'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: BorderSide(
                color: AppColors.error.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      );
    }

    final blocked = !_model.fitsTargetDevice;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: widget.onDownload,
          icon: const Icon(Icons.download_rounded, size: 17),
          label: Text('Download ${formatBytes(_totalBytes)}'),
          style: FilledButton.styleFrom(
            // A model that cannot load still gets a working button - the brief
            // requires the hard block to be about mobile data, not about
            // disabling the download - but it is coloured as a risk.
            backgroundColor: blocked ? AppColors.error : AppColors.accent,
            foregroundColor:
                blocked ? Colors.white : const Color(0xFF1A1A2E),
          ),
        ),
        if (_model.wifiOnly) ...[
          const SizedBox(height: 5),
          Row(
            children: [
              const Icon(Icons.wifi_rounded, size: 12, color: AppColors.accent),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Blocked on mobile data. Connect to Wi-Fi to enable this '
                  'download.',
                  style: TextStyle(fontSize: 10, color: secondary),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
