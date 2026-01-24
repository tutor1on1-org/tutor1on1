import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DbPathProvider {
  static Future<File> getDatabaseFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'family_teacher.db'));
  }
}
