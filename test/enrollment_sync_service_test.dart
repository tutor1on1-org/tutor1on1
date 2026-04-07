import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:tutor1on1/db/app_database.dart';
import 'package:tutor1on1/llm/prompt_repository.dart';
import 'package:tutor1on1/services/artifact_sync_api_service.dart';
import 'package:tutor1on1/services/course_artifact_service.dart';
import 'package:tutor1on1/services/course_bundle_service.dart';
import 'package:tutor1on1/services/course_service.dart';
import 'package:tutor1on1/services/enrollment_sync_service.dart';
import 'package:tutor1on1/services/marketplace_api_service.dart';
import 'package:tutor1on1/services/prompt_bundle_compat.dart';
import 'package:tutor1on1/services/secure_storage_service.dart' as storage;

class _MemorySecureStorage extends storage.SecureStorageService {
  final Map<String, int> _installedVersionByKey = <String, int>{};
  final Map<String, String> _localState2ByKey = <String, String>{};
  final Map<String, DateTime> _runAtByKey = <String, DateTime>{};
  final Map<String, storage.SyncItemState> _syncItemStateByKey =
      <String, storage.SyncItemState>{};

  @override
  Future<String?> readAuthAccessToken() async => 'token';

  @override
  Future<int?> readInstalledCourseBundleVersion({
    required int remoteUserId,
    required int remoteCourseId,
  }) async {
    return _installedVersionByKey['$remoteUserId:$remoteCourseId'];
  }

  @override
  Future<void> writeInstalledCourseBundleVersion({
    required int remoteUserId,
    required int remoteCourseId,
    required int versionId,
  }) async {
    _installedVersionByKey['$remoteUserId:$remoteCourseId'] = versionId;
  }

  @override
  Future<String?> readLocalSyncState2({
    required int remoteUserId,
    required String domain,
  }) async {
    return _localState2ByKey['$remoteUserId:$domain'];
  }

  @override
  Future<void> writeLocalSyncState2({
    required int remoteUserId,
    required String domain,
    required String state2,
  }) async {
    _localState2ByKey['$remoteUserId:$domain'] = state2.trim();
  }

  @override
  Future<void> deleteLocalSyncState2({
    required int remoteUserId,
    required String domain,
  }) async {
    _localState2ByKey.remove('$remoteUserId:$domain');
  }

  @override
  Future<void> clearAllLocalSyncState2() async {
    _localState2ByKey.clear();
  }

  @override
  Future<DateTime?> readSyncRunAt({
    required int remoteUserId,
    required String domain,
  }) async {
    return _runAtByKey['$remoteUserId:$domain'];
  }

  @override
  Future<void> writeSyncRunAt({
    required int remoteUserId,
    required String domain,
    required DateTime runAt,
  }) async {
    _runAtByKey['$remoteUserId:$domain'] = runAt.toUtc();
  }

  @override
  Future<storage.SyncItemState?> readSyncItemState({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
  }) async {
    return _syncItemStateByKey['$remoteUserId:$domain:$scopeKey'];
  }

  @override
  Future<void> writeSyncItemState({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
    required String contentHash,
    required DateTime lastChangedAt,
    required DateTime lastSyncedAt,
  }) async {
    _syncItemStateByKey['$remoteUserId:$domain:$scopeKey'] =
        storage.SyncItemState(
      contentHash: contentHash,
      lastChangedAt: lastChangedAt.toUtc(),
      lastSyncedAt: lastSyncedAt.toUtc(),
    );
  }

  @override
  Future<void> clearSyncDomainState({
    required int remoteUserId,
    required String domain,
    bool clearItemStates = true,
    bool clearListEtags = true,
    bool clearRunAt = true,
  }) async {
    if (clearItemStates) {
      _syncItemStateByKey.removeWhere(
        (key, _) => key.startsWith('$remoteUserId:$domain:'),
      );
    }
    if (clearRunAt) {
      _runAtByKey.remove('$remoteUserId:$domain');
    }
  }
}

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

  @override
  Future<String?> getApplicationSupportPath() async {
    final dir = Directory(p.join(rootPath, 'support'));
    await dir.create(recursive: true);
    return dir.path;
  }
}

class _ServerCourse {
  _ServerCourse({
    required this.courseId,
    required this.bundleId,
    required this.teacherUserId,
    required this.teacherName,
    required this.subject,
    required this.bundleVersionId,
    required this.bundleSha256,
    required this.bundleBytes,
    required this.lastModified,
  });

