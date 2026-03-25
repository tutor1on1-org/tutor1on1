import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'legacy_brand_compat.dart';

class DbPathProvider {
  static const String currentDatabaseFileName = 'tutor1on1.db';
  static final String legacyDatabaseFileName = buildLegacyDatabaseFileName();

  static Future<File> getDatabaseFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final current = File(p.join(dir.path, currentDatabaseFileName));
    if (current.existsSync()) {
      return current;
    }
    final legacy = File(p.join(dir.path, legacyDatabaseFileName));
    if (legacy.existsSync()) {
      return legacy;
    }
    return current;
  }
}
