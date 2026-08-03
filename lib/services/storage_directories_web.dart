import 'file_system_web.dart';

Future<Directory> getApplicationDocumentsDirectory() async =>
    Directory('/tutor1on1/documents')..createSync(recursive: true);

Future<Directory> getApplicationSupportDirectory() async =>
    Directory('/tutor1on1/support')..createSync(recursive: true);

Future<Directory> getTemporaryDirectory() async =>
    Directory('/tutor1on1/tmp')..createSync(recursive: true);
