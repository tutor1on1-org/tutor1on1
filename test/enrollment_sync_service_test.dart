import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:family_teacher/db/app_database.dart';
import 'package:family_teacher/llm/prompt_repository.dart';
import 'package:family_teacher/services/course_bundle_service.dart';
import 'package:family_teacher/services/course_service.dart';
import 'package:family_teacher/services/enrollment_sync_service.dart';
import 'package:family_teacher/services/marketplace_api_service.dart';
import 'package:family_teacher/services/secure_storage_service.dart' as storage;

class _TestSecureStorageService extends storage.SecureStorageService {
  _TestSecureStorageService({
    String? accessToken,
    int? deletionCursor,
  })  : _accessToken = accessToken,
        _deletionCursor = deletionCursor;

  final String? _accessToken;
  int? _deletionCursor;
  final Map<String, int> _installedVersionByKey = <String, int>{};
  final Map<String, String> _etagByKey = <String, String>{};
  final Map<String, DateTime> _runAtByDomain = <String, DateTime>{};
  final Map<String, storage.SyncItemState> _syncItemStateByKey =
      <String, storage.SyncItemState>{};

  @override
  Future<String?> readAuthAccessToken() async => _accessToken;

  @override
  Future<int?> readEnrollmentDeletionCursor(int remoteUserId) async {
    return _deletionCursor;
  }

  @override
  Future<void> writeEnrollmentDeletionCursor(
    int remoteUserId,
    int eventId,
  ) async {
    _deletionCursor = eventId;
  }

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
  Future<String?> readSyncListEtag({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
  }) async {
    return _etagByKey['$remoteUserId:$domain:$scopeKey'];
  }

  @override
  Future<void> writeSyncListEtag({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
    required String etag,
  }) async {
    _etagByKey['$remoteUserId:$domain:$scopeKey'] = etag;
  }

  @override
  Future<DateTime?> readSyncRunAt({
    required int remoteUserId,
    required String domain,
  }) async {
    return _runAtByDomain['$remoteUserId:$domain'];
  }

  @override
  Future<void> writeSyncRunAt({
    required int remoteUserId,
    required String domain,
    required DateTime runAt,
  }) async {
    _runAtByDomain['$remoteUserId:$domain'] = runAt.toUtc();
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
}

class _TestMarketplaceApiService extends MarketplaceApiService {
  _TestMarketplaceApiService({
    required storage.SecureStorageService secureStorage,
    List<EnrollmentSummary>? enrollments,
    List<EnrollmentDeletionEvent>? deletionEvents,
    List<TeacherCourseSummary>? teacherCourses,
    Map<int, List<TeacherBundleVersionSummary>>?
        teacherBundleVersionsByCourseId,
    Map<int, File>? bundleFilesByVersionId,
    List<EnrollmentDeletionEvent> Function(int? sinceId)?
        deletionEventsProvider,
    this.enrollmentsNotModified = false,
    this.teacherCoursesNotModified = false,
    this.enrollmentsEtag = 'enrollment-etag',
    this.teacherCoursesEtag = 'teacher-courses-etag',
  })  : _enrollments = enrollments ?? const <EnrollmentSummary>[],
        _deletionEvents = deletionEvents ?? const <EnrollmentDeletionEvent>[],
        _teacherCourses = teacherCourses ?? const <TeacherCourseSummary>[],
        _teacherBundleVersionsByCourseId = teacherBundleVersionsByCourseId ??
            const <int, List<TeacherBundleVersionSummary>>{},
        _bundleFilesByVersionId = bundleFilesByVersionId ?? const <int, File>{},
        _deletionEventsProvider = deletionEventsProvider,
        super(
          secureStorage: secureStorage,
          baseUrl: 'https://example.com',
          client: MockClient(
            (_) async => http.Response('[]', 200),
          ),
        );

  final List<EnrollmentSummary> _enrollments;
  final List<EnrollmentDeletionEvent> _deletionEvents;
  final List<TeacherCourseSummary> _teacherCourses;
  final Map<int, List<TeacherBundleVersionSummary>>
      _teacherBundleVersionsByCourseId;
  final Map<int, File> _bundleFilesByVersionId;
  final List<EnrollmentDeletionEvent> Function(int? sinceId)?
      _deletionEventsProvider;
  final bool enrollmentsNotModified;
  final bool teacherCoursesNotModified;
  final String? enrollmentsEtag;
  final String? teacherCoursesEtag;
  final List<_UploadedBundleRecord> uploadedBundles = <_UploadedBundleRecord>[];
  int? lastDeletionSinceId;
  String? lastEnrollmentsIfNoneMatch;
  String? lastTeacherCoursesIfNoneMatch;
  int listEnrollmentsDeltaCalls = 0;
  int listDeletionEventsCalls = 0;
  int listTeacherCoursesDeltaCalls = 0;
  int listTeacherCoursesCalls = 0;
  int listTeacherBundleVersionsCalls = 0;

