import 'dart:io';

import '../db/app_database.dart';
import 'db_path_provider.dart';

class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  Future<void> exportTo(File target) async {
    final escaped = target.path.replaceAll("'", "''");
    await _db.customStatement("VACUUM INTO '$escaped'");
  }

  Future<void> restoreFrom(File source) async {
    final dbFile = await DbPathProvider.getDatabaseFile();
    await _db.close();
    await source.copy(dbFile.path);
  }
}
