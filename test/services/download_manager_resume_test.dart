import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_ai/core/data/database.dart';
import 'package:library_ai/core/models/model_catalogue.dart';
import 'package:library_ai/core/models/transfer_state.dart';
import 'package:library_ai/core/services/connectivity_service.dart';
import 'package:library_ai/core/services/download_manager.dart';
import 'package:library_ai/core/services/settings_service.dart';
import 'package:library_ai/core/services/storage_paths.dart';

void main() {
  test('a retry resumes the saved prefix and verifies the complete file',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final storage = _MemoryStoragePaths(SettingsService(database));
    final adapter = _ResumeAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final manager = DownloadManager(
      database: database,
      connectivity: ConnectivityService(),
      storagePaths: storage,
      dio: dio,
    );
    final expectedBytes = [0, 1, 2, 3, 4];
    final expectedSha256 = sha256.convert(expectedBytes).toString();
    final model = CatalogueModel.fromJson({
      'id': 'resume-test',
      'displayName': 'Resume test',
      'hfModelId': 'fixture/source',
      'ggufRepoId': 'fixture/gguf',
      'ggufRepoUrl': 'https://example.invalid/fixture',
      'recommendedQuant': 'Q4_K_M',
      'quants': [
        {
          'quant': 'Q4_K_M',
          'fileName': 'fixture.gguf',
          'sizeBytes': expectedBytes.length,
          'sha256': expectedSha256,
          'qualityNote': 'test fixture',
          'fitsTargetDevice': true,
          'downloadUrl': 'https://example.invalid/fixture.gguf',
        },
      ],
    });

    try {
      await manager.start(
        model: model,
        quant: model.quants.single,
        includeMmproj: false,
      );
      expect(manager.taskFor(model.id)?.phase, DownloadPhase.failed);
      expect(storage.partialBytes, [0, 1]);

      await manager.start(
        model: model,
        quant: model.quants.single,
        includeMmproj: false,
      );

      expect(adapter.requestRanges, [null, 'bytes=2-']);
      expect(manager.taskFor(model.id)?.phase, DownloadPhase.complete);
      expect(storage.promotedBytes, expectedBytes);
      expect(await database.installation(model.id), isNotNull);
    } finally {
      manager.dispose();
      dio.close(force: true);
      await database.close();
    }
  });
}

class _ResumeAdapter implements HttpClientAdapter {
  final requestRanges = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    String? range;
    for (final entry in options.headers.entries) {
      if (entry.key.toLowerCase() == 'range') {
        range = entry.value?.toString();
        break;
      }
    }
    requestRanges.add(range);

    if (range == null) {
      return ResponseBody(
        Stream<Uint8List>.value(Uint8List.fromList([0, 1])),
        200,
        headers: const {'content-length': ['2']},
      );
    }
    return ResponseBody(
      Stream<Uint8List>.value(Uint8List.fromList([2, 3, 4])),
      206,
      headers: const {
        'content-length': ['3'],
        'content-range': ['bytes 2-4/5'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _MemoryStoragePaths extends StoragePaths {
  _MemoryStoragePaths(SettingsService settings) : super(settings: settings);

  List<int> partialBytes = <int>[];
  List<int>? promotedBytes;

  @override
  Future<ModelFileTarget> modelFileTarget(
    String modelId,
    String fileName,
  ) async =>
      ModelFileTarget.local(
        path: '/models/$modelId/$fileName',
        fileName: fileName,
      );

  @override
  Future<int> modelPartSize(ModelFileTarget target) async => partialBytes.length;

  @override
  Stream<List<int>> readModelPart(ModelFileTarget target) async* {
    yield List<int>.unmodifiable(partialBytes);
  }

  @override
  Future<void> writeModelPart(
    ModelFileTarget target,
    Stream<List<int>> source, {
    bool append = false,
  }) async {
    final received = <int>[];
    await for (final chunk in source) {
      received.addAll(chunk);
    }
    partialBytes = append ? [...partialBytes, ...received] : received;
  }

  @override
  Future<String> promoteModelPart(ModelFileTarget target) async {
    promotedBytes = List<int>.unmodifiable(partialBytes);
    partialBytes = <int>[];
    final locator = await modelFileLocator(target);
    return locator;
  }

  @override
  Future<String> modelFileLocator(ModelFileTarget target) async =>
      'memory://${target.fileName}';
}
