import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:saf/saf.dart';

import '../constants/app_constants.dart';
import '../models/app_settings.dart';
import 'settings_service.dart';

/// Where Library AI keeps user data.
///
/// Model files use app-private storage by default. If the user chooses a
/// document tree, only that tree is used, through Android's Storage Access
/// Framework; the app never requests broad storage permissions. Other files
/// (attachments and exports) retain their existing app-scoped locations.
///
/// Instances are provided through Riverpod so the SAF gateway and settings
/// source can be substituted in tests and storage behavior is not hidden behind
/// static global state.
class StoragePaths {
  StoragePaths({required SettingsService settings, Saf? saf})
      : _settings = settings,
        _saf = saf ?? Saf();

  final SettingsService _settings;
  final Saf _saf;

  static Directory? _exportsDir;

  /// Opens the system `ACTION_OPEN_DOCUMENT_TREE` picker and persists a
  /// read/write grant. Cancelling returns null and leaves settings untouched.
  Future<ModelStorageFolder?> pickModelStorageFolder() async {
    final folder = await _saf.pickDirectory(
      writePermission: true,
      persistablePermission: true,
    );
    if (folder == null) return null;

    final permissions = await _saf.persistedPermissions();
    if (!hasPersistedTreeGrant(permissions, folder.uri)) {
      throw const FileSystemException(
        'Android did not retain access to the selected folder.',
      );
    }
    return ModelStorageFolder(uri: folder.uri, name: folder.name);
  }

  /// Returns a target for a model file in the active location.
  ///
  /// A saved tree URI is used only while a persisted read/write grant is still
  /// present. If access was revoked or the tree became unavailable, downloads
  /// safely fall back to app-private storage and [modelStorageStatus] explains
  /// why, without repeatedly opening a dialog.
  Future<ModelFileTarget> modelFileTarget(
    String modelId,
    String fileName,
  ) async {
    final settings = await _settings.load();
    final treeUri = await _usableTreeUri(settings.modelStorageTreeUri);
    if (treeUri != null) {
      try {
        final directory = await _saf.mkdirp(
          treeUri,
          [AppConstants.modelsDirectoryName, modelId],
        );
        return ModelFileTarget.saf(
          parentUri: directory.uri,
          fileName: fileName,
        );
      } catch (_) {
        // A provider can become unavailable while its grant remains persisted.
        // Stay usable by falling back to app-private storage.
      }
    }

    final directory = await _privateModelDirectory(modelId);
    return ModelFileTarget.local(
      path: p.join(directory.path, fileName),
      fileName: fileName,
    );
  }

  /// Picks the model's directory in the active location, creating it when
  /// needed. This is used for deletion and measured storage usage.
  Future<ModelDirectoryTarget> modelDirectory(String modelId) async {
    final settings = await _settings.load();
    final treeUri = await _usableTreeUri(settings.modelStorageTreeUri);
    if (treeUri != null) {
      try {
        final directory = await _saf.mkdirp(
          treeUri,
          [AppConstants.modelsDirectoryName, modelId],
        );
        return ModelDirectoryTarget.saf(uri: directory.uri);
      } catch (_) {
        // Fall through to the private location.
      }
    }
    return ModelDirectoryTarget.local(
      directory: await _privateModelDirectory(modelId),
    );
  }