  final int courseId;
  final int bundleId;
  final int teacherUserId;
  final String teacherName;
  final String subject;
  int bundleVersionId;
  String bundleSha256;
  Uint8List bundleBytes;
  String lastModified;
}

class _FakeCourseBundleServer {
  final Map<int, _ServerCourse> _courses = <int, _ServerCourse>{};
  final Map<int, Set<int>> _studentCourseIds = <int, Set<int>>{};
  int _nextBundleId = 7000;
  int _nextCourseId = 9000;

  void seedCourse({
    required int courseId,
    required int teacherUserId,
    required String teacherName,
    required String subject,
    required int bundleVersionId,
    required Uint8List bundleBytes,
    required String bundleSha256,
    String lastModified = '2026-04-01T00:00:00Z',
  }) {
    _courses[courseId] = _ServerCourse(
      courseId: courseId,
      bundleId: _nextBundleId++,
      teacherUserId: teacherUserId,
      teacherName: teacherName,
      subject: subject,
      bundleVersionId: bundleVersionId,
      bundleSha256: bundleSha256,
      bundleBytes: Uint8List.fromList(bundleBytes),
      lastModified: lastModified,
    );
    if (courseId >= _nextCourseId) {
      _nextCourseId = courseId + 1;
    }
  }

  void setStudentCourses(int studentUserId, List<int> courseIds) {
    _studentCourseIds[studentUserId] = courseIds.toSet();
  }

  List<_ServerCourse> visibleTeacherCourses(int teacherUserId) {
    final courses = _courses.values
        .where((course) => course.teacherUserId == teacherUserId)
        .toList(growable: false);
    courses.sort((left, right) => left.courseId.compareTo(right.courseId));
    return courses;
  }

  List<_ServerCourse> visibleStudentCourses(int studentUserId) {
    final courseIds = _studentCourseIds[studentUserId] ?? const <int>{};
    final courses = courseIds
        .map((courseId) => _courses[courseId])
        .whereType<_ServerCourse>()
        .toList(growable: false);
    courses.sort((left, right) => left.courseId.compareTo(right.courseId));
    return courses;
  }

  TeacherCourseSummary teacherCourseSummary(_ServerCourse course) {
    return TeacherCourseSummary(
      courseId: course.courseId,
      subject: course.subject,
      grade: '',
      description: '',
      visibility: 'private',
      approvalStatus: 'approved',
      publishedAt: '',
      latestBundleVersionId: course.bundleVersionId,
      latestBundleHash: course.bundleSha256,
      status: 'active',
    );
  }

  EnrollmentSummary enrollmentSummary(_ServerCourse course) {
    return EnrollmentSummary(
      enrollmentId: course.courseId,
      courseId: course.courseId,
      teacherId: course.teacherUserId,
      status: 'active',
      assignedAt: '',
      courseSubject: course.subject,
      teacherName: course.teacherName,
      latestBundleVersionId: course.bundleVersionId,
      latestBundleHash: course.bundleSha256,
    );
  }

  ArtifactState1Item artifactItem(_ServerCourse course) {
    return ArtifactState1Item(
      artifactId: 'course_bundle:${course.courseId}',
      artifactClass: 'course_bundle',
      courseId: course.courseId,
      teacherUserId: course.teacherUserId,
      studentUserId: 0,
      kpKey: '',
      bundleVersionId: course.bundleVersionId,
      sha256: course.bundleSha256,
      lastModified: course.lastModified,
    );
  }

  _ServerCourse ensureTeacherCourse({
    required int teacherUserId,
    required String subject,
  }) {
    for (final course in _courses.values) {
      if (course.teacherUserId == teacherUserId &&
          course.subject.trim().toLowerCase() == subject.trim().toLowerCase()) {
        return course;
      }
    }
    final course = _ServerCourse(
      courseId: _nextCourseId++,
      bundleId: _nextBundleId++,
      teacherUserId: teacherUserId,
      teacherName: 'teacher-$teacherUserId',
      subject: subject,
      bundleVersionId: 0,
      bundleSha256: '',
      bundleBytes: Uint8List(0),
      lastModified: '2026-04-01T00:00:00Z',
    );
    _courses[course.courseId] = course;
    return course;
  }

