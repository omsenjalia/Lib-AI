import 'dart:io';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a retry resumes the saved prefix and verifies the complete file',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final storage = _MemoryStoragePaths(SettingsService(database));
    final dio = Dio();
    final manager = DownloadManager(
      database: database,
      connectivity: ConnectivityService(),
      storagePaths: storage,
      dio: dio,
    );
    final requestRanges = <String?>[];
    final expectedBytes = [0, 1, 2, 3, 4];
    final expectedSha256 = sha256.convert(expectedBytes).toString();

    final serverSubscription = server.listen((request) async {
      final range = request.headers.value('range');
      requestRanges.add(range);
      if (range == null) {
        // Model an interrupted response: the server cleanly closes after
        // sending only a prefix of the five-byte fixture.
        request.response.statusCode = 200;
        request.response.contentLength = 2;
        request.response.add([0, 1]);
      } else {
        request.response.statusCode = 206;
        request.response.headers.set('content-range', 'bytes 2-4/5');
        request.response.contentLength = 3;
        request.response.add([2, 3, 4]);
      }
      await request.response.close();
    });

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
          'downloadUrl': 'http://127.0.0.1:${server.port}/fixture.gguf',
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

      expect(requestRanges, [null, 'bytes=2-']);
      expect(manager.taskFor(model.id)?.phase, DownloadPhase.complete);
      expect(storage.promotedBytes, expectedBytes);
      expect(await database.installation(model.id), isNotNull);
    } finally {
      manager.dispose();
      dio.close(force: true);
      await serverSubscription.cancel();
      await server.close(force: true);
      await database.close();
    }
  });
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
