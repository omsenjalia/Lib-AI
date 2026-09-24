import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/app_constants.dart';

/// Where Library AI keeps things on disk.
///
/// Models live under the app's *support* directory, not the documents
/// directory: they are multi-gigabyte internal data the user should never
/// see in a file picker, and they should not be swept up by any future
/// "documents" backup. Exports, by contrast, are user-facing and go to
/// documents.
///
/// Nothing here requires a storage permission. Everything is app-private
/// storage, which is also why the manifest declares no storage permissions.
abstract final class StoragePaths {
  static Directory? _modelsDir;
  static Directory? _exportsDir;

  /// Directory holding downloaded GGUF files.
  static Future<Directory> modelsDirectory() async {
    final cached = _modelsDir;
    if (cached != null) return cached;
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, AppConstants.modelsDirectoryName));
    if (!await dir.exists()) await dir.create(recursive: true);
    _modelsDir = dir;
    return dir;
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
      // Not supported on this platform; the documents directory is fine.
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
  ///
  /// Attachments are copied here rather than referenced in place because the
  /// camera app's own output lives in a cache directory the system is free to
  /// clear - which would leave a message in the transcript pointing at a file
  /// that no longer exists.
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

  /// Absolute path a model file will occupy, keyed by catalogue id.
  ///
  /// Each model gets its own subdirectory. That keeps a model and its vision
  /// projector together, and means deleting a model is one directory removal
  /// with no chance of leaving an orphaned projector behind.
  static Future<String> modelFilePath(
    String modelId,
    String fileName,
  ) async {
    final root = await modelsDirectory();
    final dir = Directory(p.join(root.path, modelId));
    if (!await dir.exists()) await dir.create(recursive: true);
    return p.join(dir.path, fileName);
  }

  /// Directory for a model's files, for storage accounting and deletion.
  static Future<Directory> modelDirectory(String modelId) async {
    final root = await modelsDirectory();
    return Directory(p.join(root.path, modelId));
  }

  /// Recursively deletes a model's directory. Missing directories are fine.
  static Future<void> deleteModelDirectory(String modelId) async {
    final dir = await modelDirectory(modelId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Bytes actually consumed by a model on disk, measured rather than trusted.
  ///
  /// Used by the Settings storage breakdown so the figure reflects reality even
  /// if a download wrote a different number of bytes than the catalogue
  /// predicted.
  static Future<int> directorySize(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }
}