  _ServerCourse? courseById(int courseId) => _courses[courseId];

  void overwriteCourseBundle({
    required int courseId,
    required Uint8List bundleBytes,
    required String bundleSha256,
  }) {
    final course = _courses[courseId];
    if (course == null) {
      throw StateError('Server course $courseId not found.');
    }
    course.bundleVersionId = course.bundleVersionId + 1;
    course.bundleBytes = Uint8List.fromList(bundleBytes);
    course.bundleSha256 = bundleSha256;
    course.lastModified = DateTime.now().toUtc().toIso8601String();
  }
}

class _FakeArtifactSyncApiService extends ArtifactSyncApiService {
  _FakeArtifactSyncApiService({
    required this.server,
    required this.currentRemoteUserId,
    required this.currentRole,
    this.omitDownloadHeaders = false,
  }) : super(
          secureStorage: _MemorySecureStorage(),
          baseUrl: 'https://example.com',
          client: MockClient((_) async => http.Response('{}', 200)),
        );

  final _FakeCourseBundleServer server;
  final int currentRemoteUserId;
  final String currentRole;
  final bool omitDownloadHeaders;

  int downloadCalls = 0;
  int uploadCalls = 0;
  final List<String> uploadedArtifactIds = <String>[];

  List<ArtifactState1Item> _visibleItems(String artifactClass) {
    if (artifactClass != 'course_bundle') {
      return const <ArtifactState1Item>[];
    }
    final courses = currentRole == 'teacher'
        ? server.visibleTeacherCourses(currentRemoteUserId)
        : server.visibleStudentCourses(currentRemoteUserId);
    return courses.map(server.artifactItem).toList(growable: false);
  }

  @override
  Future<String> getState2({required String artifactClass}) async {
    final items = _visibleItems(artifactClass)
      ..sort((left, right) => left.artifactId.compareTo(right.artifactId));
    final builder = StringBuffer();
    for (final item in items) {
      builder
        ..write(item.artifactId)
        ..write('|')
        ..write(item.sha256)
        ..write('\n');
    }
    return 'artifact_state2_v1:${sha256.convert(utf8.encode(builder.toString()))}';
  }

  @override
  Future<ArtifactState1Result> getState1(
      {required String artifactClass}) async {
    final items = _visibleItems(artifactClass);
    return ArtifactState1Result(
      state2: await getState2(artifactClass: artifactClass),
      items: items,
    );
  }

  @override
  Future<DownloadedArtifact> downloadArtifact(String artifactId) async {
    downloadCalls++;
    final parts = artifactId.trim().split(':');
    final courseId = int.tryParse(parts.length > 1 ? parts[1].trim() : '') ?? 0;
    final course = server.courseById(courseId);
    if (course == null) {
      throw StateError('Missing server artifact $artifactId.');
    }
    return DownloadedArtifact(
      artifactId: omitDownloadHeaders ? '' : artifactId,
      artifactClass: omitDownloadHeaders ? '' : 'course_bundle',
      sha256: omitDownloadHeaders ? '' : course.bundleSha256,
      lastModified: course.lastModified,
      bytes: Uint8List.fromList(course.bundleBytes),
    );
  }

  @override
  Future<UploadArtifactResult> uploadArtifact({
    required String artifactId,
    required String sha256,
    required Uint8List bytes,
    required String baseSha256,
    required bool overwriteServer,
  }) async {
    uploadCalls++;
    uploadedArtifactIds.add(artifactId);
    final parts = artifactId.trim().split(':');
    final courseId = int.tryParse(parts.length > 1 ? parts[1].trim() : '') ?? 0;
    final course = server.courseById(courseId);
    if (course == null) {
      throw StateError('Missing server artifact target $artifactId.');
    }
    final currentHash = course.bundleSha256.trim();
    final expectedBase = baseSha256.trim();
    if (!overwriteServer) {
      if (currentHash.isEmpty && expectedBase.isNotEmpty) {
        throw ArtifactConflictException(
          message: 'Artifact conflict: server_missing',
          serverSha256: '',
          expectedBaseSha256: expectedBase,
        );
      }
      if (currentHash.isNotEmpty && currentHash != expectedBase) {
        throw ArtifactConflictException(
          message: 'Artifact conflict: server_changed',
          serverSha256: currentHash,
          expectedBaseSha256: expectedBase,
        );
      }
    }
    server.overwriteCourseBundle(
      courseId: courseId,
      bundleBytes: bytes,
      bundleSha256: sha256,
    );
    return UploadArtifactResult(
      artifactId: artifactId,
      sha256: sha256,
      bundleVersionId: course.bundleVersionId,
      state2: await getState2(artifactClass: 'course_bundle'),
    );
  }
}