  @override
  Future<List<EnrollmentSummary>> listEnrollments() async {
    return _enrollments;
  }

  @override
  Future<MarketplaceListResult<EnrollmentSummary>> listEnrollmentsDelta({
    String? ifNoneMatch,
  }) async {
    listEnrollmentsDeltaCalls++;
    lastEnrollmentsIfNoneMatch = ifNoneMatch;
    return MarketplaceListResult<EnrollmentSummary>(
      items:
          enrollmentsNotModified ? const <EnrollmentSummary>[] : _enrollments,
      etag: enrollmentsEtag,
      notModified: enrollmentsNotModified,
    );
  }

  @override
  Future<List<EnrollmentDeletionEvent>> listEnrollmentDeletionEvents({
    int? sinceId,
  }) async {
    listDeletionEventsCalls++;
    lastDeletionSinceId = sinceId;
    if (_deletionEventsProvider != null) {
      return _deletionEventsProvider(sinceId);
    }
    return _deletionEvents;
  }

  @override
  Future<List<TeacherCourseSummary>> listTeacherCourses() async {
    listTeacherCoursesCalls++;
    return _teacherCourses;
  }

  @override
  Future<MarketplaceListResult<TeacherCourseSummary>> listTeacherCoursesDelta({
    String? ifNoneMatch,
  }) async {
    listTeacherCoursesDeltaCalls++;
    lastTeacherCoursesIfNoneMatch = ifNoneMatch;
    return MarketplaceListResult<TeacherCourseSummary>(
      items: teacherCoursesNotModified
          ? const <TeacherCourseSummary>[]
          : _teacherCourses,
      etag: teacherCoursesEtag,
      notModified: teacherCoursesNotModified,
    );
  }

  @override
  Future<List<TeacherBundleVersionSummary>> listTeacherBundleVersions(
    int courseId,
  ) async {
    listTeacherBundleVersionsCalls++;
    return _teacherBundleVersionsByCourseId[courseId] ??
        const <TeacherBundleVersionSummary>[];
  }

  @override
  Future<File> downloadBundleToFile({
    required int bundleVersionId,
    required String targetPath,
  }) async {
    final source = _bundleFilesByVersionId[bundleVersionId];
    if (source == null || !source.existsSync()) {
      throw StateError(
        'Missing test bundle file for version $bundleVersionId.',
      );
    }
    final target = File(targetPath);
    await target.parent.create(recursive: true);
    return source.copy(targetPath);
  }

  @override
  Future<Map<String, dynamic>> uploadBundle({
    required int bundleId,
    required String courseName,
    required File bundleFile,
  }) async {
    final copyDir = await Directory.systemTemp.createTemp('ft_upload_bundle_');
    final copyPath = p.join(copyDir.path, p.basename(bundleFile.path));
    final copy = await bundleFile.copy(copyPath);
    uploadedBundles.add(
      _UploadedBundleRecord(
        bundleId: bundleId,
        courseName: courseName,
        bundleFile: copy,
      ),
    );
    return <String, dynamic>{
      'bundle_version_id': bundleId * 1000 + uploadedBundles.length,
      'status': 'uploaded',
    };
  }

  @override
  Future<EnsureBundleResult> ensureBundle(
    int courseId, {
    String? courseName,
  }) async {
    return EnsureBundleResult(
      bundleId: courseId * 10,
      courseId: courseId,
    );
  }
}

class _UploadedBundleRecord {
  _UploadedBundleRecord({
    required this.bundleId,
    required this.courseName,
    required this.bundleFile,
  });

