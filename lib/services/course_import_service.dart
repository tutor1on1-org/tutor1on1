import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'course_bundle_service.dart';

class CourseImportService {
  static Future<String?> pickAndImportCourseFolder() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import course ZIP',
      type: FileType.custom,
      allowedExtensions: const <String>['zip'],
      withData: false,
      withReadStream: true,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    final selected = result.files.single;
    final bundleService = CourseBundleService();
    bundleService.validateCompressedByteLength(selected.size);
    final readStream = selected.readStream;
    if (readStream == null) {
      throw StateError('The selected course ZIP could not be read.');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in readStream) {
      bundleService.validateCompressedByteLength(builder.length + chunk.length);
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) {
      throw StateError('The selected course ZIP is empty.');
    }
    return bundleService.extractBundleFromBytes(
      bytes: bytes,
      courseName: selected.name,
    );
  }
}