class _FakeMarketplaceApiService extends MarketplaceApiService {
  _FakeMarketplaceApiService({
    required this.server,
    required this.currentRemoteUserId,
    required this.currentRole,
  }) : super(
          secureStorage: _MemorySecureStorage(),
          baseUrl: 'https://example.com',
          client: MockClient((_) async => http.Response('{}', 200)),
        );

  final _FakeCourseBundleServer server;
  final int currentRemoteUserId;
  final String currentRole;

  @override
  Future<List<EnrollmentSummary>> listEnrollments() async {
    return server
        .visibleStudentCourses(currentRemoteUserId)
        .map(server.enrollmentSummary)
        .toList(growable: false);
  }

  @override
  Future<List<TeacherCourseSummary>> listTeacherCourses() async {
    return server
        .visibleTeacherCourses(currentRemoteUserId)
        .map(server.teacherCourseSummary)
        .toList(growable: false);
  }

  @override
  Future<TeacherCourseSummary> createTeacherCourse({
    required String subject,
    String? grade,
    String? description,
    List<int> subjectLabelIds = const <int>[],
  }) async {
    final course = server.ensureTeacherCourse(
      teacherUserId: currentRemoteUserId,
      subject: subject,
    );
    return server.teacherCourseSummary(course);
  }

  @override
  Future<EnsureBundleResult> ensureBundle(
    int courseId, {
    String? courseName,
  }) async {
    final course = server.courseById(courseId);
    if (course == null) {
      throw StateError('Missing server course $courseId.');
    }
    return EnsureBundleResult(
      bundleId: course.bundleId,
      courseId: course.courseId,
    );
  }
}

Future<Directory> _createCourseFolder({
  required Directory root,
  required String folderName,
  required String rootTitle,
  String lectureText = 'Lecture body',
}) async {
  final dir = Directory(p.join(root.path, folderName));
  await dir.create(recursive: true);
  await File(p.join(dir.path, 'contents.txt')).writeAsString(
    '1 $rootTitle\n',
  );
  await File(p.join(dir.path, '1_lecture.txt')).writeAsString(
    lectureText,
  );
  return dir;
}

Future<_SeededBundle> _createSeededBundle({
  required Directory root,
  required String folderName,
  required String rootTitle,
  String lectureText = 'Lecture body',
}) async {
  final courseDir = await _createCourseFolder(
    root: root,
    folderName: folderName,
    rootTitle: rootTitle,
    lectureText: lectureText,
  );
  final bundleService = CourseBundleService();
  final bundleFile = await bundleService.createBundleFromFolder(courseDir.path);
  final bytes = await bundleFile.readAsBytes();
  final sha = await bundleService.computeBundleByteHash(bundleFile);
  await bundleFile.delete();
  return _SeededBundle(
    courseDir: courseDir,
    bytes: Uint8List.fromList(bytes),
    sha256: sha,
  );
}

class _SeededBundle {
  _SeededBundle({
    required this.courseDir,
    required this.bytes,
    required this.sha256,
  });

  final Directory courseDir;
  final Uint8List bytes;
  final String sha256;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory rootDir;
  late AppDatabase db;
  late _MemorySecureStorage secureStorage;
  late CourseArtifactService courseArtifactService;
  late CourseService courseService;
  late PromptRepository promptRepository;

  setUp(() async {
    rootDir = await Directory.systemTemp.createTemp('enrollment_sync_test_');
    PathProviderPlatform.instance = _TestPathProviderPlatform(rootDir.path);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    secureStorage = _MemorySecureStorage();
    courseArtifactService = CourseArtifactService(
      artifactsRootProvider: () async =>
          Directory(p.join(rootDir.path, 'artifacts')),
    );
    courseService = CourseService(
      db,
      courseArtifactService: courseArtifactService,
    );
    promptRepository = PromptRepository(db: db);
  });

  tearDown(() async {
    await db.close();
    if (await rootDir.exists()) {
      await rootDir.delete(recursive: true);
    }
  });

