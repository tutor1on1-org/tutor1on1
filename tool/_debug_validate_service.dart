import 'dart:io';
import 'package:tutor1on1/services/course_bundle_service.dart';

Future<void> main() async {
  final service = CourseBundleService();
  await service.validateBundleForImport(File('tmp_bundle_21.zip'));
  print('validate ok');
}
