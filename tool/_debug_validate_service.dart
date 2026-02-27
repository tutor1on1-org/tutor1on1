import 'dart:io';
import 'package:family_teacher/services/course_bundle_service.dart';

Future<void> main() async {
  final service = CourseBundleService();
  await service.validateBundleForImport(File('tmp_bundle_21.zip'));
  print('validate ok');
}