  /// The storage location the app can currently access, plus an actionable
  /// explanation when a previously granted tree is no longer usable.
  Future<ModelStorageStatus> modelStorageStatus() async {
    final settings = await _settings.load();
    final configuredUri = settings.modelStorageTreeUri;
    final configuredName = settings.modelStorageFolderName;
    final privateRoot = await _privateModelsDirectory();
    final privateBytesUsed = await _directorySize(privateRoot);
    if (configuredUri == null) {
      return ModelStorageStatus(
        displayName: 'App storage',
        isUserFolder: false,
        warning: null,
        bytesUsed: privateBytesUsed,
        privateBytesUsed: privateBytesUsed,
      );
    }

    final treeUri = await _usableTreeUri(configuredUri);
    if (treeUri == null) {
      return ModelStorageStatus(
        displayName: 'App storage (fallback)',
        isUserFolder: false,
        warning:
            'Access to ${configuredName ?? 'the selected folder'} was revoked. '
            'Models are using app storage. Choose that folder again to restore access.',
        bytesUsed: privateBytesUsed,
        privateBytesUsed: privateBytesUsed,
      );
    }

    try {
      final root = await _saf.mkdirp(
        treeUri,
        [AppConstants.modelsDirectoryName],
      );
      return ModelStorageStatus(
        displayName: '${configuredName ?? 'Selected folder'}/'
            '${AppConstants.modelsDirectoryName}',
        isUserFolder: true,
        warning: null,
        bytesUsed: await _safDirectorySize(root.uri),
        privateBytesUsed: privateBytesUsed,
      );
    } catch (_) {
      return ModelStorageStatus(
        displayName: 'App storage (fallback)',
        isUserFolder: false,
        warning:
            'The selected folder is unavailable. Models are using app storage. '
            'Choose the folder again to restore access.',
        bytesUsed: privateBytesUsed,
        privateBytesUsed: privateBytesUsed,
      );
    }
  }

  /// Resolves a file target to the database locator to store after promotion.
  /// Private targets use a normal path; SAF targets use a content URI.
  Future<String> modelFileLocator(ModelFileTarget target) async {
    final path = target.path;
    if (path != null) return path;
    final parentUri = target.parentUri!;
    final document = await _saf.child(parentUri, [target.fileName]);
    if (document == null) {
      throw FileSystemException(
        'The promoted model file could not be found.',
        target.fileName,
      );
    }
    return document.uri;
  }

  /// Writes a streamed model to a sibling `.part` file. The stream is consumed
  /// with backpressure in both app-private and SAF storage.
  Future<void> writeModelPart(
    ModelFileTarget target,
    Stream<List<int>> source, {
    bool append = false,
  }) async {
    if (target.isSaf) {
      final partName = target.partFileName;
      final existing = await _saf.child(target.parentUri!, [partName]);
      if (!append && existing != null) await _saf.delete(existing.uri);
      await _saf.writeFileStream(
        target.parentUri!,
        partName,
        'application/octet-stream',
        source,
        overwrite: !append,
        append: append,
      );
      return;
    }

    final part = File('${target.path}.${target.partSuffix}');
    if (!append && await part.exists()) await part.delete();
    final output = part.openWrite(
      mode: append ? FileMode.append : FileMode.write,
    );
    try {
      await output.addStream(source);
      await output.flush();
      await output.close();
    } catch (_) {
      await output.close();
      rethrow;
    }
  }

  /// Locator for the current partial model file, if one exists.
  Future<String?> modelPartLocator(ModelFileTarget target) async {
    if (!target.isSaf) {
      final part = File('${target.path}.${target.partSuffix}');
      return await part.exists() ? part.path : null;
    }
    final document = await _saf.child(
      target.parentUri!,
      [target.partFileName],
    );
    return document?.uri;
  }

  /// Streams the existing partial file so a resumed download can rebuild its
  /// SHA-256 state before appending bytes from the server.
  Stream<List<int>> readModelPart(ModelFileTarget target) async* {
    final locator = await modelPartLocator(target);
    if (locator == null) return;
    final lease = await openModelFile(locator);
    try {
      await for (final chunk in File(lease.path).openRead()) {
        yield chunk;
      }
    } finally {
      await lease.close();
    }
  }

  /// Current size of the partial file, used to form an HTTP Range request.
  Future<int> modelPartSize(ModelFileTarget target) async {
    if (!target.isSaf) {
      final part = File('${target.path}.${target.partSuffix}');
      return await part.exists() ? part.length() : 0;
    }
    final document = await _saf.child(
      target.parentUri!,
      [target.partFileName],
    );
    return document?.length ?? 0;
  }

