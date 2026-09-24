import 'dart:async';

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

class _DownloadCancelledException implements Exception {
  const _DownloadCancelledException();
}

class _InvalidDownloadResponseException implements Exception {
  const _InvalidDownloadResponseException(this.message);

  final String message;
}

@immutable
class _ParsedContentRange {
  const _ParsedContentRange({
    required this.start,
    required this.end,
    required this.total,
  });

  final int start;
  final int end;
  final int total;
}

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
    required StoragePaths storagePaths,
    Dio? dio,
  })  : _db = database,
        _connectivity = connectivity,
        _storagePaths = storagePaths,
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
  final StoragePaths _storagePaths;
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
          throw const WifiRequiredException(
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

        final destination = await _storagePaths.modelFileTarget(
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

        final locator = await _storagePaths.modelFileLocator(destination);
        if (spec.isMmproj) {
          mmprojLocalPath = locator;
          totalBytes += spec.expectedBytes;
        } else {
          modelLocalPath = locator;
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
      _publishFailure(
        model.id,
        quant.quant,
        error.message,
        detail: error.detail,
      );
    } catch (error) {
      _publishFailure(
        model.id,
        quant.quant,
        'Download failed.',
        detail: '$error',
      );
    }
  }

  /// Streams one file to the active storage backend, hashing as it goes.
  ///
  /// Returns true when the file was written and verified, false when the
  /// transfer was cancelled or failed (in which case the terminal task state
  /// has already been published).
  Future<bool> _downloadFile({
    required String modelId,
    required String quant,
    required _FileSpec spec,
    required ModelFileTarget destination,
    required int fileIndex,
    required int fileCount,
    required bool includesMmproj,
    bool forceRestart = false,
  }) async {
    if (_cancelRequests[modelId] == true) {
      await _finish(modelId, DownloadPhase.cancelled);
      return false;
    }

    if (forceRestart) await _storagePaths.deleteModelPart(destination);
    var existingBytes = await _storagePaths.modelPartSize(destination);
    if (existingBytes > spec.expectedBytes) {
      await _storagePaths.deleteModelPart(destination);
      existingBytes = 0;
    }

    // A process may have been killed after receiving the final byte but before
    // promotion. Verify such a complete part locally instead of downloading it
    // again. The catalogue SHA-256 is required before promoting it.
    final expected = spec.sha256;
    if (existingBytes == spec.expectedBytes && existingBytes > 0) {
      final partLocator = await _storagePaths.modelPartLocator(destination);
      if (partLocator != null && expected != null && expected.isNotEmpty) {
        _publish(
          DownloadTask(
            modelId: modelId,
            quant: quant,
            fileName: spec.fileName,
            totalBytes: spec.expectedBytes,
            receivedBytes: existingBytes,
            phase: DownloadPhase.verifying,
            includesMmproj: includesMmproj,
            fileIndex: fileIndex,
            fileCount: fileCount,
          ),
        );
        final actual = await _storagePaths.sha256Of(partLocator);
        if (actual.toLowerCase() == expected.toLowerCase()) {
          await _storagePaths.promoteModelPart(destination);
          return true;
        }
      }
      await _storagePaths.deleteModelPart(destination);
      existingBytes = 0;
    }

    final stopwatch = Stopwatch()..start();
    var received = 0;
    var newBytesReceived = 0;
    var lastSampleAt = 0;
    var lastSampleBytes = 0;
    var speed = 0.0;

    try {
      _publish(
        DownloadTask(
          modelId: modelId,
          quant: quant,
          fileName: spec.fileName,
          totalBytes: spec.expectedBytes,
          receivedBytes: existingBytes,
          phase: DownloadPhase.downloading,
          includesMmproj: includesMmproj,
          fileIndex: fileIndex,
          fileCount: fileCount,
        ),
      );

      final response = await _dio.get<ResponseBody>(
        spec.url,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          headers: {
            if (existingBytes > 0) 'Range': 'bytes=$existingBytes-',
          },
          // This is an inactivity timeout, not a total transfer deadline. A
          // healthy slow stream may run for hours; a stalled stream fails but
          // keeps its flushed bytes for the next Range retry.
          receiveTimeout: const Duration(minutes: 2),
        ),
      );

      final body = response.data;
      if (body == null) {
        _publishFailure(modelId, quant, 'Empty response from server.');
        return false;
      }

      final statusCode = response.statusCode;
      var append = false;
      var prefixBytes = 0;
      if (statusCode == 206) {
        final contentRange = _parseContentRange(
          _responseHeader(body.headers, 'content-range'),
        );
        if (contentRange == null ||
            contentRange.start != existingBytes ||
            contentRange.end != spec.expectedBytes - 1 ||
            contentRange.total != spec.expectedBytes) {
          await _discardResponseBody(body);
          if (!forceRestart) {
            await _storagePaths.deleteModelPart(destination);
            return _downloadFile(
              modelId: modelId,
              quant: quant,
              spec: spec,
              destination: destination,
              fileIndex: fileIndex,
              fileCount: fileCount,
              includesMmproj: includesMmproj,
              forceRestart: true,
            );
          }
          _publishFailure(
            modelId,
            quant,
            'The server returned an invalid resumed download.',
            detail: _responseHeader(body.headers, 'content-range'),
          );
          return false;
        }
        append = existingBytes > 0;
        prefixBytes = existingBytes;
      } else if (statusCode != 200) {
        _publishFailure(
          modelId,
          quant,
          'Unexpected response while downloading ${spec.fileName}.',
          detail: 'HTTP status $statusCode',
        );
        return false;
      }
      // A 200 response means the server ignored Range. The stream below
      // overwrites the old partial file and starts a clean digest.

      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      received = prefixBytes;
      if (append && prefixBytes > 0) {
        var hashedPrefixBytes = 0;
        await for (final chunk in _storagePaths.readModelPart(destination)) {
          if (_cancelRequests[modelId] == true) {
            hasher.close();
            await _finish(
              modelId,
              DownloadPhase.cancelled,
              receivedBytes: hashedPrefixBytes,
            );
            return false;
          }
          hasher.add(chunk);
          hashedPrefixBytes += chunk.length;
        }
        if (hashedPrefixBytes != prefixBytes) {
          hasher.close();
          await _discardResponseBody(body);
          if (!forceRestart) {
            await _storagePaths.deleteModelPart(destination);
            return _downloadFile(
              modelId: modelId,
              quant: quant,
              spec: spec,
              destination: destination,
              fileIndex: fileIndex,
              fileCount: fileCount,
              includesMmproj: includesMmproj,
              forceRestart: true,
            );
          }
          _publishFailure(
            modelId,
            quant,
            'The saved partial file could not be read.',
          );
          return false;
        }
      }

      Stream<List<int>> monitoredStream() async* {
        await for (final chunk in body.stream) {
          if (_cancelRequests[modelId] == true) {
            throw const _DownloadCancelledException();
          }
          if (received + chunk.length > spec.expectedBytes) {
            throw const _InvalidDownloadResponseException(
              'The server returned more bytes than the catalogue file size.',
            );
          }

          hasher.add(chunk);
          received += chunk.length;
          newBytesReceived += chunk.length;

          // Sample speed roughly twice a second. Faster updates would make the
          // ETA jitter without becoming more accurate.
          final elapsed = stopwatch.elapsedMilliseconds;
          if (elapsed - lastSampleAt >= 500) {
            final instantSpeed =
                (newBytesReceived - lastSampleBytes) /
                    ((elapsed - lastSampleAt) / 1000);
            speed = speed == 0
                ? instantSpeed
                : (speed * 0.6) + (instantSpeed * 0.4);
            lastSampleAt = elapsed;
            lastSampleBytes = newBytesReceived;

            _publish(
              DownloadTask(
                modelId: modelId,
                quant: quant,
                fileName: spec.fileName,
                totalBytes: spec.expectedBytes,
                receivedBytes: received,
                phase: DownloadPhase.downloading,
                bytesPerSecond: speed,
                eta: speed > 0
                    ? Duration(
                        seconds: ((spec.expectedBytes - received) / speed)
                            .round(),
                      )
                    : null,
                includesMmproj: includesMmproj,
                fileIndex: fileIndex,
                fileCount: fileCount,
              ),
            );
          }
          yield chunk;
        }
      }

      await _storagePaths.writeModelPart(
        destination,
        monitoredStream(),
        append: append,
      );
      if (_cancelRequests[modelId] == true) {
        await _finish(
          modelId,
          DownloadPhase.cancelled,
          receivedBytes: received,
        );
        return false;
      }
      hasher.close();

      // A cleanly closed but short body is still incomplete. Keep it so the
      // next user retry can request the remaining byte range.
      if (received != spec.expectedBytes) {
        _publishFailure(
          modelId,
          quant,
          'The download stopped before the file was complete.',
          detail: 'Received $received of ${spec.expectedBytes} bytes.',
          receivedBytes: received,
        );
        return false;
      }

      _publish(
        DownloadTask(
          modelId: modelId,
          quant: quant,
          fileName: spec.fileName,
          totalBytes: spec.expectedBytes,
          receivedBytes: received,
          phase: DownloadPhase.verifying,
          includesMmproj: includesMmproj,
          fileIndex: fileIndex,
          fileCount: fileCount,
        ),
      );

      final actual = digestSink.value?.toString();
      if (expected != null && expected.isNotEmpty && actual != null) {
        if (expected.toLowerCase() != actual.toLowerCase()) {
          await _storagePaths.deleteModelPart(destination);
          if (append && !forceRestart) {
            return _downloadFile(
              modelId: modelId,
              quant: quant,
              spec: spec,
              destination: destination,
              fileIndex: fileIndex,
              fileCount: fileCount,
              includesMmproj: includesMmproj,
              forceRestart: true,
            );
          }
          _publishFailure(
            modelId,
            quant,
            'Downloaded file failed its integrity check.',
            detail: 'Expected $expected but computed $actual',
          );
          return false;
        }
      }

      await _storagePaths.promoteModelPart(destination);
      return true;
    } on _DownloadCancelledException {
      // Cancellation acts as pause: the flushed `.part` remains available for
      // the next explicit retry.
      await _finish(
        modelId,
        DownloadPhase.cancelled,
        receivedBytes: received,
      );
      return false;
    } on _InvalidDownloadResponseException catch (error) {
      await _storagePaths.deleteModelPart(destination);
      _publishFailure(
        modelId,
        quant,
        'The server returned an invalid model file.',
        detail: error.message,
      );
      return false;
    } on DioException catch (error) {
      if (error.response?.statusCode == 416 &&
          existingBytes > 0 &&
          !forceRestart) {
        await _storagePaths.deleteModelPart(destination);
        return _downloadFile(
          modelId: modelId,
          quant: quant,
          spec: spec,
          destination: destination,
          fileIndex: fileIndex,
          fileCount: fileCount,
          includesMmproj: includesMmproj,
          forceRestart: true,
        );
      }
      // Network errors, timeouts, and user pauses deliberately keep the bytes
      // already written to `.part`; a retry will validate and resume them.
      _publishFailure(
        modelId,
        quant,
        'Could not download ${spec.fileName}.',
        detail: error.message ?? '${error.type}',
        receivedBytes: received,
      );
      return false;
    } catch (error) {
      // If storage itself failed, preserve whatever was flushed. The next
      // attempt validates the full prefix against the catalogue SHA-256.
      _publishFailure(
        modelId,
        quant,
        'Download failed.',
        detail: '$error',
        receivedBytes: received,
      );
      return false;
    }
  }

  Future<void> _discardResponseBody(ResponseBody body) async {
    final subscription = body.stream.listen((_) {});
    await subscription.cancel();
  }

  String? _responseHeader(Map<String, List<String>> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase() &&
          entry.value.isNotEmpty) {
        return entry.value.first;
      }
    }
    return null;
  }

  _ParsedContentRange? _parseContentRange(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^bytes\s+(\d+)-(\d+)/(\d+)$', caseSensitive: false)
        .firstMatch(value.trim());
    if (match == null) return null;
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    final total = int.tryParse(match.group(3)!);
    if (start == null || end == null || total == null || end < start) {
      return null;
    }
    return _ParsedContentRange(start: start, end: end, total: total);
  }

  Future<void> _finish(
    String modelId,
    DownloadPhase phase, {
    int? receivedBytes,
  }) async {
    final existing = _tasks[modelId];
    if (existing == null) return;
    _publish(
      existing.copyWith(phase: phase, receivedBytes: receivedBytes),
    );
  }

  void _publishFailure(
    String modelId,
    String quant,
    String message, {
    String? detail,
    int? receivedBytes,
  }) {
    _publish(
      DownloadTask(
        modelId: modelId,
        quant: quant,
        fileName: _tasks[modelId]?.fileName ?? '',
        totalBytes: _tasks[modelId]?.totalBytes ?? 0,
        receivedBytes: receivedBytes ?? _tasks[modelId]?.receivedBytes ?? 0,
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
    final installation = await _db.installation(modelId);
    if (installation != null) {
      for (final locator in [
        installation.localPath,
        if (installation.mmprojPath != null) installation.mmprojPath!,
      ]) {
        try {
          await _storagePaths.deleteModelFile(locator);
        } catch (_) {
          // The user can revoke a SAF grant independently. Remove the local
          // database row even if the old document tree cannot be reached.
        }
      }
    }
    await _storagePaths.deleteModelDirectory(modelId);
    await _db.removeInstallation(modelId);
    clearTask(modelId);
  }

  /// Bytes on disk for a model, measured rather than taken from the record.
  Future<int> diskUsage(String modelId) async {
    final installation = await _db.installation(modelId);
    if (installation == null) return _storagePaths.modelDirectorySize(modelId);
    var total = await _storagePaths.modelFileSize(installation.localPath);
    if (installation.mmprojPath != null) {
      total += await _storagePaths.modelFileSize(installation.mmprojPath!);
    }
    return total;
  }

  /// Cleans up `.part` files left behind by interrupted downloads.
  Future<void> sweepPartialDownloads({bool discardResumable = false}) async {
    await _storagePaths.sweepPartialDownloads(
      discardResumable: discardResumable,
    );
  }

  void dispose() {
    _controller.close();
  }
}
