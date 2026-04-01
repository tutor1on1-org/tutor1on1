import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:tutor1on1/services/course_artifact_service.dart';
import 'package:tutor1on1/services/course_bundle_service.dart';
import 'package:tutor1on1/services/prompt_bundle_compat.dart';

class _TestPathProviderPlatform extends PathProviderPlatform {
  _TestPathProviderPlatform(this.rootPath);

  final String rootPath;

  @override
  Future<String?> getTemporaryPath() async {
    final dir = Directory(p.join(rootPath, 'temp'));
    await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    final dir = Directory(p.join(rootPath, 'documents'));
    await dir.create(recursive: true);
    return dir.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempRoot;
  late CourseArtifactService artifactService;
  late CourseBundleService bundleService;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('course_artifact_test_');
    PathProviderPlatform.instance = _TestPathProviderPlatform(tempRoot.path);
    artifactService = CourseArtifactService(
      artifactsRootProvider: () async =>
          Directory(p.join(tempRoot.path, 'artifacts')),
    );
    bundleService = CourseBundleService();
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test(
      'cached course artifacts reuse a stable upload bundle without source folder',
      () async {
    final courseDir = await _createCourseFolder(
      root: tempRoot,
      folderName: 'math_course',
      contents: '''
1 Number
1.1 Integers
2 Algebra
2.1 Expressions
''',
      lectureIds: const <String>['1', '1.1', '2', '2.1'],
    );

    final manifest = await artifactService.rebuildCourseArtifacts(
      courseVersionId: 17,
      folderPath: courseDir.path,
    );
    expect(manifest.chapters.map((chapter) => chapter.chapterKey).toList(),
        equals(const <String>['1', '2']));

    await courseDir.delete(recursive: true);

    final promptMetadata = <String, dynamic>{
      'schema': kCurrentPromptBundleSchema,
      'teacher_username': 'dennis',
      'prompt_templates': const <Map<String, dynamic>>[],
      'student_prompt_profiles': const <Map<String, dynamic>>[],
    };
    final prepared = await artifactService.prepareUploadBundle(
      courseVersionId: 17,
      promptMetadata: promptMetadata,
      bundleLabel: 'math',
    );
    final preparedAgain = await artifactService.prepareUploadBundle(
      courseVersionId: 17,
      promptMetadata: promptMetadata,
      bundleLabel: 'math',
    );
    final hash = await bundleService.computeBundleByteHash(
      prepared.bundleFile,
    );
    expect(prepared.hash, equals(hash));
    expect(preparedAgain.hash, equals(prepared.hash));
    expect(preparedAgain.bundleFile.path, equals(prepared.bundleFile.path));
  });
}

Future<Directory> _createCourseFolder({
  required Directory root,
  required String folderName,
  required String contents,
  required List<String> lectureIds,
}) async {
  final dir = Directory(p.join(root.path, folderName));
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
  await dir.create(recursive: true);
  await File(p.join(dir.path, 'contents.txt')).writeAsString(contents);
  for (final id in lectureIds) {
    await File(p.join(dir.path, '${id}_lecture.txt'))
        .writeAsString('Lecture for $id');
  }
  return dir;
}