  /// Removes a partial model file, ignoring a missing file.
  Future<void> deleteModelPart(ModelFileTarget target) async {
    try {
      if (target.isSaf) {
        final part = await _saf.child(
          target.parentUri!,
          [target.partFileName],
        );
        if (part != null) await _saf.delete(part.uri);
      } else {
        final part = File('${target.path}.${target.partSuffix}');
        if (await part.exists()) await part.delete();
      }
    } catch (_) {
      // A best-effort cleanup failure is harmless; the next attempt validates
      // this part before resuming or overwrites it after a clean restart.
    }
  }

  /// Promotes a verified `.part` file and returns its durable locator.
  Future<String> promoteModelPart(ModelFileTarget target) async {
    if (target.isSaf) {
      final part = await _saf.child(
        target.parentUri!,
        [target.partFileName],
      );
      if (part == null) {
        throw FileSystemException(
          'The partial model file is missing.',
          target.fileName,
        );
      }
      final existing = await _saf.child(target.parentUri!, [target.fileName]);
      if (existing != null) await _saf.delete(existing.uri);
      await _saf.rename(part.uri, target.fileName);
      return modelFileLocator(target);
    }

    final part = File('${target.path}.${target.partSuffix}');
    final destination = File(target.path!);
    if (!await part.exists()) {
      throw FileSystemException('The partial model file is missing.', part.path);
    }
    if (await destination.exists()) await destination.delete();
    await part.rename(destination.path);
    return destination.path;
  }

  /// Removes an installation directory from the active storage location.
  Future<void> deleteModelDirectory(String modelId) async {
    final target = await modelDirectory(modelId);
    if (target.isSaf) {
      await _saf.delete(target.uri!);
    } else if (await target.directory!.exists()) {
      await target.directory!.delete(recursive: true);
    }
  }

  /// Measures bytes actually consumed by one installed model.
  Future<int> modelDirectorySize(String modelId) async {
    final target = await modelDirectory(modelId);
    if (target.isSaf) return _safDirectorySize(target.uri!);
    return _directorySize(target.directory!);
  }