  test(
      'student sync stays clean after the next due interval when remote is unchanged',
      () async {
    final studentId = await db.createUser(
      username: 'albert',
      pinHash: 'pin',
      role: 'student',
      remoteUserId: 3001,
    );
    final student = (await db.getUserById(studentId))!;

    final seeded = await _createSeededBundle(
      root: rootDir,
      folderName: 'remote_math',
      rootTitle: 'Remote Math',
    );
    final server = _FakeCourseBundleServer()
      ..seedCourse(
        courseId: 501,
        teacherUserId: 9001,
        teacherName: 'dennis',
        subject: 'Remote Math',
        bundleVersionId: 7,
        bundleBytes: seeded.bytes,
        bundleSha256: seeded.sha256,
      )
      ..setStudentCourses(3001, const <int>[501]);
    final artifactApi = _FakeArtifactSyncApiService(
      server: server,
      currentRemoteUserId: 3001,
      currentRole: 'student',
    );
    final marketplaceApi = _FakeMarketplaceApiService(
      server: server,
      currentRemoteUserId: 3001,
      currentRole: 'student',
    );
    final service = EnrollmentSyncService(
      db: db,
      secureStorage: secureStorage,
      courseService: courseService,
      marketplaceApi: marketplaceApi,
      artifactApi: artifactApi,
      promptRepository: promptRepository,
      courseArtifactService: courseArtifactService,
    );

    final first = await service.syncIfReady(currentUser: student);
    expect(first.downloadedCount, 1);
    expect(first.uploadedCount, 0);
    expect(artifactApi.downloadCalls, 1);

    final assignedCourses = await db.getAssignedCoursesForStudent(student.id);
    expect(assignedCourses, hasLength(1));
    expect(
      await db.getCourseVersionIdForRemoteCourse(501),
      isNotNull,
    );
    await secureStorage.writeSyncRunAt(
      remoteUserId: 3001,
      domain: 'enrollment_sync_student',
      runAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
    );

    final second = await service.syncIfReady(currentUser: student);
    expect(second.downloadedCount, 0);
    expect(second.uploadedCount, 0);
    expect(artifactApi.downloadCalls, 1);
  });

  test('student sync accepts missing artifact download headers', () async {
    final studentId = await db.createUser(
      username: 'albert',
      pinHash: 'pin',
      role: 'student',
      remoteUserId: 3001,
    );
    final student = (await db.getUserById(studentId))!;

    final seeded = await _createSeededBundle(
      root: rootDir,
      folderName: 'remote_headerless_course',
      rootTitle: 'Headerless Math',
    );
    final server = _FakeCourseBundleServer()
      ..seedCourse(
        courseId: 510,
        teacherUserId: 9001,
        teacherName: 'dennis',
        subject: 'Headerless Math',
        bundleVersionId: 4,
        bundleBytes: seeded.bytes,
        bundleSha256: seeded.sha256,
      )
      ..setStudentCourses(3001, const <int>[510]);
    final artifactApi = _FakeArtifactSyncApiService(
      server: server,
      currentRemoteUserId: 3001,
      currentRole: 'student',
      omitDownloadHeaders: true,
    );
    final marketplaceApi = _FakeMarketplaceApiService(
      server: server,
      currentRemoteUserId: 3001,
      currentRole: 'student',
    );
    final service = EnrollmentSyncService(
      db: db,
      secureStorage: secureStorage,
      courseService: courseService,
      marketplaceApi: marketplaceApi,
      artifactApi: artifactApi,
      promptRepository: promptRepository,
      courseArtifactService: courseArtifactService,
    );

    final result = await service.syncIfReady(currentUser: student);
    expect(result.downloadedCount, 1);
    expect(artifactApi.downloadCalls, 1);
    expect(await db.getCourseVersionIdForRemoteCourse(510), isNotNull);
    expect(await db.getAssignedCoursesForStudent(student.id), hasLength(1));
  });

