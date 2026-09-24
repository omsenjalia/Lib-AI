import 'package:flutter_test/flutter_test.dart';
import 'package:library_ai/core/services/storage_paths.dart';
import 'package:saf/saf.dart';

void main() {
  group('hasPersistedTreeGrant', () {
    const treeUri =
        'content://com.android.externalstorage.documents/tree/primary%3ADocuments';

    test('requires an exact persisted read and write grant', () {
      final grants = [
        const SafPersistedPermission(
          uri: treeUri,
          read: true,
          write: true,
          persistedTime: 42,
        ),
      ];

      expect(hasPersistedTreeGrant(grants, treeUri), isTrue);
      expect(hasPersistedTreeGrant(grants, '$treeUri/child'), isFalse);
    });

    test('a read-only grant is not sufficient for model storage', () {
      const grants = [
        SafPersistedPermission(
          uri: treeUri,
          read: true,
          write: false,
          persistedTime: 42,
        ),
      ];

      expect(hasPersistedTreeGrant(grants, treeUri), isFalse);
    });

    test('a revoked or missing grant falls back by returning false', () {
      expect(hasPersistedTreeGrant(const [], treeUri), isFalse);
    });
  });

  group('ModelStorageStatus', () {
    test('flags model bytes that would be deleted with app-private storage', () {
      const status = ModelStorageStatus(
        displayName: 'Selected folder/models',
        isUserFolder: true,
        bytesUsed: 0,
        privateBytesUsed: 128,
        warning: null,
      );

      expect(status.hasFragileUserData, isTrue);
    });

    test('does not flag an empty private model directory', () {
      const status = ModelStorageStatus(
        displayName: 'Selected folder/models',
        isUserFolder: true,
        bytesUsed: 128,
        privateBytesUsed: 0,
        warning: null,
      );

      expect(status.hasFragileUserData, isFalse);
    });
  });

  group('ModelFileTarget', () {
    test('uses a sibling part filename and supports move-specific parts', () {
      const downloadTarget = ModelFileTarget.local(
        path: '/models/example.gguf',
        fileName: 'example.gguf',
      );
      const moveTarget = ModelFileTarget.saf(
        parentUri: 'content://tree/models',
        fileName: 'example.gguf',
        partSuffix: 'move.part',
      );

      expect(downloadTarget.partFileName, 'example.gguf.part');
      expect(moveTarget.partFileName, 'example.gguf.move.part');
      expect(downloadTarget.isSaf, isFalse);
      expect(moveTarget.isSaf, isTrue);
    });
  });
}
