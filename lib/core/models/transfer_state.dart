import 'package:flutter/foundation.dart';

/// Where a download has got to.
enum DownloadPhase {
  queued,

  /// Waiting for the user to accept a blocking confirmation (the 27B on
  /// mobile data, or a model that will not fit in RAM).
  awaitingConfirmation,

  downloading,

  /// Bytes are on disk; SHA-256 verification is running.
  verifying,

  complete,

  failed,

  cancelled,
}

/// Live state of one model download, as shown on the model card.
@immutable
class DownloadTask {
  const DownloadTask({
    required this.modelId,
    required this.quant,
    required this.fileName,
    required this.totalBytes,
    this.receivedBytes = 0,
    this.phase = DownloadPhase.queued,
    this.bytesPerSecond = 0,
    this.eta,
    this.error,
    this.detail,
    this.includesMmproj = false,
    this.fileIndex = 1,
    this.fileCount = 1,
  });

  final String modelId;
  final String quant;
  final String fileName;

  /// Bytes for the file currently transferring.
  final int totalBytes;
  final int receivedBytes;

  final DownloadPhase phase;
  final double bytesPerSecond;
  final Duration? eta;
  final String? error;
  final String? detail;

  /// True when a vision projector is part of this download, so the progress
  /// bar can say "file 2 of 2" rather than silently restarting at zero.
  final bool includesMmproj;
  final int fileIndex;
  final int fileCount;

  /// 0..1 for the file currently transferring.
  double get progress {
    if (totalBytes <= 0) return 0;
    final value = receivedBytes / totalBytes;
    return value.clamp(0.0, 1.0);
  }

  bool get isActive =>
      phase == DownloadPhase.downloading ||
      phase == DownloadPhase.verifying ||
      phase == DownloadPhase.awaitingConfirmation;

  bool get isTerminal =>
      phase == DownloadPhase.complete ||
      phase == DownloadPhase.failed ||
      phase == DownloadPhase.cancelled;

  String get statusLabel {
    switch (phase) {
      case DownloadPhase.queued:
        return 'Queued';
      case DownloadPhase.awaitingConfirmation:
        return 'Waiting for confirmation';
      case DownloadPhase.downloading:
        return 'Downloading';
      case DownloadPhase.verifying:
        return 'Verifying checksum';
      case DownloadPhase.complete:
        return 'Ready';
      case DownloadPhase.failed:
        return 'Download failed';
      case DownloadPhase.cancelled:
        return 'Paused';
    }
  }

  DownloadTask copyWith({
    String? fileName,
    int? totalBytes,
    int? receivedBytes,
    DownloadPhase? phase,
    double? bytesPerSecond,
    Duration? eta,
    bool clearEta = false,
    String? error,
    bool clearError = false,
    String? detail,
    bool? includesMmproj,
    int? fileIndex,
    int? fileCount,
  }) =>
      DownloadTask(
        modelId: modelId,
        quant: quant,
        fileName: fileName ?? this.fileName,
        totalBytes: totalBytes ?? this.totalBytes,
        receivedBytes: receivedBytes ?? this.receivedBytes,
        phase: phase ?? this.phase,
        bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
        eta: clearEta ? null : (eta ?? this.eta),
        error: clearError ? null : (error ?? this.error),
        detail: detail ?? this.detail,
        includesMmproj: includesMmproj ?? this.includesMmproj,
        fileIndex: fileIndex ?? this.fileIndex,
        fileCount: fileCount ?? this.fileCount,
      );
}

/// Result of one auto-update check for one model.
///
/// Presence of this object never causes a download. It only drives the badge
/// and the dismissible banner.
@immutable
class ModelUpdateInfo {
  const ModelUpdateInfo({
    required this.modelId,
    required this.updateAvailable,
    this.lastCheckedAt,
    this.remoteSha,
    this.remoteLastModified,
    this.error,
  });

  const ModelUpdateInfo.unknown(this.modelId)
      : updateAvailable = false,
        lastCheckedAt = null,
        remoteSha = null,
        remoteLastModified = null,
        error = null;

  final String modelId;
  final bool updateAvailable;
  final DateTime? lastCheckedAt;
  final String? remoteSha;
  final DateTime? remoteLastModified;

  /// Set when the check could not complete. Offline is *not* an error and is
  /// never recorded here - it is a silent skip.
  final String? error;
}
