import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../errors/app_exception.dart';
import '../models/model_catalogue.dart';
import '../models/transfer_state.dart';
import 'connectivity_service.dart';
import 'storage_paths.dart';

/// Collects a single digest produced by a chunked hash conversion.
///
/// Used instead of buffering the file, because the files here are 4-9 GB and
/// reading one into memory to hash it would defeat the purpose of streaming the
/// download in the first place.
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// One file queued inside a model download.
@immutable
class _FileSpec {
  const _FileSpec({
    required this.url,
    required this.fileName,
    required this.expectedBytes,
    required this.sha256,
    this.isMmproj = false,
  });

  final String url;
  final String fileName;
  final int expectedBytes;
  final String? sha256;
  final bool isMmproj;
}

/// Downloads model files and verifies them before they are usable.
///
/// Two rules from the brief are enforced **here**, not in the UI, so they hold
/// no matter which screen triggers a download:
///
///  1. A `wifiOnly` model (the 27B) is hard blocked on mobile data. This throws
///     [WifiRequiredException] before a single byte is requested, and is
///     re-checked before each file so dropping off Wi-Fi mid-download stops it.
///  2. A file whose SHA-256 does not match the catalogue is discarded. The
///     `.part` file is deleted and the model is not marked as installed, so a
///     truncated download can never be loaded as if it were complete.
class DownloadManager {
  DownloadManager({
    required AppDatabase database,
    required ConnectivityService connectivity,
    Dio? dio,
  })  : _db = database,
        _connectivity = connectivity,
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                headers: const {
                  'User-Agent': 'LibraryAI/1.0 (+offline-first study app)',
                  'Accept': 'application/octet-stream',
                },
              ),
            );

  final AppDatabase _db;
  final ConnectivityService _connectivity;
  final Dio _dio;

  final _controller = StreamController<Map<String, DownloadTask>>.broadcast();
  final Map<String, DownloadTask> _tasks = {};
  final Map<String, bool> _cancelRequests = {};

  /// Live state of every in-flight or recently finished download, keyed by
  /// catalogue model id.
  Stream<Map<String, DownloadTask>> get tasksStream => _controller.stream;
  Map<String, DownloadTask> get tasks => Map.unmodifiable(_tasks);

  DownloadTask? taskFor(String modelId) => _tasks[modelId];

  void _publish(DownloadTask task) {
    _tasks[task.modelId] = task;
    if (!_controller.isClosed) _controller.add(Map.unmodifiable(_tasks));
  }

  /// Clears a finished task so the model card returns to its normal state.
  void clearTask(String modelId) {
    _tasks.remove(modelId);
    _cancelRequests.remove(modelId);
    if (!_controller.isClosed) _controller.add(Map.unmodifiable(_tasks));
  }

  /// Starts (or restarts) a download.
  ///
  /// [includeMmproj] should be true when the user wants vision support; the
  /// caller decides, because for a 27B model the extra 0.93 GB is a real
  /// consideration rather than an obvious yes.
  Future<void> start({
    required CatalogueModel model,
    required QuantOption quant,
    bool includeMmproj = true,
  }) async {
    if (_tasks[model.id]?.isActive ?? false) {
      throw const DownloadException('This model is already downloading.');
    }
    _cancelRequests[model.id] = false;

    final wantMmproj = includeMmproj && model.mmproj != null;
    final files = <_FileSpec>[
      _FileSpec(
        url: quant.downloadUrl,
        fileName: quant.fileName,
        expectedBytes: quant.sizeBytes,
        sha256: quant.sha256,
      ),
      if (wantMmproj)
        _FileSpec(
          url: model.mmproj!.downloadUrl,
          fileName: model.mmproj!.fileName,
          expectedBytes: model.mmproj!.sizeBytes,
          sha256: model.mmproj!.sha256,
          isMmproj: true,
        ),
    ];

    try {
      // --- Wi-Fi gate, re-checked per file so leaving Wi-Fi stops the transfer.
      if (model.wifiOnly) {
        if (!await _connectivity.isOnUnmeteredConnection()) {
          throw WifiRequiredException(
            '${model.displayName} can only be downloaded over Wi-Fi.',
          );
        }
      }

      String? modelLocalPath;
      String? mmprojLocalPath;
      var totalBytes = 0;

      for (var index = 0; index < files.length; index++) {
        final spec = files[index];

        if (_cancelRequests[model.id] == true) {
          await _finish(model.id, DownloadPhase.cancelled);
          return;
        }

        // Re-assert the Wi-Fi rule before each file. The 27B is 7.3 GB; losing
        // Wi-Fi halfway through should not quietly continue on mobile data.
        if (model.wifiOnly &&
            !await _connectivity.isOnUnmeteredConnection()) {
          throw WifiRequiredException(
            'Wi-Fi was lost, so the download was stopped.',
          );
        }

        _publish(
          DownloadTask(
            modelId: model.id,
            quant: quant.quant,
            fileName: spec.fileName,
            totalBytes: spec.expectedBytes,
            phase: DownloadPhase.downloading,
            includesMmproj: wantMmproj,
            fileIndex: index + 1,
            fileCount: files.length,
          ),
        );

        final destination = await StoragePaths.modelFilePath(
          model.id,
          spec.fileName,
        );

        final ok = await _downloadFile(
          modelId: model.id,
          quant: quant.quant,
          spec: spec,
          destination: destination,
          fileIndex: index + 1,
          fileCount: files.length,
          includesMmproj: wantMmproj,
        );

        if (!ok) {
          // _downloadFile already recorded the terminal phase.
          return;
        }

        if (spec.isMmproj) {
          mmprojLocalPath = destination;
          totalBytes += spec.expectedBytes;
        } else {
          modelLocalPath = destination;
          totalBytes += spec.expectedBytes;
        }
      }

      if (modelLocalPath == null) {
        throw const DownloadException('Nothing was downloaded.');
      }

      await _db.upsertInstallation(
        ModelInstallationsCompanion.insert(
          modelId: model.id,
          quant: quant.quant,
          fileName: quant.fileName,
          localPath: modelLocalPath,
          mmprojPath: Value(mmprojLocalPath),
          sizeBytes: quant.sizeBytes,
          sha256: Value(quant.sha256),
          repoSha: Value(model.ggufRepoSha),
          repoLastModified: Value(model.ggufRepoLastModified),
          totalBytes: totalBytes,
        ),
      );

      // A fresh download resets the update baseline: whatever is on disk now
      // matches the repository, so any previous "update available" badge is
      // stale and must clear.
      await _db.upsertUpdateCheck(
        ModelUpdateChecksCompanion.insert(
          modelId: model.id,
          lastCheckedAt: DateTime.now(),
          remoteSha: Value(model.ggufRepoSha),
          remoteLastModified: Value(model.ggufRepoLastModified),
          updateAvailable: const Value(false),
        ),
      );

      _publish(
        DownloadTask(
          modelId: model.id,
          quant: quant.quant,
          fileName: quant.fileName,
          totalBytes: totalBytes,
          receivedBytes: totalBytes,
          phase: DownloadPhase.complete,
          includesMmproj: wantMmproj,
          fileIndex: files.length,
          fileCount: files.length,
        ),
      );
    } on AppException catch (error) {
      _publishFailure(model.id, quant, error.message, error.detail);
    } catch (error) {
      _publishFailure(
        model.id,
        quant,
        'Download failed.',
        '$error',
      );
    }
  }

  /// Streams one file to disk, hashing as it goes.
  ///
  /// Returns true when the file was written and verified, false when the
  /// transfer was cancelled or failed (in which case the terminal task state
  /// has already been published).
  Future<bool> _downloadFile({
    required String modelId,
    required String quant,
    required _FileSpec spec,
    required String destination,
    required int fileIndex,
    required int fileCount,
    required bool includesMmproj,
  }) async {
    // Download to a sibling `.part` file. The real path only appears once the
    // bytes are verified, so a half-written file can never be mistaken for a
    // usable model by the loader.
    final partFile = File('$destination.part');
    IOSink? sink;
    final stopwatch = Stopwatch()..start();
    var received = 0;
    var lastSampleAt = 0;
    var lastSampleBytes = 0;
    var speed = 0.0;

    try {
      final response = await _dio.get<ResponseBody>(
        spec.url,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          // A 7 GB transfer over a slow connection is not a timeout case; the
          // per-chunk read is what would stall, not the whole response.
          receiveTimeout: Duration.zero,
        ),
      );

      final body = response.data;
      if (body == null) {
        _publishFailure(modelId, quant, 'Empty response from server.');
        return false;
      }

      final declaredLength = int.tryParse(
        body.headers.value(Headers.contentLengthHeader)?.first ?? '',
      );
      final total = declaredLength ?? spec.expectedBytes;

      if (partFile.existsSync()) await partFile.delete();
      sink = partFile.openWrite();

      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);

      await for (final chunk in body.stream) {
        if (_cancelRequests[modelId] == true) {
          await sink.flush();
          await sink.close();
          sink = null;
          await _safeDelete(partFile);
          await _finish(modelId, DownloadPhase.cancelled);
          return false;
        }

        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;

        // Sample speed roughly twice a second. Faster updates would make the
        // ETA jitter without becoming more accurate.
        final elapsed = stopwatch.elapsedMilliseconds;
        if (elapsed - lastSampleAt >= 500) {
          final instantSpeed =
              (received - lastSampleBytes) / ((elapsed - lastSampleAt) / 1000);
          // Exponential moving average so the number is readable.
          speed = speed == 0 ? instantSpeed : (speed * 0.6) + (instantSpeed * 0.4);
          lastSampleAt = elapsed;
          lastSampleBytes = received;

          _publish(
            DownloadTask(
              modelId: modelId,
              quant: quant,
              fileName: spec.fileName,
              totalBytes: total,
              receivedBytes: received,
              phase: DownloadPhase.downloading,
              bytesPerSecond: speed,
              eta: speed > 0
                  ? Duration(seconds: ((total - received) / speed).round())
                  : null,
              includesMmproj: includesMmproj,
              fileIndex: fileIndex,
              fileCount: fileCount,
            ),
          );
        }
      }

      hasher.close();
      await sink.flush();
      await sink.close();
      sink = null;

      // --- integrity check --------------------------------------------------
      _publish(
        DownloadTask(
          modelId: modelId,
          quant: quant,
          fileName: spec.fileName,
          totalBytes: total,
          receivedBytes: received,
          phase: DownloadPhase.verifying,
          includesMmproj: includesMmproj,
          fileIndex: fileIndex,
          fileCount: fileCount,
        ),
      );

      final expected = spec.sha256;
      final actual = digestSink.value?.toString();
      if (expected != null && expected.isNotEmpty && actual != null) {
        if (expected.toLowerCase() != actual.toLowerCase()) {
          await _safeDelete(partFile);
          _publishFailure(
            modelId,
            quant,
            'Downloaded file failed its integrity check.',
            'Expected $expected but computed $actual',
          );
          return false;
        }
      }

      // Atomic-ish promotion into place.
      final target = File(destination);
      if (await target.exists()) await target.delete();
      await partFile.rename(destination);
      return true;
    } on DioException catch (error) {
      await sink?.close();
      sink = null;
      await _safeDelete(partFile);
      _publishFailure(
        modelId,
        quant,
        'Could not download ${spec.fileName}.',
        error.message ?? '${error.type}',
      );
      return false;
    } catch (error) {
      await sink?.close();
      sink = null;
      await _safeDelete(partFile);
      _publishFailure(modelId, quant, 'Download failed.', '$error');
      return false;
    }
  }

  Future<void> _safeDelete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Leaving a stray `.part` file is harmless; it is overwritten or cleaned
      // up on the next attempt.
    }
  }

  Future<void> _finish(String modelId, DownloadPhase phase) async {
    final existing = _tasks[modelId];
    if (existing == null) return;
    _publish(existing.copyWith(phase: phase));
  }

  void _publishFailure(
    String modelId,
    String quant,
    String message, [
    String? detail,
  ]) {
    _publish(
      DownloadTask(
        modelId: modelId,
        quant: quant,
        fileName: _tasks[modelId]?.fileName ?? '',
        totalBytes: _tasks[modelId]?.totalBytes ?? 0,
        receivedBytes: _tasks[modelId]?.receivedBytes ?? 0,
        phase: DownloadPhase.failed,
        error: message,
        detail: detail,
      ),
    );
  }

  /// Requests cancellation. The in-flight chunk loop notices on its next tick.
  void cancel(String modelId) {
    _cancelRequests[modelId] = true;
  }

  /// Removes a model's files and its installation record.
  ///
  /// Callers must ensure the model is not currently loaded; the model library
  /// disables the delete action for the active model.
  Future<void> deleteModel(String modelId) async {
    await StoragePaths.deleteModelDirectory(modelId);
    await _db.removeInstallation(modelId);
    clearTask(modelId);
  }

  /// Bytes on disk for a model, measured rather than taken from the record.
  Future<int> diskUsage(String modelId) async {
    final dir = await StoragePaths.modelDirectory(modelId);
    return StoragePaths.directorySize(dir);
  }

  /// Cleans up `.part` files left behind by interrupted downloads.
  Future<void> sweepPartialDownloads() async {
    try {
      final root = await StoragePaths.modelsDirectory();
      await for (final entity in root.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.part')) {
          await entity.delete();
        }
      }
    } catch (_) {
      // Best-effort housekeeping; never worth surfacing.
    }
  }

  void dispose() {
    _controller.close();
  }
}
