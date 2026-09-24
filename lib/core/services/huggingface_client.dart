import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';

/// What the auto-update checker needs to know about a remote repository.
@immutable
class RemoteRepoState {
  const RemoteRepoState({
    required this.repoId,
    this.sha,
    this.lastModified,
    this.fileOids = const {},
  });

  final String repoId;

  /// Repository-level commit hash.
  final String? sha;

  final DateTime? lastModified;

  /// Per-file SHA-256, keyed by file name.
  ///
  /// HuggingFace stores large files in LFS, and for those the `lfs.oid` field
  /// **is** the file's SHA-256. That makes this map directly comparable with
  /// the checksums recorded in `models_catalogue.json`, so change detection
  /// works at file granularity rather than "the repo moved, something changed".
  final Map<String, String> fileOids;

  /// The recorded checksum for [fileName], if the API reported one.
  String? oidFor(String fileName) => fileOids[fileName];
}

/// Minimal read-only client for HuggingFace's public model API.
///
/// This is the only network code in the app apart from the download manager,
/// and it is only ever called from the update checker, which itself refuses to
/// run when offline.
class HuggingFaceClient {
  HuggingFaceClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: AppConstants.metadataTimeout,
                receiveTimeout: AppConstants.metadataTimeout,
                headers: const {
                  // HuggingFace asks API clients to identify themselves.
                  'User-Agent': 'LibraryAI/1.0 (+offline-first study app)',
                },
              ),
            );

  final Dio _dio;

  /// Fetches repo metadata for [repoId].
  ///
  /// Uses `GET /api/models/{id}?blobs=true`, which is the endpoint named in the
  /// brief, plus `blobs=true` so the response includes the per-file LFS object
  /// ids used for change detection.
  ///
  /// Throws [DioException] on failure; callers decide whether that is worth
  /// reporting. For an offline device it is not - the update checker swallows
  /// connection errors entirely.
  Future<RemoteRepoState> fetchRepoState(String repoId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '${AppConstants.huggingFaceApiBase}/$repoId',
      queryParameters: const {'blobs': 'true'},
    );

    final data = response.data;
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        message: 'Empty response body from HuggingFace',
      );
    }

    final oids = <String, String>{};
    final siblings = data['siblings'];
    if (siblings is List) {
      for (final entry in siblings) {
        if (entry is! Map) continue;
        final name = entry['rfilename'];
        if (name is! String) continue;

        // Prefer the LFS object id: for LFS files it is the SHA-256 of the
        // content, which is exactly what we compare against.
        final lfs = entry['lfs'];
        if (lfs is Map && lfs['oid'] is String) {
          oids[name] = lfs['oid'] as String;
          continue;
        }
        final blobId = entry['blobId'];
        if (blobId is String && blobId.isNotEmpty) {
          oids[name] = blobId;
        }
      }
    }

    return RemoteRepoState(
      repoId: repoId,
      sha: data['sha'] as String?,
      lastModified: _parseDate(data['lastModified']),
      fileOids: oids,
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