  test(
      'teacher sync downloads remote course without eagerly preparing upload bundle',
      () async {
    final teacherId = await db.createUser(
      username: 'dennis',
      pinHash: 'pin',
      role: 'teacher',
      remoteUserId: 9001,
    );
    final teacher = (await db.getUserById(teacherId))!;

    final seeded = await _createSeededBundle(
      root: rootDir,
      folderName: 'remote_teacher_course',
      rootTitle: 'Remote Math',
    );
    final server = _FakeCourseBundleServer()
      ..seedCourse(
        courseId: 501,
        teacherUserId: 9001,
        teacherName: 'dennis',
        subject: 'Remote Math',
        bundleVersionId: 3,
        bundleBytes: seeded.bytes,
        bundleSha256: seeded.sha256,
      );
    final artifactApi = _FakeArtifactSyncApiService(
      server: server,
      currentRemoteUserId: 9001,
      currentRole: 'teacher',
    );
    final marketplaceApi = _FakeMarketplaceApiService(
      server: server,
      currentRemoteUserId: 9001,
      currentRole: 'teacher',
    );
    final service = EnrollmentSyncService(
      db: db,
      secureStorage: secureStorage,
      courseService: courseService,
      marketplaceApi: marketplaceApi,
      artifactApi: artifactApi,
      promptRepository: promptRepository,
      courseArtifactService: courseArtifactService,
    );

    final first = await service.syncIfReady(currentUser: teacher);
    expect(first.downloadedCount, 1);
    expect(first.uploadedCount, 0);

    final localCourseVersionId =
        await db.getCourseVersionIdForRemoteCourse(501);
    expect(localCourseVersionId, isNotNull);
    final importedManifest =
        await courseArtifactService.readCourseArtifacts(localCourseVersionId!);
    expect(importedManifest, isNotNull);
    expect(importedManifest!.chapters, isEmpty);
    expect(
      await courseArtifactService
          .readPreparedUploadBundle(localCourseVersionId),
      isNull,
    );
    final prepared = await courseArtifactService.prepareUploadBundle(
      courseVersionId: localCourseVersionId,
      promptMetadata: <String, dynamic>{
        'schema': kCurrentPromptBundleSchema,
        'remote_course_id': 501,
        'teacher_username': 'dennis',
        'prompt_templates': const <Map<String, dynamic>>[],
        'student_prompt_profiles': const <Map<String, dynamic>>[],
        'student_pass_configs': const <Map<String, dynamic>>[],
      },
      bundleLabel: 'Remote Math',
    );
    expect(prepared.hash, isNotEmpty);

    await secureStorage.writeSyncRunAt(
      remoteUserId: 9001,
      domain: 'enrollment_sync_teacher',
      runAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
    );

    final second = await service.syncIfReady(currentUser: teacher);
    expect(second.downloadedCount, 0);
    expect(second.uploadedCount, 0);
    expect(artifactApi.uploadCalls, 0);
  });

