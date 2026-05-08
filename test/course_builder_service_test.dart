import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:tutor1on1/db/app_database.dart';
import 'package:tutor1on1/llm/llm_models.dart';
import 'package:tutor1on1/llm/llm_service.dart';
import 'package:tutor1on1/llm/prompt_repository.dart';
import 'package:tutor1on1/services/course_artifact_service.dart';
import 'package:tutor1on1/services/course_builder_service.dart';
import 'package:tutor1on1/services/course_bundle_service.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

class _FakeLlmService implements LlmService {
  final List<_Invocation> invocations = <_Invocation>[];
  String responseText = 'AI draft';

  @override
  LlmRequestHandle startCall({
    required String promptName,
    required String renderedPrompt,
    Map<String, dynamic>? schemaMap,
    String? conversationDigest,
    String? modelOverride,
    LlmCallContext? context,
  }) {
    invocations.add(
      _Invocation(
        promptName: promptName,
        renderedPrompt: renderedPrompt,
        context: context,
      ),
    );
    return LlmRequestHandle(
      future: Future.value(
        LlmCallResult(
          responseText: responseText,
          latencyMs: 1,
          fromReplay: false,
        ),
      ),
      cancel: () {},
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Invocation {
  const _Invocation({
    required this.promptName,
    required this.renderedPrompt,
    required this.context,
  });

  final String promptName;
  final String renderedPrompt;
  final LlmCallContext? context;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory tempRoot;
  late CourseArtifactService artifactService;
  late _FakeLlmService llmService;
  late CourseBuilderService service;
  late int teacherId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tempRoot = await Directory.systemTemp.createTemp(
      'course_builder_service_test_',
    );
    artifactService = CourseArtifactService(
      artifactsRootProvider: () async => Directory(
        p.join(tempRoot.path, 'artifacts'),
      ),
    );
    llmService = _FakeLlmService();
    service = CourseBuilderService(
      db: db,
      llmService: llmService,
      promptRepository: PromptRepository(db: db),
      courseArtifactService: artifactService,
    );
    teacherId = await db.createUser(
      username: 'teacher',
      pinHash: 'hash',
      role: 'teacher',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      if (call.method == 'getTemporaryDirectory') {
        return p.join(tempRoot.path, 'tmp');
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    await db.close();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('content prompt reuses lesson_content and conversation_history',
      () async {
    final courseDir = await _createCourseFolder(tempRoot);
    final courseId = await db.createCourseVersion(
      teacherId: teacherId,
      subject: 'Math',
      sourcePath: courseDir.path,
      granularity: 2,
      textbookText: '1 Unit\n1.1 Adding\n',
    );
    final course = (await db.getCourseVersionById(courseId))!;

    final response = await service.generate(
      courseVersion: course,
      kpKey: '1.1',
      kpTitle: 'Adding',
      mode: CourseBuilderMode.content,
      conversationHistory: 'Teacher: make it clearer',
    );

    expect(response, 'AI draft');
    expect(llmService.invocations.single.promptName, 'course_builder_content');
    expect(
      llmService.invocations.single.renderedPrompt,
      contains('Existing lesson content:\nOriginal lesson'),
    );
    expect(
      llmService.invocations.single.renderedPrompt,
      contains('Teacher: make it clearer'),
    );
  });

  test('save lesson content writes source file and rebuilds stored bundle',
      () async {
    final courseDir = await _createCourseFolder(tempRoot);
    final courseId = await db.createCourseVersion(
      teacherId: teacherId,
      subject: 'Math',
      sourcePath: courseDir.path,
      granularity: 2,
      textbookText: '1 Unit\n1.1 Adding\n',
    );
    final course = (await db.getCourseVersionById(courseId))!;

    await service.saveLessonContent(
      courseVersion: course,
      kpKey: '1.1',
      text: 'Updated lesson',
    );

    expect(
      await File(p.join(courseDir.path, '1.1_lecture.txt')).readAsString(),
      'Updated lesson',
    );
    expect(
      await artifactService.readStoredTextEntry(
        courseVersionId: courseId,
        candidateRelativePaths: const ['1.1_lecture.txt'],
      ),
      'Updated lesson',
    );
  });

  test('save question can update cached bundle without a source folder',
      () async {
    final courseDir = await _createCourseFolder(tempRoot);
    final bundle = await CourseBundleService().createBundleFromFolder(
      courseDir.path,
    );
    final courseId = await db.createCourseVersion(
      teacherId: teacherId,
      subject: 'Math',
      granularity: 2,
      textbookText: '1 Unit\n1.1 Adding\n',
    );
    await artifactService.storeImportedContentBundle(
      courseVersionId: courseId,
      folderPath: courseDir.path,
      bundleFile: bundle,
      buildChapterArtifacts: false,
    );
    final course = (await db.getCourseVersionById(courseId))!;

    await service.saveQuestionText(
      courseVersion: course,
      kpKey: '1.1',
      level: 'medium',
      text: 'New medium question',
    );

    expect(
      await artifactService.readStoredTextEntry(
        courseVersionId: courseId,
        candidateRelativePaths: const ['1.1_medium.txt'],
      ),
      'New medium question',
    );
  });

  test('save lesson updates cached bundle for downloaded scaffolds', () async {
    final courseDir = await _createCourseFolder(tempRoot);
    final bundle = await CourseBundleService().createBundleFromFolder(
      courseDir.path,
    );
    final scaffoldDir = Directory(
      p.join(tempRoot.path, 'downloaded_courses', 'special_relativity'),
    );
    await scaffoldDir.create(recursive: true);
    await File(p.join(scaffoldDir.path, 'contents.txt')).writeAsString(
      '1 Unit\n1.1 Adding\n',
    );
    final courseId = await db.createCourseVersion(
      teacherId: teacherId,
      subject: 'Math',
      sourcePath: scaffoldDir.path,
      granularity: 2,
      textbookText: '1 Unit\n1.1 Adding\n',
    );
    await artifactService.storeImportedContentBundle(
      courseVersionId: courseId,
      folderPath: courseDir.path,
      bundleFile: bundle,
      buildChapterArtifacts: false,
    );
    final course = (await db.getCourseVersionById(courseId))!;

    await service.saveLessonContent(
      courseVersion: course,
      kpKey: '1.1',
      text: 'Downloaded scaffold update',
    );

    expect(
      File(p.join(scaffoldDir.path, '1.1_lecture.txt')).existsSync(),
      isFalse,
    );
    expect(
      await artifactService.readStoredTextEntry(
        courseVersionId: courseId,
        candidateRelativePaths: const ['1.1_lecture.txt'],
      ),
      'Downloaded scaffold update',
    );
  });
}

Future<Directory> _createCourseFolder(Directory root) async {
  final dir = Directory(p.join(root.path, 'course'));
  await dir.create(recursive: true);
  await File(p.join(dir.path, 'contents.txt')).writeAsString(
    '1 Unit\n1.1 Adding\n',
  );
  await File(p.join(dir.path, '1_lecture.txt')).writeAsString('Unit lesson');
  await File(p.join(dir.path, '1.1_lecture.txt')).writeAsString(
    'Original lesson',
  );
  await File(p.join(dir.path, '1.1_medium.txt')).writeAsString(
    'Original medium question',
  );
  return dir;
}