  final int bundleId;
  final String courseName;
  final File bundleFile;
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
}

Future<Directory> _createCourseFolder({
  required String label,
  required String rootTitle,
}) async {
  final dir = await Directory.systemTemp.createTemp('ft_course_$label');
  await File(p.join(dir.path, 'contents.txt')).writeAsString(
    '1 $rootTitle\n',
  );
  await File(p.join(dir.path, '1_lecture.txt')).writeAsString(
    'Lecture for $rootTitle',
  );
  return dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  final tempPaths = <String>[];
  final tempFiles = <String>[];
  late Directory pathProviderRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    pathProviderRoot =
        Directory.systemTemp.createTempSync('ft_test_path_provider_');
    PathProviderPlatform.instance =
        _TestPathProviderPlatform(pathProviderRoot.path);
  });

  tearDown(() async {
    await db.close();
    for (final path in tempPaths) {
      final directory = Directory(path);
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    }
    tempPaths.clear();
    for (final path in tempFiles) {
      final file = File(path);
      if (file.existsSync()) {
        await file.delete();
      }
    }
    tempFiles.clear();
    if (pathProviderRoot.existsSync()) {
      await pathProviderRoot.delete(recursive: true);
    }
  });

  test(
    'teacher sync reuses suffix-named local course via normalized subject',
    () async {
      final teacherId = await db.createUser(
        username: 'teacher_a',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 701,
      );
      final localCourseId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'Algebra_1700000000',
        granularity: 1,
        textbookText: '',
        sourcePath: r'C:\courses\algebra',
      );
      final teacher = await db.getUserById(teacherId);
      expect(teacher, isNotNull);
      final remoteDir = await _createCourseFolder(
        label: 'teacher_sync_suffix_remote',
        rootTitle: 'Algebra',
      );
      tempPaths.add(remoteDir.path);
      final remoteBundle = await CourseBundleService().createBundleFromFolder(
        remoteDir.path,
      );
      tempFiles.add(remoteBundle.path);

      final secureStorage = _TestSecureStorageService();
      final api = _TestMarketplaceApiService(
        secureStorage: secureStorage,
        teacherCourses: <TeacherCourseSummary>[
          TeacherCourseSummary(
            courseId: 91,
            subject: 'Algebra',
            grade: '',
            description: '',
            visibility: 'private',
            publishedAt: '',
            latestBundleVersionId: 3,
            status: 'active',
          ),
        ],
        bundleFilesByVersionId: <int, File>{3: remoteBundle},
      );
      final service = EnrollmentSyncService(
        db: db,
        secureStorage: secureStorage,
        courseService: CourseService(db),
        marketplaceApi: api,
        promptRepository: PromptRepository(db: db),
      );

      await service.syncIfReady(currentUser: teacher!);

      final linkedCourseId = await db.getCourseVersionIdForRemoteCourse(91);
      expect(linkedCourseId, equals(localCourseId));
      final linkedRemoteId = await db.getRemoteCourseId(localCourseId);
      expect(linkedRemoteId, equals(91));

      final updated = await db.getCourseVersionById(localCourseId);
      expect(updated, isNotNull);
      expect(updated!.subject, equals('Algebra'));

      final allTeacherCourses = await db.getCourseVersionsForTeacher(teacherId);
      expect(allTeacherCourses.length, equals(1));
      expect(allTeacherCourses.first.id, equals(localCourseId));
    },
  );

  test(
    'teacher first sync downloads remote bundle when local course hash differs',
    () async {
      final teacherId = await db.createUser(
        username: 'teacher_pull_remote',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 1701,
      );
      final studentId = await db.createUser(
        username: 'student_pull_remote',
        pinHash: 'hash',
        role: 'student',
        teacherId: teacherId,
        remoteUserId: 1702,
      );
      final localDir = await _createCourseFolder(
        label: 'local_pull_remote',
        rootTitle: 'Local Topic',
      );
      tempPaths.add(localDir.path);
      final remoteDir = await _createCourseFolder(
        label: 'remote_pull_remote',
        rootTitle: 'Remote Topic',
      );
      tempPaths.add(remoteDir.path);
      final courseVersionId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'Physics',
        granularity: 1,
        textbookText: '1 Local Topic',
        sourcePath: localDir.path,
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: 9101,
      );
      final teacher = await db.getUserById(teacherId);
      expect(teacher, isNotNull);

      final bundleService = CourseBundleService();
      final remoteBundle = await bundleService.createBundleFromFolder(
        remoteDir.path,
        promptMetadata: <String, dynamic>{
          'schema': 'family_teacher_prompt_bundle_v1',
          'remote_course_id': 9101,
          'teacher_username': 'teacher_pull_remote',
          'prompt_templates': <Map<String, dynamic>>[
            <String, dynamic>{
              'prompt_name': 'learn_init',
              'scope': 'course',
              'content': 'REMOTE COURSE PROMPT',
            },
            <String, dynamic>{
              'prompt_name': 'review_cont',
              'scope': 'student',
              'content': 'REMOTE STUDENT PROMPT',
              'student_remote_user_id': 1702,
              'student_username': 'student_pull_remote',
            },
          ],
          'student_prompt_profiles': <Map<String, dynamic>>[
            <String, dynamic>{
              'scope': 'student',
              'student_remote_user_id': 1702,
              'student_username': 'student_pull_remote',
              'preferred_tone': 'calm',
            },
          ],
        },
      );
      tempFiles.add(remoteBundle.path);
      final remoteHash =
          await bundleService.computeBundleSemanticHash(remoteBundle);

      final secureStorage = _TestSecureStorageService();
      final api = _TestMarketplaceApiService(
        secureStorage: secureStorage,
        teacherCourses: <TeacherCourseSummary>[
          TeacherCourseSummary(
            courseId: 9101,
            subject: 'Physics',
            grade: '',
            description: '',
            visibility: 'private',
            publishedAt: '',
            latestBundleVersionId: 301,
            status: 'active',
          ),
        ],
        teacherBundleVersionsByCourseId: <int,
            List<TeacherBundleVersionSummary>>{
          9101: <TeacherBundleVersionSummary>[
            TeacherBundleVersionSummary(
              bundleVersionId: 301,
              bundleId: 91,
              version: 3,
              hash: remoteHash,
              createdAt: '2026-03-08T00:00:00Z',
              sizeBytes: remoteBundle.lengthSync(),
              isLatest: true,
              fileMissing: false,
            ),
          ],
        },
        bundleFilesByVersionId: <int, File>{301: remoteBundle},
      );
      final service = EnrollmentSyncService(
        db: db,
        secureStorage: secureStorage,
        courseService: CourseService(db),
        marketplaceApi: api,
        promptRepository: PromptRepository(db: db),
      );

      await service.syncIfReady(currentUser: teacher!);

      final updatedCourse = await db.getCourseVersionById(courseVersionId);
      expect(updatedCourse, isNotNull);
      expect(updatedCourse!.textbookText, contains('Remote Topic'));
      expect(updatedCourse.sourcePath, isNot(equals(localDir.path)));
      expect(
        await secureStorage.readInstalledCourseBundleVersion(
          remoteUserId: 1701,
          remoteCourseId: 9101,
        ),
        equals(301),
      );
      final syncState = await secureStorage.readSyncItemState(
        remoteUserId: 1701,
        domain: 'enrollment_sync_teacher_upload',
        scopeKey: 'course:9101',
      );
      expect(syncState, isNotNull);
      expect(syncState!.contentHash, equals(remoteHash));

      final activeCoursePrompt = await db.getActivePromptTemplate(
        teacherId: teacherId,
        promptName: 'learn_init',
        courseKey: updatedCourse.sourcePath,
        studentId: null,
      );
      expect(activeCoursePrompt, isNotNull);
      expect(activeCoursePrompt!.content, equals('REMOTE COURSE PROMPT'));

      final activeStudentPrompt = await db.getActivePromptTemplate(
        teacherId: teacherId,
        promptName: 'review_cont',
        courseKey: updatedCourse.sourcePath,
        studentId: studentId,
      );
      expect(activeStudentPrompt, isNotNull);
      expect(activeStudentPrompt!.content, equals('REMOTE STUDENT PROMPT'));

      final studentProfile = await db.getStudentPromptProfile(
        teacherId: teacherId,
        courseKey: updatedCourse.sourcePath,
        studentId: studentId,
      );
      expect(studentProfile, isNotNull);
      expect(studentProfile!.preferredTone, equals('calm'));
      expect(api.listTeacherBundleVersionsCalls, equals(1));
    },
  );

  test(
    'teacher upload reuses loaded course manifest and excludes teacher-global prompts',
    () async {
      final teacherId = await db.createUser(
        username: 'teacher_upload_bundle',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 1801,
      );
      final studentId = await db.createUser(
        username: 'student_upload_bundle',
        pinHash: 'hash',
        role: 'student',
        teacherId: teacherId,
        remoteUserId: 1802,
      );
      final courseADir = await _createCourseFolder(
        label: 'upload_course_a',
        rootTitle: 'Course A Topic',
      );
      tempPaths.add(courseADir.path);
      final courseBDir = await _createCourseFolder(
        label: 'upload_course_b',
        rootTitle: 'Course B Topic',
      );
      tempPaths.add(courseBDir.path);

      final courseAId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'Course A',
        granularity: 1,
        textbookText: '1 Course A Topic',
        sourcePath: courseADir.path,
      );
      final courseBId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'Course B',
        granularity: 1,
        textbookText: '1 Course B Topic',
        sourcePath: courseBDir.path,
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseAId,
        remoteCourseId: 9201,
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseBId,
        remoteCourseId: 9202,
      );
      await db.insertPromptTemplate(
        teacherId: teacherId,
        promptName: 'learn_init',
        content: 'GLOBAL PROMPT',
      );
      await db.insertPromptTemplate(
        teacherId: teacherId,
        promptName: 'learn_init',
        content: 'COURSE PROMPT',
        courseKey: courseADir.path,
      );
      await db.insertPromptTemplate(
        teacherId: teacherId,
        promptName: 'review_cont',
        content: 'STUDENT PROMPT',
        courseKey: courseADir.path,
        studentId: studentId,
      );
      await db.upsertStudentPromptProfile(
        teacherId: teacherId,
        courseKey: courseADir.path,
        studentId: studentId,
        preferredTone: 'energetic',
      );
      final teacher = await db.getUserById(teacherId);
      expect(teacher, isNotNull);

      final secureStorage = _TestSecureStorageService();
      await secureStorage.writeSyncRunAt(
        remoteUserId: 1801,
        domain: 'enrollment_sync_teacher',
        runAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      );
      final api = _TestMarketplaceApiService(
        secureStorage: secureStorage,
        teacherCourses: <TeacherCourseSummary>[
          TeacherCourseSummary(
            courseId: 9201,
            subject: 'Course A',
            grade: '',
            description: '',
            visibility: 'private',
            publishedAt: '',
            latestBundleVersionId: null,
            status: 'active',
          ),
          TeacherCourseSummary(
            courseId: 9202,
            subject: 'Course B',
            grade: '',
            description: '',
            visibility: 'private',
            publishedAt: '',
            latestBundleVersionId: null,
            status: 'active',
          ),
        ],
      );
      final service = EnrollmentSyncService(
        db: db,
        secureStorage: secureStorage,
        courseService: CourseService(db),
        marketplaceApi: api,
        promptRepository: PromptRepository(db: db),
      );

      await service.syncIfReady(currentUser: teacher!);

      expect(api.listTeacherCoursesDeltaCalls, equals(1));
      expect(api.listTeacherCoursesCalls, equals(1));
      expect(api.uploadedBundles.length, equals(2));

      final uploadedCourseABundle = api.uploadedBundles.firstWhere(
        (entry) => entry.courseName == 'Course A',
      );
      tempPaths.add(uploadedCourseABundle.bundleFile.parent.path);
      final metadata = await CourseBundleService()
          .readPromptMetadataFromBundleFile(uploadedCourseABundle.bundleFile);
      expect(metadata, isNotNull);
      final promptTemplates = (metadata!['prompt_templates'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(
        promptTemplates.any((item) => item['scope'] == 'teacher'),
        isFalse,
      );
      expect(
        promptTemplates.any((item) => item['scope'] == 'course'),
        isTrue,
      );
      expect(
        promptTemplates.any((item) => item['scope'] == 'student'),
        isTrue,
      );
      final studentProfiles =
          (metadata['student_prompt_profiles'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
      expect(
        studentProfiles.any((item) => item['scope'] == 'teacher'),
        isFalse,
      );
      expect(
        studentProfiles.any((item) => item['scope'] == 'student'),
        isTrue,
      );
    },
  );

  test(
    'student sync migrates and removes suffix duplicate course rows',
    () async {
      final teacherId = await db.createUser(
        username: 'teacher_b',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 801,
      );
      final studentId = await db.createUser(
        username: 'student_b',
        pinHash: 'hash',
        role: 'student',
        teacherId: teacherId,
        remoteUserId: 901,
      );
      final canonicalCourseId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'Biology',
        granularity: 1,
        textbookText: '',
        sourcePath: r'C:\courses\biology',
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: canonicalCourseId,
        remoteCourseId: 5001,
      );
      await db.assignStudent(
        studentId: studentId,
        courseVersionId: canonicalCourseId,
      );

      final staleCourseId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'Biology_1700000000',
        granularity: 1,
        textbookText: '',
        sourcePath: r'C:\courses\biology_old',
      );
      await db.assignStudent(
        studentId: studentId,
        courseVersionId: staleCourseId,
      );
      await db.upsertProgress(
        studentId: studentId,
        courseVersionId: staleCourseId,
        kpKey: '1.1',
        lit: true,
      );

      final student = await db.getUserById(studentId);
      expect(student, isNotNull);

      final secureStorage = _TestSecureStorageService();
      final api = _TestMarketplaceApiService(
        secureStorage: secureStorage,
        enrollments: <EnrollmentSummary>[
          EnrollmentSummary(
            enrollmentId: 1,
            courseId: 5001,
            teacherId: teacherId,
            status: 'approved',
            assignedAt: '2026-02-27T00:00:00Z',
            courseSubject: 'Biology',
            teacherName: 'teacher_b',
            latestBundleVersionId: null,
          ),
        ],
      );
      final service = EnrollmentSyncService(
        db: db,
        secureStorage: secureStorage,
        courseService: CourseService(db),
        marketplaceApi: api,
        promptRepository: PromptRepository(db: db),
      );

      await service.syncIfReady(currentUser: student!);

      final assigned = await db.getAssignedCoursesForStudent(studentId);
      expect(assigned.length, equals(1));
      expect(assigned.first.id, equals(canonicalCourseId));

      final staleCourse = await db.getCourseVersionById(staleCourseId);
      expect(staleCourse, isNull);

      final movedProgress = await db.getProgress(
        studentId: studentId,
        courseVersionId: canonicalCourseId,
        kpKey: '1.1',
      );
      expect(movedProgress, isNotNull);
      expect(movedProgress!.lit, isTrue);
    },
  );

  test(
    'student sync rebinds remote-linked course ownership to remote teacher user',
    () async {
      final studentId = await db.createUser(
        username: 'student_owner_fix',
        pinHash: 'hash',
        role: 'student',
        remoteUserId: 951,
      );
      final corruptedCourseId = await db.createCourseVersion(
        teacherId: studentId,
        subject: 'Geometry',
        granularity: 1,
        textbookText: '',
        sourcePath: r'C:\courses\geometry',
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: corruptedCourseId,
        remoteCourseId: 8101,
      );
      await db.assignStudent(
        studentId: studentId,
        courseVersionId: corruptedCourseId,
      );

      final student = await db.getUserById(studentId);
      expect(student, isNotNull);

      final secureStorage = _TestSecureStorageService();
      final api = _TestMarketplaceApiService(
        secureStorage: secureStorage,
        enrollments: <EnrollmentSummary>[
          EnrollmentSummary(
            enrollmentId: 11,
            courseId: 8101,
            teacherId: 9101,
            status: 'approved',
            assignedAt: '2026-02-28T00:00:00Z',
            courseSubject: 'Geometry',
            teacherName: 'remote_teacher',
            latestBundleVersionId: null,
          ),
        ],
      );
      final service = EnrollmentSyncService(
        db: db,
        secureStorage: secureStorage,
        courseService: CourseService(db),
        marketplaceApi: api,
        promptRepository: PromptRepository(db: db),
      );

      await service.syncIfReady(currentUser: student!);

      final repaired = await db.getCourseVersionById(corruptedCourseId);
      expect(repaired, isNotNull);
      expect(repaired!.teacherId, isNot(studentId));

      final localTeacher = await db.findUserByRemoteId(9101);
      expect(localTeacher, isNotNull);
      expect(localTeacher!.role, equals('teacher'));
      expect(localTeacher.username, equals('remote_teacher'));
      expect(repaired.teacherId, equals(localTeacher.id));
    },
  );

  test(
    'student sync renames existing remote teacher placeholder to provided teacher name',
    () async {
      final studentId = await db.createUser(
        username: 'student_teacher_name_fix',
        pinHash: 'hash',
        role: 'student',
        remoteUserId: 953,
      );
      final placeholderTeacherId = await db.createUser(
        username: 'remote_teacher_9102',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 9102,
      );
      final courseVersionId = await db.createCourseVersion(
        teacherId: placeholderTeacherId,
        subject: 'Statistics',
        granularity: 1,
        textbookText: '',
        sourcePath: r'C:\courses\statistics',
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: 8102,
      );
      await db.assignStudent(
        studentId: studentId,
        courseVersionId: courseVersionId,
      );

      final student = await db.getUserById(studentId);
      expect(student, isNotNull);

      final secureStorage = _TestSecureStorageService();
      final api = _TestMarketplaceApiService(
        secureStorage: secureStorage,
        enrollments: <EnrollmentSummary>[
          EnrollmentSummary(
            enrollmentId: 12,
            courseId: 8102,
            teacherId: 9102,
            status: 'approved',
            assignedAt: '2026-02-28T00:00:00Z',
            courseSubject: 'Statistics',
            teacherName: 'dennis',
            latestBundleVersionId: null,
          ),
        ],
      );
      final service = EnrollmentSyncService(
        db: db,
        secureStorage: secureStorage,
        courseService: CourseService(db),
        marketplaceApi: api,
        promptRepository: PromptRepository(db: db),
      );

      await service.syncIfReady(currentUser: student!);

      final localTeacher = await db.findUserByRemoteId(9102);
      expect(localTeacher, isNotNull);
      expect(localTeacher!.id, equals(placeholderTeacherId));
      expect(localTeacher.username, equals('dennis'));
    },
  );

  test(
    'student legacy cleanup keeps remote-linked assigned course during throttled relogin sync',
    () async {
      final studentId = await db.createUser(
        username: 'student_throttle_keep',
        pinHash: 'hash',
        role: 'student',
        remoteUserId: 952,
      );
      final corruptedCourseId = await db.createCourseVersion(
        teacherId: studentId,
        subject: 'History',
        granularity: 1,
        textbookText: '',
        sourcePath: r'C:\courses\history',
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: corruptedCourseId,
        remoteCourseId: 8201,
      );
      await db.assignStudent(
        studentId: studentId,
        courseVersionId: corruptedCourseId,
      );
      await db.upsertProgress(
        studentId: studentId,
        courseVersionId: corruptedCourseId,
        kpKey: '1.1',
        lit: true,
      );

      final student = await db.getUserById(studentId);
      expect(student, isNotNull);

      final secureStorage = _TestSecureStorageService();
      await secureStorage.writeSyncRunAt(
        remoteUserId: 952,
        domain: 'enrollment_sync_deletions',
        runAt: DateTime.now().toUtc(),
      );
      await secureStorage.writeSyncRunAt(
        remoteUserId: 952,
        domain: 'enrollment_sync_student',
        runAt: DateTime.now().toUtc(),
      );
      final api = _TestMarketplaceApiService(
        secureStorage: secureStorage,
        enrollments: const <EnrollmentSummary>[],
      );
      final service = EnrollmentSyncService(
        db: db,
        secureStorage: secureStorage,
        courseService: CourseService(db),
        marketplaceApi: api,
        promptRepository: PromptRepository(db: db),
      );

      await service.syncIfReady(currentUser: student!);

      final assigned = await db.getAssignedCoursesForStudent(studentId);
      expect(assigned.length, equals(1));
      expect(assigned.first.id, equals(corruptedCourseId));
      final progress = await db.getProgress(
        studentId: studentId,
        courseVersionId: corruptedCourseId,
        kpKey: '1.1',
      );
      expect(progress, isNotNull);
      expect(progress!.lit, isTrue);
    },
  );

  test(
    'student login sync replays deletion events and advances cursor',
    () async {
      final teacherId = await db.createUser(
        username: 'teacher_c',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 811,
      );
      final studentId = await db.createUser(
        username: 'student_c',
        pinHash: 'hash',
        role: 'student',
        teacherId: teacherId,
        remoteUserId: 911,
      );
      final courseId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'Chemistry',
        granularity: 1,
        textbookText: '',
        sourcePath: r'C:\courses\chemistry',
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseId,
        remoteCourseId: 6001,
      );
      await db.assignStudent(
        studentId: studentId,
        courseVersionId: courseId,
      );
      await db.upsertProgress(
        studentId: studentId,
        courseVersionId: courseId,
        kpKey: '1.1',
        lit: true,
      );

      final student = await db.getUserById(studentId);
      expect(student, isNotNull);

      final secureStorage = _TestSecureStorageService(
        deletionCursor: 3,
      );
      final api = _TestMarketplaceApiService(
        secureStorage: secureStorage,
        enrollments: const <EnrollmentSummary>[],
        deletionEventsProvider: (sinceId) {
          expect(sinceId, equals(3));
          return <EnrollmentDeletionEvent>[
            EnrollmentDeletionEvent(
              eventId: 5,
              studentId: 911,
              teacherUserId: 811,
              courseId: 6001,
              reason: 'quit_approved',
              createdAt: '2026-02-27T00:00:00Z',
            ),
          ];
        },
      );
      final service = EnrollmentSyncService(
        db: db,
        secureStorage: secureStorage,
        courseService: CourseService(db),
        marketplaceApi: api,
        promptRepository: PromptRepository(db: db),
      );

      await service.syncIfReady(currentUser: student!);

      final assigned = await db.getAssignedCoursesForStudent(studentId);
      expect(assigned, isEmpty);
      final removedCourse = await db.getCourseVersionById(courseId);
      expect(removedCourse, isNull);
      final movedProgress = await db.getProgress(
        studentId: studentId,
        courseVersionId: courseId,
        kpKey: '1.1',
      );
      expect(movedProgress, isNull);
      expect(await secureStorage.readEnrollmentDeletionCursor(911), equals(5));
      expect(api.lastDeletionSinceId, equals(3));
    },
  );

  test(
    'teacher login sync replays deletion events but keeps teacher course definition',
    () async {
      final teacherId = await db.createUser(
        username: 'teacher_d',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 812,
      );
      final studentAId = await db.createUser(
        username: 'student_d1',
        pinHash: 'hash',
        role: 'student',
        teacherId: teacherId,
        remoteUserId: 912,
      );
      final studentBId = await db.createUser(
        username: 'student_d2',
        pinHash: 'hash',
        role: 'student',
        teacherId: teacherId,
        remoteUserId: 913,
      );
      final courseId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'Physics',
        granularity: 1,
        textbookText: '',
        sourcePath: r'C:\courses\physics',
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseId,
        remoteCourseId: 7001,
      );
      await db.assignStudent(
        studentId: studentAId,
        courseVersionId: courseId,
      );
      await db.assignStudent(
        studentId: studentBId,
        courseVersionId: courseId,
      );
      await db.upsertProgress(
        studentId: studentAId,
        courseVersionId: courseId,
        kpKey: '1.1',
        lit: true,
      );
      await db.upsertProgress(
        studentId: studentBId,
        courseVersionId: courseId,
        kpKey: '1.1',
        lit: true,
      );

      final teacher = await db.getUserById(teacherId);
      expect(teacher, isNotNull);

      final secureStorage = _TestSecureStorageService();
      final api = _TestMarketplaceApiService(
        secureStorage: secureStorage,
        teacherCourses: <TeacherCourseSummary>[
          TeacherCourseSummary(
            courseId: 7001,
            subject: 'Physics',
            grade: '',
            description: '',
            visibility: 'private',
            publishedAt: '',
            latestBundleVersionId: null,
            status: 'active',
          ),
        ],
        deletionEvents: <EnrollmentDeletionEvent>[
          EnrollmentDeletionEvent(
            eventId: 9,
            studentId: 912,
            teacherUserId: 812,
            courseId: 7001,
            reason: 'quit_approved',
            createdAt: '2026-02-27T00:00:00Z',
          ),
        ],
      );
      final service = EnrollmentSyncService(
        db: db,
        secureStorage: secureStorage,
        courseService: CourseService(db),
        marketplaceApi: api,
        promptRepository: PromptRepository(db: db),
      );

      await service.syncIfReady(currentUser: teacher!);

      final teacherCourse = await db.getCourseVersionById(courseId);
      expect(teacherCourse, isNotNull);

      final studentACourses = await db.getAssignedCoursesForStudent(studentAId);
      expect(studentACourses, isEmpty);
      final studentAProgress = await db.getProgress(
        studentId: studentAId,
        courseVersionId: courseId,
        kpKey: '1.1',
      );
      expect(studentAProgress, isNull);

      final studentBCourses = await db.getAssignedCoursesForStudent(studentBId);
      expect(studentBCourses.length, equals(1));
      expect(studentBCourses.first.id, equals(courseId));
      final studentBProgress = await db.getProgress(
        studentId: studentBId,
        courseVersionId: courseId,
        kpKey: '1.1',
      );
      expect(studentBProgress, isNotNull);
      expect(studentBProgress!.lit, isTrue);

      expect(await secureStorage.readEnrollmentDeletionCursor(812), equals(9));
    },
  );

  test('student sync throttles repeated runs within 60 seconds', () async {
    final teacherId = await db.createUser(
      username: 'teacher_e',
      pinHash: 'hash',
      role: 'teacher',
      remoteUserId: 820,
    );
    final studentId = await db.createUser(
      username: 'student_e',
      pinHash: 'hash',
      role: 'student',
      teacherId: teacherId,
      remoteUserId: 920,
    );
    final student = await db.getUserById(studentId);
    expect(student, isNotNull);

    final secureStorage = _TestSecureStorageService();
    final api = _TestMarketplaceApiService(
      secureStorage: secureStorage,
      enrollments: const <EnrollmentSummary>[],
      enrollmentsNotModified: true,
      enrollmentsEtag: 'student-enrollments-etag',
    );
    final service = EnrollmentSyncService(
      db: db,
      secureStorage: secureStorage,
      courseService: CourseService(db),
      marketplaceApi: api,
      promptRepository: PromptRepository(db: db),
    );

    await service.syncIfReady(currentUser: student!);
    await service.syncIfReady(currentUser: student);

    expect(api.listEnrollmentsDeltaCalls, equals(1));
  });

  test(
    'student sync timestamps are category-scoped and still run deletion replay',
    () async {
      final teacherId = await db.createUser(
        username: 'teacher_g',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 840,
      );
      final studentId = await db.createUser(
        username: 'student_g',
        pinHash: 'hash',
        role: 'student',
        teacherId: teacherId,
        remoteUserId: 940,
      );
      final student = await db.getUserById(studentId);
      expect(student, isNotNull);

      final secureStorage = _TestSecureStorageService();
      await secureStorage.writeSyncRunAt(
        remoteUserId: 940,
        domain: 'enrollment_sync_student',
        runAt: DateTime.now().toUtc(),
      );
      final api = _TestMarketplaceApiService(
        secureStorage: secureStorage,
        enrollments: const <EnrollmentSummary>[],
        enrollmentsNotModified: true,
      );
      final service = EnrollmentSyncService(
        db: db,
        secureStorage: secureStorage,
        courseService: CourseService(db),
        marketplaceApi: api,
        promptRepository: PromptRepository(db: db),
      );

      await service.syncIfReady(currentUser: student!);

      expect(api.listEnrollmentsDeltaCalls, equals(0));
      expect(api.listDeletionEventsCalls, equals(1));
    },
  );

  test('teacher sync uses cached ETag for delta list calls', () async {
    final teacherId = await db.createUser(
      username: 'teacher_f',
      pinHash: 'hash',
      role: 'teacher',
      remoteUserId: 830,
    );
    final teacher = await db.getUserById(teacherId);
    expect(teacher, isNotNull);

    final secureStorage = _TestSecureStorageService();
    await secureStorage.writeSyncListEtag(
      remoteUserId: 830,
      domain: 'enrollment_sync_teacher',
      scopeKey: 'teacher_courses',
      etag: 'cached-teacher-etag',
    );
    final api = _TestMarketplaceApiService(
      secureStorage: secureStorage,
      teacherCoursesNotModified: true,
      teacherCoursesEtag: 'cached-teacher-etag',
    );
    final service = EnrollmentSyncService(
      db: db,
      secureStorage: secureStorage,
      courseService: CourseService(db),
      marketplaceApi: api,
      promptRepository: PromptRepository(db: db),
    );

    await service.syncIfReady(currentUser: teacher!);

    expect(api.listTeacherCoursesDeltaCalls, equals(1));
    expect(api.lastTeacherCoursesIfNoneMatch, equals('cached-teacher-etag'));
    final runAt = await secureStorage.readSyncRunAt(
      remoteUserId: 830,
      domain: 'enrollment_sync_teacher',
    );
    expect(runAt, isNotNull);
  });
}
