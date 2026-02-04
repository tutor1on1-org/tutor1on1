import 'dart:io';

import 'package:flutter/services.dart';

class CourseImportService {
  static const MethodChannel _channel =
      MethodChannel('family_teacher/course_import');

  static Future<String?> pickAndImportCourseFolder() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Course import is only available on Android.');
    }
    final path =
        await _channel.invokeMethod<String>('pickAndImportCourseFolder');
    if (path == null || path.trim().isEmpty) {
      return null;
    }
    return path.trim();
  }
}