  /// Clears resumable download `.part` files only when the user explicitly
  /// requests cleanup. Launch-time housekeeping must preserve them so failed,
  /// paused, and timed-out downloads can continue with an HTTP Range request.
  /// `.move.part` files are always preserved for the migration resume flow.
  Future<void> sweepPartialDownloads({bool discardResumable = false}) async {
    if (!discardResumable) return;
    try {
      final settings = await _settings.load();
      final treeUri = await _usableTreeUri(settings.modelStorageTreeUri);
      if (treeUri != null) {
        final root = await _saf.child(
          treeUri,
          [AppConstants.modelsDirectoryName],
        );
        if (root != null) {
          final stale = <String>[];
          await for (final entry in _saf.walk(root.uri)) {
            if (!entry.file.isDir && _isStaleDownloadPart(entry.file.name)) {
              stale.add(entry.file.uri);
            }
          }
          for (final uri in stale) {
            await _saf.delete(uri);
          }
        }
      }

      // A user may have changed the selected tree since an earlier transfer.
      // Always sweep app-private parts too, while keeping `.move.part` files
      // whose persisted migration ids make them resumable.
      final root = await _privateModelsDirectory();
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is File && _isStaleDownloadPart(p.basename(entity.path))) {
          await entity.delete();
        }
      }
    } catch (_) {
      // Best-effort housekeeping; never worth surfacing.
    }
  }

  /// Lists non-directory files in the active, app-managed models directory.
  /// Adoption only inspects this directory, never unrelated files in the
  /// user-selected tree.
  Future<List<ModelStorageDocument>> scanManagedModelFiles() async {
    final settings = await _settings.load();
    final treeUri = await _usableTreeUri(settings.modelStorageTreeUri);
    if (treeUri != null) {
      final root = await _saf.child(
        treeUri,
        [AppConstants.modelsDirectoryName],
      );
      if (root == null) return const [];
      final documents = <ModelStorageDocument>[];
      await for (final entry in _saf.walk(root.uri)) {
        if (!entry.file.isDir) {
          documents.add(
            ModelStorageDocument(
              name: entry.file.name,
              locator: entry.file.uri,
              length: entry.file.length,
            ),
          );
        }
      }
      return documents;
    }

    final root = await _privateModelsDirectory();
    final documents = <ModelStorageDocument>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        documents.add(
          ModelStorageDocument(
            name: p.basename(entity.path),
            locator: entity.path,
            length: await entity.length(),
          ),
        );
      }
    }
    return documents;
  }

  /// Opens a SAF-backed installation for fllama, whose API accepts paths rather
  /// than content URIs. The returned `/proc/self/fd/<n>` path remains valid
  /// until [ModelFileLease.close] is called.
  Future<ModelFileLease> openModelFile(String locator) async {
    if (!locator.startsWith('content://')) {
      return ModelFileLease(path: locator);
    }
    final descriptor = await _saf.openFileDescriptor(locator, 'r');
    return ModelFileLease(
      path: descriptor.path,
      close: () => _saf.closeFileDescriptor(descriptor.fd),
    );
  }

  /// Streams SHA-256 from disk without materializing a multi-gigabyte model in
  /// memory. SAF descriptors are held only for the duration of the hash.
  Future<String> sha256Of(String locator) async {
    final lease = await openModelFile(locator);
    try {
      final digestSink = _StorageDigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      await for (final chunk in File(lease.path).openRead()) {
        hasher.add(chunk);
      }
      hasher.close();
      return digestSink.value!.toString();
    } finally {
      await lease.close();
    }
  }

  /// Gets a file's current length, regardless of storage backend.
  Future<int> modelFileSize(String locator) async {
    if (locator.startsWith('content://')) {
      final document = await _saf.stat(locator);
      if (document == null) {
        throw FileSystemException('Model file does not exist.', locator);
      }
      return document.length;
    }
    return File(locator).length();
  }

  /// Deletes a file locator without requiring callers to know its backend.
  Future<void> deleteModelFile(String locator) async {
    if (locator.startsWith('content://')) {
      await _saf.delete(locator);
      return;
    }
    final file = File(locator);
    if (await file.exists()) await file.delete();
  }

  /// Copies one model file to the active destination, checking its expected
  /// SHA-256 while streaming. Existing source data remains untouched until the
  /// caller updates the installation row after every file has been promoted.
  Future<String> copyVerifiedModelFile({
    required String sourceLocator,
    required ModelFileTarget destination,
    required String expectedSha256,
    required void Function(int copiedBytes) onProgress,
    bool Function()? isCancelled,
  }) async {
    final source = await openModelFile(sourceLocator);
    final digestSink = _StorageDigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    var copiedBytes = 0;

    Stream<List<int>> verifiedSource() async* {
      await for (final chunk in File(source.path).openRead()) {
        if (isCancelled?.call() ?? false) {
          throw const ModelStorageCancelledException();
        }
        hasher.add(chunk);
        copiedBytes += chunk.length;
        onProgress(copiedBytes);
        yield chunk;
      }
    }

    try {
      await writeModelPart(destination, verifiedSource());
      hasher.close();
      if (digestSink.value?.toString().toLowerCase() !=
          expectedSha256.toLowerCase()) {
        throw const FileSystemException(
          'The copied model failed its integrity check.',
        );
      }
      return await promoteModelPart(destination);
    } catch (_) {
      await deleteModelPart(destination);
      rethrow;
    } finally {
      await source.close();
    }
  }

  /// Directory holding generated PDF/ZIP exports.
  ///
  /// Prefers the app's *external* files directory on Android
  /// (`Android/data/<package>/files/LibraryAI`). Files there are reachable from
  /// a file manager or over USB, which is the whole point of an export - an
  /// archive the user cannot open is not an export. It is still app-scoped, so
  /// no storage permission is involved.
  ///
  /// Falls back to the documents directory on platforms without external
  /// storage, or if the external path is unavailable.
  static Future<Directory> exportsDirectory() async {
    final cached = _exportsDir;
    if (cached != null) return cached;

    Directory? root;
    try {
      root = await getExternalStorageDirectory();
    } catch (_) {
      root = null;
    }
    root ??= await getApplicationDocumentsDirectory();

    final dir =
        Directory(p.join(root.path, AppConstants.exportsDirectoryName));
    if (!await dir.exists()) await dir.create(recursive: true);
    _exportsDir = dir;
    return dir;
  }

  /// Directory holding images the user attached to a turn.
  static Future<Directory> attachmentsDirectory() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'attachments'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Copies [source] into app-private storage and returns the new file.
  static Future<File> persistAttachment(File source) async {
    final dir = await attachmentsDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final extension = p.extension(source.path);
    final target = File(p.join(dir.path, 'attachment-$stamp$extension'));
    return source.copy(target.path);
  }

  Future<String?> _usableTreeUri(String? treeUri) async {
    if (treeUri == null) return null;
    try {
      final permissions = await _saf.persistedPermissions();
      if (!hasPersistedTreeGrant(permissions, treeUri)) return null;
      return treeUri;
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _privateModelsDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      p.join(support.path, AppConstants.modelsDirectoryName),
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> _privateModelDirectory(String modelId) async {
    final root = await _privateModelsDirectory();
    final directory = Directory(p.join(root.path, modelId));
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<int> _directorySize(Directory directory) async {
    if (!await directory.exists()) return 0;
    var total = 0;
    await for (final entity
        in directory.list(recursive: true, followLinks: false)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  Future<int> _safDirectorySize(String directoryUri) async {
    var total = 0;
    await for (final entry in _saf.walk(directoryUri)) {
      if (!entry.file.isDir) total += entry.file.length;
    }
    return total;
  }

  static bool _isStaleDownloadPart(String name) =>
      name.endsWith('.part') && !name.endsWith('.move.part');
}

/// Whether a persisted Android grant still permits reading and writing the
/// selected SAF tree.
bool hasPersistedTreeGrant(
  Iterable<SafPersistedPermission> permissions,
  String treeUri,
) =>
    permissions.any(
      (permission) =>
          permission.uri == treeUri && permission.read && permission.write,
    );

@immutable
class ModelStorageFolder {
  const ModelStorageFolder({required this.uri, required this.name});

  final String uri;
  final String name;
}

@immutable
class ModelFileTarget {
  const ModelFileTarget.local({
    required this.path,
    required this.fileName,
    this.partSuffix = 'part',
  }) : parentUri = null;
  const ModelFileTarget.saf({
    required this.parentUri,
    required this.fileName,
    this.partSuffix = 'part',
  }) : path = null;

  final String? path;
  final String? parentUri;
  final String fileName;
  final String partSuffix;

  String get partFileName => '$fileName.$partSuffix';

  bool get isSaf => parentUri != null;
}

@immutable
class ModelDirectoryTarget {
  const ModelDirectoryTarget.local({required this.directory}) : uri = null;
  const ModelDirectoryTarget.saf({required this.uri}) : directory = null;

  final Directory? directory;
  final String? uri;

  bool get isSaf => uri != null;
}

@immutable
class ModelStorageStatus {
  const ModelStorageStatus({
    required this.displayName,
    required this.isUserFolder,
    required this.bytesUsed,
    required this.privateBytesUsed,
    required this.warning,
  });

  final String displayName;
  final bool isUserFolder;
  final int bytesUsed;

  /// Model bytes left in app-private storage, including old installs after a
  /// user selects a SAF folder. Uninstall removes these files.
  final int privateBytesUsed;

  final String? warning;

  bool get hasFragileUserData => privateBytesUsed > 0;
}

@immutable
class ModelStorageDocument {
  const ModelStorageDocument({
    required this.name,
    required this.locator,
    required this.length,
  });

  final String name;
  final String locator;
  final int length;
}

class ModelFileLease {
  ModelFileLease({required this.path, Future<void> Function()? close})
      : _close = close;

  final String path;
  final Future<void> Function()? _close;
  bool _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _close?.call();
  }
}

class ModelStorageCancelledException implements Exception {
  const ModelStorageCancelledException();

  @override
  String toString() => 'Model storage operation was cancelled.';
}

class _StorageDigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