  test('teacher sync uploads one changed course bundle artifact', () async {
    final teacherId = await db.createUser(
      username: 'dennis',
      pinHash: 'pin',
      role: 'teacher',
      remoteUserId: 9001,
    );
    final teacher = (await db.getUserById(teacherId))!;

    final localCourseDir = await _createCourseFolder(
      root: rootDir,
      folderName: 'local_teacher_course',
      rootTitle: 'Remote Math',
    );
    final courseVersionId = await db.createCourseVersion(
      teacherId: teacher.id,
      subject: 'Remote Math',
      granularity: 1,
      textbookText: '',
      sourcePath: localCourseDir.path,
    );
    await db.upsertCourseRemoteLink(
      courseVersionId: courseVersionId,
      remoteCourseId: 501,
    );
    await courseArtifactService.rebuildCourseArtifacts(
      courseVersionId: courseVersionId,
      folderPath: localCourseDir.path,
    );
    final initialPrepared = await courseArtifactService.prepareUploadBundle(
      courseVersionId: courseVersionId,
      promptMetadata: <String, dynamic>{
        'schema': kCurrentPromptBundleSchema,
        'remote_course_id': 501,
        'teacher_username': 'dennis',
        'prompt_templates': const <Map<String, dynamic>>[],
        'student_prompt_profiles': const <Map<String, dynamic>>[],
        'student_pass_configs': const <Map<String, dynamic>>[],
      },
      bundleLabel: 'Remote Math',
    );
    final server = _FakeCourseBundleServer()
      ..seedCourse(
        courseId: 501,
        teacherUserId: 9001,
        teacherName: 'dennis',
        subject: 'Remote Math',
        bundleVersionId: 3,
        bundleBytes: await initialPrepared.bundleFile.readAsBytes(),
        bundleSha256: initialPrepared.hash,
      );
    final artifactApi = _FakeArtifactSyncApiService(
      server: server,
      currentRemoteUserId: 9001,
      currentRole: 'teacher',
    );
    final marketplaceApi = _FakeMarketplaceApiService(
      server: server,
      currentRemoteUserId: 9001,
      currentRole: 'teacher',
    );
    final service = EnrollmentSyncService(
      db: db,
      secureStorage: secureStorage,
      courseService: courseService,
      marketplaceApi: marketplaceApi,
      artifactApi: artifactApi,
      promptRepository: promptRepository,
      courseArtifactService: courseArtifactService,
    );

    final first = await service.syncIfReady(currentUser: teacher);
    expect(first.downloadedCount, 0);
    expect(first.uploadedCount, 0);
    await secureStorage.writeSyncRunAt(
      remoteUserId: 9001,
      domain: 'enrollment_sync_teacher',
      runAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
    );

    final cleanSecond = await service.syncIfReady(currentUser: teacher);
    expect(cleanSecond.uploadedCount, 0);
    expect(cleanSecond.downloadedCount, 0);
    expect(artifactApi.uploadCalls, 0);

    await File(p.join(localCourseDir.path, '1_lecture.txt')).writeAsString(
      'Teacher changed lesson text',
    );
    await courseArtifactService.rebuildCourseArtifacts(
      courseVersionId: courseVersionId,
      folderPath: localCourseDir.path,
    );
    await service.refreshStoredLocalState2(currentUser: teacher);
    await secureStorage.writeSyncRunAt(
      remoteUserId: 9001,
      domain: 'enrollment_sync_teacher',
      runAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
    );

    final second = await service.syncIfReady(currentUser: teacher);
    expect(second.uploadedCount, 1);
    expect(second.downloadedCount, 0);
    expect(artifactApi.uploadCalls, 1);
    expect(artifactApi.uploadedArtifactIds,
        equals(const <String>['course_bundle:501']));
    await secureStorage.writeSyncRunAt(
      remoteUserId: 9001,
      domain: 'enrollment_sync_teacher',
      runAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
    );

    final third = await service.syncIfReady(currentUser: teacher);
    expect(third.uploadedCount, 0);
    expect(third.downloadedCount, 0);
    expect(artifactApi.uploadCalls, 1);
  });

  test('student sync deletes local course when remote artifact disappears',
      () async {
    final studentId = await db.createUser(
      username: 'albert',
      pinHash: 'pin',
      role: 'student',
      remoteUserId: 3001,
    );
    final student = (await db.getUserById(studentId))!;

    final seeded = await _createSeededBundle(
      root: rootDir,
      folderName: 'remote_delete_course',
      rootTitle: 'Delete Me',
    );
    final server = _FakeCourseBundleServer()
      ..seedCourse(
        courseId: 777,
        teacherUserId: 9001,
        teacherName: 'dennis',
        subject: 'Delete Me',
        bundleVersionId: 2,
        bundleBytes: seeded.bytes,
        bundleSha256: seeded.sha256,
      )
      ..setStudentCourses(3001, const <int>[777]);
    final artifactApi = _FakeArtifactSyncApiService(
      server: server,
      currentRemoteUserId: 3001,
      currentRole: 'student',
    );
    final marketplaceApi = _FakeMarketplaceApiService(
      server: server,
      currentRemoteUserId: 3001,
      currentRole: 'student',
    );
    final service = EnrollmentSyncService(
      db: db,
      secureStorage: secureStorage,
      courseService: courseService,
      marketplaceApi: marketplaceApi,
      artifactApi: artifactApi,
      promptRepository: promptRepository,
      courseArtifactService: courseArtifactService,
    );

    final first = await service.syncIfReady(currentUser: student);
    expect(first.downloadedCount, 1);
    expect(await db.getAssignedCoursesForStudent(student.id), hasLength(1));

    server.setStudentCourses(3001, const <int>[]);
    await secureStorage.writeSyncRunAt(
      remoteUserId: 3001,
      domain: 'enrollment_sync_student',
      runAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
    );

    final second = await service.syncIfReady(currentUser: student);
    expect(second.downloadedCount, 0);
    expect(second.uploadedCount, 0);
    expect(await db.getAssignedCoursesForStudent(student.id), isEmpty);
    expect(await db.getCourseVersionIdForRemoteCourse(777), isNull);
  });
}
