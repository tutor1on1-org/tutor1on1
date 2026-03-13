import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:family_teacher/services/secure_storage_service.dart';

void main() {
  group('SecureStorageService.migrateWindowsRenamedProductStorage', () {
    test('copies missing files and overwrites older secure files', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'secure-storage-migration-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sourceDir = Directory(
        p.join(
          tempDir.path,
          SecureStorageService.windowsStorageCompanyName,
          SecureStorageService.windowsAccidentalProductName,
        ),
      );
      final targetDir = Directory(
        p.join(
          tempDir.path,
          SecureStorageService.windowsStorageCompanyName,
          SecureStorageService.windowsStableProductName,
        ),
      );
      await sourceDir.create(recursive: true);
      await targetDir.create(recursive: true);

      final sourceOnly =
          File(p.join(sourceDir.path, 'auth_access_token.secure'));
      await sourceOnly.writeAsBytes(const [1, 2, 3]);
      final sourceOnlyModified = DateTime.utc(2026, 3, 13, 10);
      await sourceOnly.setLastModified(sourceOnlyModified);

      final sourceNewer = File(p.join(sourceDir.path, 'openai_api_key.secure'));
      await sourceNewer.writeAsBytes(const [9, 9, 9]);
      final sourceNewerModified = DateTime.utc(2026, 3, 13, 11);
      await sourceNewer.setLastModified(sourceNewerModified);

      final targetOlder = File(p.join(targetDir.path, 'openai_api_key.secure'));
      await targetOlder.writeAsBytes(const [4, 4, 4]);
      await targetOlder.setLastModified(DateTime.utc(2026, 3, 13, 9));

      final targetNewer = File(
        p.join(targetDir.path, 'auth_refresh_token.secure'),
      );
      await targetNewer.writeAsBytes(const [7, 7, 7]);
      final targetNewerModified = DateTime.utc(2026, 3, 13, 12);
      await targetNewer.setLastModified(targetNewerModified);

      final sourceOlder =
          File(p.join(sourceDir.path, 'auth_refresh_token.secure'));
      await sourceOlder.writeAsBytes(const [5, 5, 5]);
      await sourceOlder.setLastModified(DateTime.utc(2026, 3, 13, 8));

      await SecureStorageService.migrateWindowsRenamedProductStorage(
        roamingAppDataDir: tempDir,
      );

      expect(
        await File(p.join(targetDir.path, 'auth_access_token.secure'))
            .readAsBytes(),
        const [1, 2, 3],
      );
      expect(
        await File(p.join(targetDir.path, 'openai_api_key.secure'))
            .readAsBytes(),
        const [9, 9, 9],
      );
      expect(
        await File(p.join(targetDir.path, 'auth_refresh_token.secure'))
            .readAsBytes(),
        const [7, 7, 7],
      );
      expect(
        await File(p.join(targetDir.path, 'openai_api_key.secure'))
            .lastModified()
            .then((value) => value.toUtc()),
        sourceNewerModified,
      );
      expect(
        await File(p.join(targetDir.path, 'auth_refresh_token.secure'))
            .lastModified()
            .then((value) => value.toUtc()),
        targetNewerModified,
      );
      expect(
        await File(p.join(targetDir.path, 'auth_access_token.secure'))
            .lastModified()
            .then((value) => value.toUtc()),
        sourceOnlyModified,
      );
    });
  });
}
