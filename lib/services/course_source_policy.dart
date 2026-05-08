import 'dart:io';

import 'package:path/path.dart' as p;

class CourseSourcePolicy {
  const CourseSourcePolicy._();

  static bool isDownloadedCoursePath(String? sourcePath) {
    final trimmed = sourcePath?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return false;
    }
    final parts = p
        .normalize(trimmed)
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty)
        .map((part) => part.toLowerCase());
    return parts.contains('downloaded_courses');
  }

  static Directory? editableSourceDirectory(String? sourcePath) {
    final trimmed = sourcePath?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    if (isDownloadedCoursePath(trimmed)) {
      return null;
    }
    final directory = Directory(trimmed);
    if (!directory.existsSync()) {
      return null;
    }
    return directory;
  }
}
