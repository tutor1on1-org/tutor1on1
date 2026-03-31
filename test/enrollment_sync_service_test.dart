import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:tutor1on1/db/app_database.dart';
import 'package:tutor1on1/llm/prompt_repository.dart';
import 'package:tutor1on1/security/hash_utils.dart';
import 'package:tutor1on1/services/course_artifact_service.dart';
import 'package:tutor1on1/services/course_bundle_service.dart';
import 'package:tutor1on1/services/course_service.dart';
import 'package:tutor1on1/services/enrollment_sync_service.dart';
import 'package:tutor1on1/services/marketplace_api_service.dart';
import 'package:tutor1on1/services/prompt_bundle_compat.dart';
import 'package:tutor1on1/services/secure_storage_service.dart' as storage;

class _TestSecureStorageService extends storage.SecureStorageService {
  _TestSecureStorageService({
    String? accessToken,
    int? deletionCursor,
  })  : _accessToken = accessToken,
        _deletionCursor = deletionCursor;

  final String? _accessToken;
  int? _deletionCursor;
  final Map<String, int> _installedVersionByKey = <String, int>{};
  final Map<String, String> _localState2ByDomain = <String, String>{};
  final Map<String, String> _etagByKey = <String, String>{};
  final Map<String, DateTime> _runAtByDomain = <String, DateTime>{};
  final Map<String, storage.SyncItemState> _syncItemStateByKey =
      <String, storage.SyncItemState>{};
  int writeSyncItemStateCalls = 0;

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
  Future<String?> readLocalSyncState2({
    required int remoteUserId,
    required String domain,
  }) async {
    return _localState2ByDomain['$remoteUserId:$domain'];
  }

  @override
  Future<void> writeLocalSyncState2({
    required int remoteUserId,
    required String domain,
    required String state2,
  }) async {
    _localState2ByDomain['$remoteUserId:$domain'] = state2.trim();
  }

  @override
  Future<void> deleteLocalSyncState2({
    required int remoteUserId,
    required String domain,
  }) async {
    _localState2ByDomain.remove('$remoteUserId:$domain');
  }

  @override
  Future<void> clearAllLocalSyncState2() async {
    _localState2ByDomain.clear();
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
    writeSyncItemStateCalls++;
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
    List<TeacherCourseSummary> Function(int listCallCount)?
        teacherCoursesProvider,
    Map<int, LatestCourseBundleInfo>? latestCourseBundleInfoByCourseId,
    this.latestCourseBundleInfoNotFound = false,
    Map<int, List<TeacherBundleVersionSummary>>?
        teacherBundleVersionsByCourseId,
    Map<int, File>? bundleFilesByVersionId,
    List<EnrollmentDeletionEvent> Function(int? sinceId)?
        deletionEventsProvider,
    this.enrollmentsNotModified = false,
    this.enrollmentsEtag = 'enrollment-etag',
    this.enrollmentsState2,
    this.teacherCoursesState2,
  })  : _enrollments = enrollments ?? const <EnrollmentSummary>[],
        _deletionEvents = deletionEvents ?? const <EnrollmentDeletionEvent>[],
        _teacherCourses = teacherCourses ?? const <TeacherCourseSummary>[],
        _teacherCoursesProvider = teacherCoursesProvider,
        _latestCourseBundleInfoByCourseId = latestCourseBundleInfoByCourseId ??
            const <int, LatestCourseBundleInfo>{},
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
  final List<TeacherCourseSummary> Function(int listCallCount)?
      _teacherCoursesProvider;
  final Map<int, LatestCourseBundleInfo> _latestCourseBundleInfoByCourseId;
  final bool latestCourseBundleInfoNotFound;
  final Map<int, List<TeacherBundleVersionSummary>>
      _teacherBundleVersionsByCourseId;
  final Map<int, File> _bundleFilesByVersionId;
  final List<EnrollmentDeletionEvent> Function(int? sinceId)?
      _deletionEventsProvider;
  final bool enrollmentsNotModified;
  final String? enrollmentsEtag;
  final String? enrollmentsState2;
  final String? teacherCoursesState2;
  final List<_UploadedBundleRecord> uploadedBundles = <_UploadedBundleRecord>[];
  int downloadBundleCalls = 0;
  int? lastDeletionSinceId;
  String? lastEnrollmentsIfNoneMatch;
  String? lastTeacherCoursesIfNoneMatch;
  int listEnrollmentsCalls = 0;
  int listEnrollmentsDeltaCalls = 0;
  int getEnrollmentsState2Calls = 0;
  int listDeletionEventsCalls = 0;
  int listTeacherCoursesDeltaCalls = 0;
  int listTeacherCoursesCalls = 0;
  int getTeacherCoursesState2Calls = 0;
  int listTeacherBundleVersionsCalls = 0;
  int latestCourseBundleInfoCalls = 0;

  @override
  Future<List<EnrollmentSummary>> listEnrollments() async {
    listEnrollmentsCalls++;
    return _enrollments;
  }

  @override
  Future<String> getEnrollmentsSyncState2() async {
    getEnrollmentsState2Calls++;
    return enrollmentsState2 ?? _buildStudentRemoteState2(_enrollments);
  }

  @override
  Future<MarketplaceListResult<EnrollmentSummary>> listEnrollmentsDelta({
    String? ifNoneMatch,
  }) async {
    listEnrollmentsDeltaCalls++;
    lastEnrollmentsIfNoneMatch = ifNoneMatch;
    final notModified = enrollmentsNotModified &&
        (ifNoneMatch ?? '').trim().isNotEmpty &&
        (ifNoneMatch ?? '').trim() == (enrollmentsEtag ?? '').trim();
    return MarketplaceListResult<EnrollmentSummary>(
      items: notModified ? const <EnrollmentSummary>[] : _enrollments,
      etag: enrollmentsEtag,
      notModified: notModified,
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
    final provider = _teacherCoursesProvider;
    if (provider != null) {
      return provider(listTeacherCoursesCalls);
    }
    return _teacherCourses;
  }

  @override
  Future<String> getTeacherCoursesSyncState2() async {
    getTeacherCoursesState2Calls++;
    return teacherCoursesState2 ?? _buildTeacherRemoteState2(_teacherCourses);
  }

  @override
  Future<MarketplaceListResult<TeacherCourseSummary>> listTeacherCoursesDelta({
    String? ifNoneMatch,
  }) async {
    listTeacherCoursesDeltaCalls++;
    lastTeacherCoursesIfNoneMatch = ifNoneMatch;
    return MarketplaceListResult<TeacherCourseSummary>(
      items: _teacherCourses,
      etag: 'teacher-courses-etag',
      notModified: false,
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
  Future<LatestCourseBundleInfo> getLatestCourseBundleInfo(int courseId) async {
    latestCourseBundleInfoCalls++;
    if (latestCourseBundleInfoNotFound) {
      throw MarketplaceApiException(
        'Cannot GET /api/bundles/latest-info',
        statusCode: 404,
      );
    }
    final info = _latestCourseBundleInfoByCourseId[courseId];
    if (info == null) {
      throw StateError('Missing latest bundle info for course $courseId.');
    }
    return info;
  }

  @override
  Future<File> downloadBundleToFile({
    required int bundleVersionId,
    required String targetPath,
  }) async {
    downloadBundleCalls++;
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

String _buildStudentRemoteState2(List<EnrollmentSummary> enrollments) {
  final fingerprints = enrollments
      .map(
        (item) => [
          'student_course',
          '${item.courseId}',
          '${item.teacherId}',
          item.teacherName.trim(),
          item.courseSubject.trim(),
          '${item.latestBundleVersionId ?? 0}',
          item.latestBundleHash.trim(),
        ].join('|'),
      )
      .toList()
    ..sort();
  return sha256Hex(fingerprints.join('\n'));
}

String _buildTeacherRemoteState2(List<TeacherCourseSummary> courses) {
  final fingerprints = courses
      .map(
        (item) => [
          'teacher_course',
          item.subject.trim().toLowerCase(),
          item.subject.trim(),
          '${item.latestBundleVersionId ?? 0}',
          item.latestBundleHash.trim(),
        ].join('|'),
      )
      .toList()
    ..sort();
  return sha256Hex(fingerprints.join('\n'));
}

class _CountingCourseArtifactService extends CourseArtifactService {
  _CountingCourseArtifactService();

  int rebuildCourseArtifactsCalls = 0;
  int readCourseArtifactsCalls = 0;
  int prepareUploadBundleCalls = 0;
  int computeUploadHashCalls = 0;

  void resetCounters() {
    rebuildCourseArtifactsCalls = 0;
    readCourseArtifactsCalls = 0;
    prepareUploadBundleCalls = 0;
    computeUploadHashCalls = 0;
  }

  @override
  Future<CourseArtifactManifest> rebuildCourseArtifacts({
    required int courseVersionId,
    required String folderPath,
  }) {
    rebuildCourseArtifactsCalls++;
    return super.rebuildCourseArtifacts(
      courseVersionId: courseVersionId,
      folderPath: folderPath,
    );
  }

  @override
  Future<CourseArtifactManifest?> readCourseArtifacts(int courseVersionId) {
    readCourseArtifactsCalls++;
    return super.readCourseArtifacts(courseVersionId);
  }

  @override
  Future<PreparedCourseUploadBundle> prepareUploadBundle({
    required int courseVersionId,
    required Map<String, dynamic>? promptMetadata,
    required String bundleLabel,
  }) {
    prepareUploadBundleCalls++;
    return super.prepareUploadBundle(
      courseVersionId: courseVersionId,
      promptMetadata: promptMetadata,
      bundleLabel: bundleLabel,
    );
  }

  @override
  Future<String> computeUploadHash({
    required int courseVersionId,
    required Map<String, dynamic>? promptMetadata,
  }) {
    computeUploadHashCalls++;
    return super.computeUploadHash(
      courseVersionId: courseVersionId,
      promptMetadata: promptMetadata,
    );
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
    'teacher sync reclaims remote-linked courses from stale placeholder teacher',
    () async {
      final teacherId = await db.createUser(
        username: 'dennis',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 9,
      );
      final placeholderTeacherId = await db.createUser(
        username: 'dennis_1',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 5,
      );
      final studentId = await db.createUser(
        username: 'albert',
        pinHash: 'hash',
        role: 'student',
        teacherId: placeholderTeacherId,
        remoteUserId: 11,
      );
      final localDir = await _createCourseFolder(
        label: 'teacher_reclaim_placeholder',
        rootTitle: 'MATH',
      );
      tempPaths.add(localDir.path);
      final courseVersionId = await db.createCourseVersion(
        teacherId: placeholderTeacherId,
        subject: 'MATH',
        granularity: 1,
        textbookText: '1 MATH',
        sourcePath: localDir.path,
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: 9105,
      );
      final teacher = await db.getUserById(teacherId);
      expect(teacher, isNotNull);

      final secureStorage = _TestSecureStorageService();
      final api = _TestMarketplaceApiService(
        secureStorage: secureStorage,
        teacherCourses: <TeacherCourseSummary>[
          TeacherCourseSummary(
            courseId: 9105,
            subject: 'MATH',
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
        courseArtifactService: CourseArtifactService(),
      );

      await service.syncIfReady(currentUser: teacher!);

      final repairedCourse = await db.getCourseVersionById(courseVersionId);
      expect(repairedCourse, isNotNull);
      expect(repairedCourse!.teacherId, equals(teacherId));

      final repairedStudent = await db.getUserById(studentId);
      expect(repairedStudent, isNotNull);
      expect(repairedStudent!.teacherId, equals(teacherId));

      final staleTeacher = await db.getUserById(placeholderTeacherId);
      expect(staleTeacher, isNull);
    },
  );

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
      final remoteHash =
          await CourseBundleService().computeBundleSemanticHash(remoteBundle);

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
            latestBundleHash: '',
            status: 'active',
          ),
        ],
        latestCourseBundleInfoByCourseId: <int, LatestCourseBundleInfo>{
          91: LatestCourseBundleInfo(
            courseId: 91,
            bundleId: 9,
            bundleVersionId: 3,
            version: 3,
            hash: remoteHash,
            fileMissing: false,
          ),
        },
        bundleFilesByVersionId: <int, File>{3: remoteBundle},
      );
      final service = EnrollmentSyncService(
        db: db,
        secureStorage: secureStorage,
        courseService: CourseService(db),
        marketplaceApi: api,
        promptRepository: PromptRepository(db: db),
        courseArtifactService: CourseArtifactService(),
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
      expect(api.latestCourseBundleInfoCalls, equals(1));
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
          'schema': kCurrentPromptBundleSchema,
          'remote_course_id': 9101,
          'teacher_username': 'teacher_pull_remote',
          'prompt_templates': <Map<String, dynamic>>[
            <String, dynamic>{
              'prompt_name': 'learn',
              'scope': 'course',
              'content':
                  '{{kp_description}}\n{{student_input}}\n{{lesson_content}}',
            },
            <String, dynamic>{
              'prompt_name': 'review',
              'scope': 'student_course',
              'content':
                  '{{kp_description}}\n{{student_input}}\n{{active_review_question_json}}\n{{target_difficulty}}\n{{presented_questions}}\n{{error_book_summary}}',
              'student_remote_user_id': 1702,
              'student_username': 'student_pull_remote',
            },
          ],
          'student_prompt_profiles': <Map<String, dynamic>>[
            <String, dynamic>{
              'scope': 'student_course',
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
            latestBundleHash: remoteHash,
            status: 'active',
          ),
        ],
        bundleFilesByVersionId: <int, File>{301: remoteBundle},
      );
      final service = EnrollmentSyncService(
        db: db,
        secureStorage: secureStorage,
        courseService: CourseService(db),
        marketplaceApi: api,
        promptRepository: PromptRepository(db: db),
        courseArtifactService: CourseArtifactService(),
      );

      final stats = await service.syncIfReady(currentUser: teacher!);

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
        promptName: 'learn',
        courseKey: updatedCourse.sourcePath,
        studentId: null,
      );
      expect(activeCoursePrompt, isNotNull);
      expect(
        activeCoursePrompt!.content,
        equals('{{kp_description}}\n{{student_input}}\n{{lesson_content}}'),
      );

      final activeStudentPrompt = await db.getActivePromptTemplate(
        teacherId: teacherId,
        promptName: 'review',
        courseKey: updatedCourse.sourcePath,
        studentId: studentId,
      );
      expect(activeStudentPrompt, isNotNull);
      expect(
        activeStudentPrompt!.content,
        equals(
          '{{kp_description}}\n{{student_input}}\n{{active_review_question_json}}\n{{target_difficulty}}\n{{presented_questions}}\n{{error_book_summary}}',
        ),
      );

      final studentProfile = await db.getStudentPromptProfile(
        teacherId: teacherId,
        courseKey: updatedCourse.sourcePath,
        studentId: studentId,
      );
      expect(studentProfile, isNotNull);
      expect(studentProfile!.preferredTone, equals('calm'));
      expect(api.listTeacherBundleVersionsCalls, equals(0));
      expect(stats.downloadedCount, equals(1));
      expect(stats.downloadedBytes, greaterThan(0));
    },
  );

  test(
    'teacher second sync does not raise false conflict after pulling legacy prompt bundle',
    () async {
      final teacherId = await db.createUser(
        username: 'teacher_legacy_pull',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 1751,
      );
      final localDir = await _createCourseFolder(
        label: 'local_legacy_pull',
        rootTitle: 'Local Topic',
      );
      tempPaths.add(localDir.path);
      final courseVersionId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'Math',
        granularity: 1,
        textbookText: '1 Local Topic',
        sourcePath: localDir.path,
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: 9201,
      );
      final teacher = await db.getUserById(teacherId);
      expect(teacher, isNotNull);

      final remoteTempDir = await Directory.systemTemp.createTemp(
        'legacy_teacher_sync_bundle_',
      );
      tempPaths.add(remoteTempDir.path);
      final archive = Archive();
      final contentsBytes = Uint8List.fromList(
        utf8.encode('1 Remote Topic\n1.1 Remote Subtopic\n'),
      );
      archive.addFile(
        ArchiveFile('contents.txt', contentsBytes.length, contentsBytes),
      );
      final lecture1 = Uint8List.fromList(utf8.encode('Remote lecture 1'));
      final lecture2 = Uint8List.fromList(utf8.encode('Remote lecture 1.1'));
      archive.addFile(
        ArchiveFile('1_lecture.txt', lecture1.length, lecture1),
      );
      archive.addFile(
        ArchiveFile('1.1_lecture.txt', lecture2.length, lecture2),
      );
      final metadataBytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, dynamic>{
            'schema': kLegacyPromptBundleSchema,
            'remote_course_id': 9201,
            'teacher_username': 'teacher_legacy_pull',
            'prompt_templates': <Map<String, dynamic>>[
              <String, dynamic>{
                'prompt_name': 'learn',
                'scope': 'course',
                'content':
                    '{{kp_description}}\n{{student_input}}\n{{lesson_content}}',
              },
            ],
            'student_prompt_profiles': const <Map<String, dynamic>>[],
            'student_pass_configs': const <Map<String, dynamic>>[],
          }),
        ),
      );
      archive.addFile(
        ArchiveFile(
          kLegacyPromptMetadataEntryPath,
          metadataBytes.length,
          metadataBytes,
        ),
      );
      final zipBytes = ZipEncoder().encode(archive);
      expect(zipBytes, isNotNull);
      final remoteBundle =
          File(p.join(remoteTempDir.path, 'legacy_remote.zip'));
      await remoteBundle.writeAsBytes(zipBytes!, flush: true);
      tempFiles.add(remoteBundle.path);

      final bundleService = CourseBundleService();
      final remoteHash =
          await bundleService.computeBundleSemanticHash(remoteBundle);

      final secureStorage = _TestSecureStorageService();
      final api = _TestMarketplaceApiService(
        secureStorage: secureStorage,
        teacherCourses: <TeacherCourseSummary>[
          TeacherCourseSummary(
            courseId: 9201,
            subject: 'Math',
            grade: '',
            description: '',
            visibility: 'private',
            publishedAt: '',
            latestBundleVersionId: 401,
            latestBundleHash: remoteHash,
            status: 'active',
          ),
        ],
        bundleFilesByVersionId: <int, File>{401: remoteBundle},
      );
      final service = EnrollmentSyncService(
        db: db,
        secureStorage: secureStorage,
        courseService: CourseService(db),
        marketplaceApi: api,
        promptRepository: PromptRepository(db: db),
        courseArtifactService: CourseArtifactService(),
      );

      final firstStats = await service.syncIfReady(currentUser: teacher!);
      final secondStats = await service.syncIfReady(currentUser: teacher);

      expect(firstStats.downloadedCount, equals(1));
      expect(secondStats.downloadedCount, equals(0));
      expect(api.uploadedBundles, isEmpty);
      expect(
        await secureStorage.readInstalledCourseBundleVersion(
          remoteUserId: 1751,
          remoteCourseId: 9201,
        ),
        equals(401),
      );
    },
  );

  test(
    'teacher unchanged sync skips local bundle hash and bundle preparation work',
    () async {
      final teacherId = await db.createUser(
        username: 'teacher_skip_hash',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 1761,
      );
      final localDir = await _createCourseFolder(
        label: 'teacher_skip_hash_local',
        rootTitle: 'Stable Topic',
      );
      tempPaths.add(localDir.path);
      final courseVersionId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'Stable Course',
        granularity: 1,
        textbookText: '1 Stable Topic',
        sourcePath: localDir.path,
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: 9301,
      );
      final teacher = await db.getUserById(teacherId);
      expect(teacher, isNotNull);

      final bundleService = CourseBundleService();
      final remoteBundle = await bundleService.createBundleFromFolder(
        localDir.path,
      );
      tempFiles.add(remoteBundle.path);
      final remoteHash =
          await bundleService.computeBundleSemanticHash(remoteBundle);

      final artifactService = _CountingCourseArtifactService();
      await artifactService.rebuildCourseArtifacts(
        courseVersionId: courseVersionId,
        folderPath: localDir.path,
      );
      artifactService.resetCounters();

      final secureStorage = _TestSecureStorageService();
      final syncedAt = DateTime.now().toUtc();
      await secureStorage.writeInstalledCourseBundleVersion(
        remoteUserId: 1761,
        remoteCourseId: 9301,
        versionId: 501,
      );
      await secureStorage.writeSyncItemState(
        remoteUserId: 1761,
        domain: 'enrollment_sync_teacher_upload',
        scopeKey: 'course:9301',
        contentHash: remoteHash,
        lastChangedAt: syncedAt,
        lastSyncedAt: syncedAt,
      );
      await secureStorage.writeSyncRunAt(
        remoteUserId: 1761,
        domain: 'enrollment_sync_teacher',
        runAt: syncedAt.subtract(const Duration(minutes: 5)),
      );
      final api = _TestMarketplaceApiService(
        secureStorage: secureStorage,
        teacherCourses: <TeacherCourseSummary>[
          TeacherCourseSummary(
            courseId: 9301,
            subject: 'Stable Course',
            grade: '',
            description: '',
            visibility: 'private',
            publishedAt: '',
            latestBundleVersionId: 501,
            latestBundleHash: remoteHash,
            status: 'active',
          ),
        ],
      );
      final service = EnrollmentSyncService(
        db: db,
        secureStorage: secureStorage,
        courseService: CourseService(
          db,
          courseArtifactService: artifactService,
        ),
        marketplaceApi: api,
        promptRepository: PromptRepository(db: db),
        courseArtifactService: artifactService,
      );

      final stats = await service.syncIfReady(currentUser: teacher!);

      expect(stats.downloadedCount, equals(0));
      expect(stats.uploadedCount, equals(0));
      expect(api.downloadBundleCalls, equals(0));
      expect(api.uploadedBundles, isEmpty);
      expect(artifactService.computeUploadHashCalls, equals(0));
      expect(artifactService.prepareUploadBundleCalls, equals(0));
    },
  );

  test(
    'teacher pulled bundle survives forced local hash recompute on fresh machine',
    () async {
      final teacherId = await db.createUser(
        username: 'teacher_round_trip',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 1762,
      );
      final teacher = await db.getUserById(teacherId);
      expect(teacher, isNotNull);

      final remoteDir = await _createCourseFolder(
        label: 'teacher_round_trip_remote',
        rootTitle: 'Round Trip Topic',
      );
      tempPaths.add(remoteDir.path);
      final remoteBundle = await CourseBundleService().createBundleFromFolder(
        remoteDir.path,
        promptMetadata: <String, dynamic>{
          'schema': kCurrentPromptBundleSchema,
          'remote_course_id': 9302,
          'teacher_username': 'teacher_round_trip',
          'prompt_templates': <Map<String, dynamic>>[
            <String, dynamic>{
              'prompt_name': 'learn',
              'scope': 'teacher',
              'content':
                  '{{kp_description}}\n{{student_input}}\n{{lesson_content}}',
              'student_remote_user_id': null,
              'student_username': null,
              'created_at': '2026-03-01T00:00:00Z',
            },
            <String, dynamic>{
              'prompt_name': 'review',
              'scope': 'student_global',
              'content':
                  '{{kp_description}}\n{{student_input}}\n{{active_review_question_json}}\n{{target_difficulty}}\n{{presented_questions}}\n{{error_book_summary}}',
              'student_remote_user_id': 2762,
              'student_username': 'albert_round_trip',
              'created_at': '2026-03-03T00:00:00Z',
            },
            <String, dynamic>{
              'prompt_name': 'learn',
              'scope': 'student_global',
              'content':
                  '{{kp_description}}\n{{student_input}}\n{{lesson_content}}',
              'student_remote_user_id': 2762,
              'student_username': 'albert_round_trip',
              'created_at': '2026-03-02T00:00:00Z',
            },
            <String, dynamic>{
              'prompt_name': 'review',
              'scope': 'course',
              'content':
                  '{{kp_description}}\n{{student_input}}\n{{active_review_question_json}}\n{{target_difficulty}}\n{{presented_questions}}\n{{error_book_summary}}',
              'student_remote_user_id': null,
              'student_username': null,
              'created_at': '2026-03-04T00:00:00Z',
            },
          ],
          'student_prompt_profiles': <Map<String, dynamic>>[
            <String, dynamic>{
              'scope': 'student_global',
              'student_remote_user_id': 2762,
              'student_username': 'albert_round_trip',
              'grade_level': null,
              'reading_level': null,
              'preferred_language': null,
              'interests': null,
              'preferred_tone': 'steady',
              'preferred_pace': null,
              'preferred_format': null,
              'support_notes': null,
              'created_at': '2026-03-05T00:00:00Z',
              'updated_at': '2026-03-06T00:00:00Z',
            },
          ],
          'student_pass_configs': <Map<String, dynamic>>[
            <String, dynamic>{
              'student_remote_user_id': 2762,
              'student_username': 'albert_round_trip',
              'easy_weight': 0.4,
              'medium_weight': 0.7,
              'hard_weight': 1.1,
              'pass_threshold': 1.3,
              'created_at': '2026-03-07T00:00:00Z',
              'updated_at': '2026-03-08T00:00:00Z',
            },
          ],
        },
      );
      tempFiles.add(remoteBundle.path);
      final remoteHash =
          await CourseBundleService().computeBundleSemanticHash(remoteBundle);

      final secureStorage = _TestSecureStorageService();
      final api = _TestMarketplaceApiService(
        secureStorage: secureStorage,
        teacherCourses: <TeacherCourseSummary>[
          TeacherCourseSummary(
            courseId: 9302,
            subject: 'MATH',
            grade: '',
            description: '',
            visibility: 'private',
            publishedAt: '',
            latestBundleVersionId: 502,
            latestBundleHash: remoteHash,
            status: 'active',
          ),
        ],
        bundleFilesByVersionId: <int, File>{502: remoteBundle},
      );
      final artifactService = _CountingCourseArtifactService();
      final service = EnrollmentSyncService(
        db: db,
        secureStorage: secureStorage,
        courseService: CourseService(
          db,
          courseArtifactService: artifactService,
        ),
        marketplaceApi: api,
        promptRepository: PromptRepository(db: db),
        courseArtifactService: artifactService,
      );

      final firstStats = await service.syncIfReady(currentUser: teacher!);

      expect(firstStats.downloadedCount, equals(1));
      final localStudent = await db.findUserByRemoteId(2762);
      expect(localStudent, isNotNull);
      expect(localStudent!.role, equals('student'));
      final assignedCourses = await db.getAssignedCoursesForStudent(
        localStudent.id,
      );
      expect(assignedCourses.map((course) => course.subject), contains('MATH'));

      final staleAt = DateTime.utc(2026, 1, 1);
      await secureStorage.writeSyncItemState(
        remoteUserId: 1762,
        domain: 'enrollment_sync_teacher_upload',
        scopeKey: 'course:9302',
        contentHash: remoteHash,
        lastChangedAt: staleAt,
        lastSyncedAt: staleAt,
      );
      await secureStorage.writeSyncRunAt(
        remoteUserId: 1762,
        domain: 'enrollment_sync_teacher',
        runAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      );
      artifactService.resetCounters();

      final secondStats = await service.syncIfReady(currentUser: teacher);

      expect(secondStats.downloadedCount, equals(0));
      expect(secondStats.uploadedCount, equals(0));
      expect(api.downloadBundleCalls, equals(1));
      expect(api.uploadedBundles, isEmpty);
      expect(artifactService.computeUploadHashCalls, equals(0));
      expect(artifactService.prepareUploadBundleCalls, equals(0));
    },
  );

  test(
    'teacher first sync force-redownloads placeholder remote course when latest hash lookup is unavailable',
    () async {
      final teacherId = await db.createUser(
        username: 'dennis_placeholder',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 1901,
      );
      final courseVersionId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'UK_MATH_7-13',
        granularity: 1,
        textbookText: '',
        sourcePath: null,
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: 10,
      );
      final teacher = await db.getUserById(teacherId);
      expect(teacher, isNotNull);

      final remoteDir = await _createCourseFolder(
        label: 'teacher_force_redownload_placeholder',
        rootTitle: 'UK MATH Remote Topic',
      );
      tempPaths.add(remoteDir.path);
      final remoteBundle = await CourseBundleService().createBundleFromFolder(
        remoteDir.path,
      );
      tempFiles.add(remoteBundle.path);
      final remoteHash =
          await CourseBundleService().computeBundleSemanticHash(remoteBundle);

      final secureStorage = _TestSecureStorageService();
      await secureStorage.writeInstalledCourseBundleVersion(
        remoteUserId: 1901,
        remoteCourseId: 10,
        versionId: 32,
      );
      final staleSyncAt = DateTime.utc(2026, 3, 12, 10, 3, 36);
      await secureStorage.writeSyncItemState(
        remoteUserId: 1901,
        domain: 'enrollment_sync_teacher_upload',
        scopeKey: 'course:10',
        contentHash: remoteHash,
        lastChangedAt: staleSyncAt,
        lastSyncedAt: staleSyncAt,
      );
      final api = _TestMarketplaceApiService(
        secureStorage: secureStorage,
        teacherCourses: <TeacherCourseSummary>[
          TeacherCourseSummary(
            courseId: 10,
            subject: 'UK_MATH_7-13',
            grade: '',
            description: '',
            visibility: 'public',
            publishedAt: '',
            latestBundleVersionId: 32,
            latestBundleHash: '',
            status: 'active',
          ),
        ],
        teacherCoursesState2: 'force-mismatch',
        latestCourseBundleInfoNotFound: true,
        bundleFilesByVersionId: <int, File>{32: remoteBundle},
      );
      final service = EnrollmentSyncService(
        db: db,
        secureStorage: secureStorage,
        courseService: CourseService(db),
        marketplaceApi: api,
        promptRepository: PromptRepository(db: db),
        courseArtifactService: CourseArtifactService(),
      );

      final stats = await service.syncIfReady(currentUser: teacher!);

      final repairedCourse = await db.getCourseVersionById(courseVersionId);
      expect(repairedCourse, isNotNull);
      expect(repairedCourse!.sourcePath, isNotNull);
      expect(repairedCourse.sourcePath, isNotEmpty);
      expect(Directory(repairedCourse.sourcePath!).existsSync(), isTrue);
      final nodes = await db.getCourseNodes(courseVersionId);
      expect(nodes, isNotEmpty);
      expect(api.downloadBundleCalls, equals(1));
      expect(api.uploadedBundles, isEmpty);
      expect(stats.downloadedCount, equals(1));
      expect(stats.downloadedBytes, greaterThan(0));
      expect(api.latestCourseBundleInfoCalls, equals(2));
      expect(
        await secureStorage.readInstalledCourseBundleVersion(
          remoteUserId: 1901,
          remoteCourseId: 10,
        ),
        equals(32),
      );
    },
  );

  test('teacher can pull latest server bundle explicitly', () async {
    final teacherId = await db.createUser(
      username: 'teacher_pull_latest',
      pinHash: 'hash',
      role: 'teacher',
      remoteUserId: 1951,
    );
    final localDir = await _createCourseFolder(
      label: 'teacher_pull_latest_local',
      rootTitle: 'Local Topic',
    );
    final remoteDir = await _createCourseFolder(
      label: 'teacher_pull_latest_remote',
      rootTitle: 'Remote Topic',
    );
    tempPaths.add(localDir.path);
    tempPaths.add(remoteDir.path);
    final courseVersionId = await db.createCourseVersion(
      teacherId: teacherId,
      subject: 'MATH',
      granularity: 1,
      textbookText: '1 Local Topic',
      sourcePath: localDir.path,
    );
    await db.upsertCourseRemoteLink(
      courseVersionId: courseVersionId,
      remoteCourseId: 9105,
    );
    final remoteBundle = await CourseBundleService().createBundleFromFolder(
      remoteDir.path,
    );
    tempFiles.add(remoteBundle.path);
    final remoteHash =
        await CourseBundleService().computeBundleSemanticHash(remoteBundle);

    final teacher = await db.getUserById(teacherId);
    expect(teacher, isNotNull);

    final secureStorage = _TestSecureStorageService();
    final api = _TestMarketplaceApiService(
      secureStorage: secureStorage,
      teacherCourses: <TeacherCourseSummary>[
        TeacherCourseSummary(
          courseId: 9105,
          subject: 'MATH',
          grade: '',
          description: '',
          visibility: 'private',
          publishedAt: '',
          latestBundleVersionId: 61,
          latestBundleHash: remoteHash,
          status: 'active',
        ),
      ],
      bundleFilesByVersionId: <int, File>{61: remoteBundle},
    );
    final service = EnrollmentSyncService(
      db: db,
      secureStorage: secureStorage,
      courseService: CourseService(db),
      marketplaceApi: api,
      promptRepository: PromptRepository(db: db),
      courseArtifactService: CourseArtifactService(),
    );

    final localCourse = await db.getCourseVersionById(courseVersionId);
    expect(localCourse, isNotNull);
    final pulled = await service.pullLatestTeacherCourse(
      currentUser: teacher!,
      course: localCourse!,
    );

    expect(pulled.id, equals(courseVersionId));
    final updatedCourse = await db.getCourseVersionById(courseVersionId);
    expect(updatedCourse, isNotNull);
    expect(updatedCourse!.textbookText, contains('Remote Topic'));
    expect(api.downloadBundleCalls, equals(1));
    expect(
      await secureStorage.readInstalledCourseBundleVersion(
        remoteUserId: 1951,
        remoteCourseId: 9105,
      ),
      equals(61),
    );
  });

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
      await db.assignStudent(
        studentId: studentId,
        courseVersionId: courseAId,
      );
      await db.insertPromptTemplate(
        teacherId: teacherId,
        promptName: 'learn',
        content: 'GLOBAL PROMPT',
      );
      await db.insertPromptTemplate(
        teacherId: teacherId,
        promptName: 'learn',
        content: 'STUDENT GLOBAL PROMPT',
        studentId: studentId,
      );
      await db.insertPromptTemplate(
        teacherId: teacherId,
        promptName: 'learn',
        content: 'COURSE PROMPT',
        courseKey: courseADir.path,
      );
      await db.insertPromptTemplate(
        teacherId: teacherId,
        promptName: 'review',
        content: 'STUDENT PROMPT',
        courseKey: courseADir.path,
        studentId: studentId,
      );
      await db.upsertStudentPromptProfile(
        teacherId: teacherId,
        courseKey: null,
        studentId: null,
        preferredFormat: 'steps',
      );
      await db.upsertStudentPromptProfile(
        teacherId: teacherId,
        courseKey: null,
        studentId: studentId,
        preferredTone: 'patient',
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
        courseArtifactService: CourseArtifactService(),
      );

      final stats = await service.syncIfReady(currentUser: teacher!);

      expect(api.getTeacherCoursesState2Calls, equals(1));
      expect(api.listTeacherCoursesCalls, equals(2));
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
        isTrue,
      );
      expect(
        promptTemplates.any((item) => item['scope'] == 'course'),
        isTrue,
      );
      expect(
        promptTemplates.any((item) => item['scope'] == 'student_course'),
        isTrue,
      );
      expect(
        promptTemplates.any((item) => item['scope'] == 'student_global'),
        isTrue,
      );
      final studentProfiles =
          (metadata['student_prompt_profiles'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
      expect(
        studentProfiles.any((item) => item['scope'] == 'teacher'),
        isTrue,
      );
      expect(
        studentProfiles.any((item) => item['scope'] == 'student_course'),
        isTrue,
      );
      expect(
        studentProfiles.any((item) => item['scope'] == 'student_global'),
        isTrue,
      );
      expect(stats.uploadedCount, equals(2));
      expect(stats.uploadedBytes, greaterThan(0));
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
        courseArtifactService: CourseArtifactService(),
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
    'student sync replaces weak remote link with fresh import and migrates data',
    () async {
      final studentId = await db.createUser(
        username: 'student_weak_remote_link',
        pinHash: 'hash',
        role: 'student',
        remoteUserId: 963,
      );
      final localTeacherId = await db.createUser(
        username: 'remote_teacher_weak_link',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 9913,
      );
      final localDir = await _createCourseFolder(
        label: 'student_weak_remote_link_local',
        rootTitle: 'Local Topic',
      );
      final remoteDir = await _createCourseFolder(
        label: 'student_weak_remote_link_remote',
        rootTitle: 'Remote Topic',
      );
      tempPaths.add(localDir.path);
      tempPaths.add(remoteDir.path);
      final remoteBundle = await CourseBundleService().createBundleFromFolder(
        remoteDir.path,
      );
      tempFiles.add(remoteBundle.path);
      final remoteHash =
          await CourseBundleService().computeBundleSemanticHash(remoteBundle);

      final staleCourseId = await db.createCourseVersion(
        teacherId: localTeacherId,
        subject: 'MATH',
        granularity: 1,
        textbookText: '1 Local Topic',
        sourcePath: localDir.path,
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: staleCourseId,
        remoteCourseId: 8107,
      );
      await db.assignStudent(
        studentId: studentId,
        courseVersionId: staleCourseId,
      );
      await db.upsertProgress(
        studentId: studentId,
        courseVersionId: staleCourseId,
        kpKey: '1',
        lit: true,
      );
      final startedAt = DateTime.parse('2026-03-03T08:00:00Z');
      final sessionId = await db.into(db.chatSessions).insert(
            ChatSessionsCompanion.insert(
              studentId: studentId,
              courseVersionId: staleCourseId,
              kpKey: '1',
              title: const Value('Local Session'),
              status: const Value('active'),
              startedAt: Value(startedAt),
            ),
          );
      await db.into(db.chatMessages).insert(
            ChatMessagesCompanion.insert(
              sessionId: sessionId,
              role: 'assistant',
              content: 'LOCAL_MESSAGE',
              createdAt: Value(startedAt),
            ),
          );

      final student = await db.getUserById(studentId);
      expect(student, isNotNull);

      final secureStorage = _TestSecureStorageService();
      final api = _TestMarketplaceApiService(
        secureStorage: secureStorage,
        enrollments: <EnrollmentSummary>[
          EnrollmentSummary(
            enrollmentId: 17,
            courseId: 8107,
            teacherId: 9913,
            status: 'approved',
            assignedAt: '2026-03-03T00:00:00Z',
            courseSubject: 'MATH',
            teacherName: 'remote_teacher_weak_link',
            latestBundleVersionId: 57,
            latestBundleHash: remoteHash,
          ),
        ],
        bundleFilesByVersionId: <int, File>{57: remoteBundle},
      );
      final service = EnrollmentSyncService(
        db: db,
        secureStorage: secureStorage,
        courseService: CourseService(db),
        marketplaceApi: api,
        promptRepository: PromptRepository(db: db),
        courseArtifactService: CourseArtifactService(),
      );

      await service.syncIfReady(currentUser: student!);

      final linkedCourseId = await db.getCourseVersionIdForRemoteCourse(8107);
      expect(linkedCourseId, isNotNull);
      expect(linkedCourseId, isNot(equals(staleCourseId)));

      final assigned = await db.getAssignedCoursesForStudent(studentId);
      expect(assigned.length, equals(1));
      expect(assigned.first.id, equals(linkedCourseId));

      final staleCourse = await db.getCourseVersionById(staleCourseId);
      expect(staleCourse, isNull);

      final importedCourse = await db.getCourseVersionById(linkedCourseId!);
      expect(importedCourse, isNotNull);
      expect(importedCourse!.textbookText, contains('Remote Topic'));

      final movedProgress = await db.getProgress(
        studentId: studentId,
        courseVersionId: linkedCourseId,
        kpKey: '1',
      );
      expect(movedProgress, isNotNull);
      expect(movedProgress!.lit, isTrue);

      final movedSession = await db.getSession(sessionId);
      expect(movedSession, isNotNull);
      expect(movedSession!.courseVersionId, equals(linkedCourseId));
      final movedMessages = await db.getMessagesForSession(sessionId);
      expect(movedMessages, hasLength(1));
      expect(movedMessages.single.content, equals('LOCAL_MESSAGE'));

      expect(api.downloadBundleCalls, equals(1));
      expect(
        await secureStorage.readInstalledCourseBundleVersion(
          remoteUserId: 963,
          remoteCourseId: 8107,
        ),
        equals(57),
      );
    },
  );

  test(
    'student sync reuses cached bundle hash and skips remote download',
    () async {
      final studentId = await db.createUser(
        username: 'student_cached_hash',
        pinHash: 'hash',
        role: 'student',
        remoteUserId: 961,
      );
      final localTeacherId = await db.createUser(
        username: 'remote_teacher_cached',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 9911,
      );
      final localDir = await _createCourseFolder(
        label: 'student_cached_hash_local',
        rootTitle: 'Cached Topic',
      );
      tempPaths.add(localDir.path);
      final remoteBundle = await CourseBundleService().createBundleFromFolder(
        localDir.path,
      );
      tempFiles.add(remoteBundle.path);
      final remoteHash =
          await CourseBundleService().computeBundleSemanticHash(remoteBundle);

      final courseVersionId = await db.createCourseVersion(
        teacherId: localTeacherId,
        subject: 'Cached Course',
        granularity: 1,
        textbookText: '1 Cached Topic',
        sourcePath: localDir.path,
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: 8105,
      );
      await db.assignStudent(
        studentId: studentId,
        courseVersionId: courseVersionId,
      );

      final student = await db.getUserById(studentId);
      expect(student, isNotNull);

      final secureStorage = _TestSecureStorageService();
      await secureStorage.writeInstalledCourseBundleVersion(
        remoteUserId: 961,
        remoteCourseId: 8105,
        versionId: 55,
      );
      final now = DateTime.now().toUtc();
      await secureStorage.writeSyncItemState(
        remoteUserId: 961,
        domain: 'enrollment_sync_student_bundle',
        scopeKey: 'course:8105',
        contentHash: remoteHash,
        lastChangedAt: now,
        lastSyncedAt: now,
      );
      final api = _TestMarketplaceApiService(
        secureStorage: secureStorage,
        enrollments: <EnrollmentSummary>[
          EnrollmentSummary(
            enrollmentId: 15,
            courseId: 8105,
            teacherId: 9911,
            status: 'approved',
            assignedAt: '2026-03-01T00:00:00Z',
            courseSubject: 'Cached Course',
            teacherName: 'remote_teacher_cached',
            latestBundleVersionId: 55,
            latestBundleHash: '',
          ),
        ],
        latestCourseBundleInfoByCourseId: <int, LatestCourseBundleInfo>{
          8105: LatestCourseBundleInfo(
            courseId: 8105,
            bundleId: 81,
            bundleVersionId: 55,
            version: 55,
            hash: remoteHash,
            fileMissing: false,
          ),
        },
      );
      final service = EnrollmentSyncService(
        db: db,
        secureStorage: secureStorage,
        courseService: CourseService(db),
        marketplaceApi: api,
        promptRepository: PromptRepository(db: db),
        courseArtifactService: CourseArtifactService(),
      );

      await service.syncIfReady(currentUser: student!);

      expect(api.downloadBundleCalls, equals(0));
      expect(
        await secureStorage.readInstalledCourseBundleVersion(
          remoteUserId: 961,
          remoteCourseId: 8105,
        ),
        equals(55),
      );
      expect(api.latestCourseBundleInfoCalls, equals(1));
      final assigned = await db.getAssignedCoursesForStudent(studentId);
      expect(assigned.map((course) => course.id), contains(courseVersionId));
    },
  );

  test(
    'student sync tolerates missing latest-info endpoint on older server',
    () async {
      final studentId = await db.createUser(
        username: 'student_legacy_hash_api',
        pinHash: 'hash',
        role: 'student',
        remoteUserId: 962,
      );
      final localTeacherId = await db.createUser(
        username: 'remote_teacher_legacy_hash_api',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 9912,
      );
      final localDir = await _createCourseFolder(
        label: 'student_legacy_hash_api_local',
        rootTitle: 'Legacy Topic',
      );
      tempPaths.add(localDir.path);
      final courseVersionId = await db.createCourseVersion(
        teacherId: localTeacherId,
        subject: 'Legacy Course',
        granularity: 1,
        textbookText: '1 Legacy Topic',
        sourcePath: localDir.path,
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: 8106,
      );
      await db.assignStudent(
        studentId: studentId,
        courseVersionId: courseVersionId,
      );

      final student = await db.getUserById(studentId);
      expect(student, isNotNull);

      final secureStorage = _TestSecureStorageService();
      await secureStorage.writeInstalledCourseBundleVersion(
        remoteUserId: 962,
        remoteCourseId: 8106,
        versionId: 56,
      );
      final api = _TestMarketplaceApiService(
        secureStorage: secureStorage,
        latestCourseBundleInfoNotFound: true,
        enrollmentsState2: 'force-mismatch',
        enrollments: <EnrollmentSummary>[
          EnrollmentSummary(
            enrollmentId: 16,
            courseId: 8106,
            teacherId: 9912,
            status: 'approved',
            assignedAt: '2026-03-02T00:00:00Z',
            courseSubject: 'Legacy Course',
            teacherName: 'remote_teacher_legacy_hash_api',
            latestBundleVersionId: 56,
            latestBundleHash: '',
          ),
        ],
      );
      final service = EnrollmentSyncService(
        db: db,
        secureStorage: secureStorage,
        courseService: CourseService(db),
        marketplaceApi: api,
        promptRepository: PromptRepository(db: db),
        courseArtifactService: CourseArtifactService(),
      );

      await service.syncIfReady(currentUser: student!);

      expect(api.latestCourseBundleInfoCalls, equals(1));
      expect(api.downloadBundleCalls, equals(0));
      final assigned = await db.getAssignedCoursesForStudent(studentId);
      expect(assigned.map((course) => course.id), contains(courseVersionId));
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
        courseArtifactService: CourseArtifactService(),
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
        courseArtifactService: CourseArtifactService(),
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
        courseArtifactService: CourseArtifactService(),
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
        courseArtifactService: CourseArtifactService(),
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
        courseArtifactService: CourseArtifactService(),
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
    await secureStorage.writeLocalSyncState2(
      remoteUserId: 920,
      domain: 'enrollment_sync_student',
      state2: 'stored-student-state2',
    );
    final api = _TestMarketplaceApiService(
      secureStorage: secureStorage,
      enrollments: const <EnrollmentSummary>[],
      enrollmentsNotModified: true,
      enrollmentsEtag: 'student-enrollments-etag',
      enrollmentsState2: 'stored-student-state2',
    );
    final service = EnrollmentSyncService(
      db: db,
      secureStorage: secureStorage,
      courseService: CourseService(db),
      marketplaceApi: api,
      promptRepository: PromptRepository(db: db),
      courseArtifactService: CourseArtifactService(),
    );

    await service.syncIfReady(currentUser: student!);
    await service.syncIfReady(currentUser: student);

    expect(api.getEnrollmentsState2Calls, equals(1));
    expect(api.listEnrollmentsCalls, equals(0));
  });

  test('teacher local mutation refreshes stored local state2 immediately',
      () async {
    final teacherId = await db.createUser(
      username: 'teacher_state2_local',
      pinHash: 'hash',
      role: 'teacher',
      remoteUserId: 910,
    );
    final secureStorage = _TestSecureStorageService();
    final service = EnrollmentSyncService(
      db: db,
      secureStorage: secureStorage,
      courseService: CourseService(db),
      marketplaceApi: _TestMarketplaceApiService(
        secureStorage: secureStorage,
      ),
      promptRepository: PromptRepository(db: db),
      courseArtifactService: CourseArtifactService(),
    );
    db.setSyncRelevantChangeCallback((change) async {
      await service.handleLocalSyncRelevantChange(change);
    });

    final courseVersionId = await db.createCourseVersion(
      teacherId: teacherId,
      subject: 'State2 Original',
      granularity: 1,
      textbookText: '1 State2 Original\n',
    );
    final teacher = await db.getUserById(teacherId);
    expect(teacher, isNotNull);

    await service.refreshStoredLocalState2(currentUser: teacher!);
    final before = await secureStorage.readLocalSyncState2(
      remoteUserId: 910,
      domain: 'enrollment_sync_teacher',
    );
    expect(before, isNotNull);

    await db.updateCourseVersionSubject(
      id: courseVersionId,
      subject: 'State2 Updated',
    );

    final after = await secureStorage.readLocalSyncState2(
      remoteUserId: 910,
      domain: 'enrollment_sync_teacher',
    );
    expect(after, isNotNull);
    expect(after, isNot(equals(before)));
  });

  test(
    'student local state2 refreshes immediately when teacher metadata changes',
    () async {
      final teacherId = await db.createUser(
        username: 'teacher_state2_teacher_before',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 920,
      );
      final studentId = await db.createUser(
        username: 'student_state2_before',
        pinHash: 'hash',
        role: 'student',
        teacherId: teacherId,
        remoteUserId: 921,
      );
      final courseVersionId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'Teacher Metadata Course',
        granularity: 1,
        textbookText: '1 Teacher Metadata Course\n',
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: 922,
      );
      await db.assignStudent(
        studentId: studentId,
        courseVersionId: courseVersionId,
      );

      final secureStorage = _TestSecureStorageService();
      await secureStorage.writeInstalledCourseBundleVersion(
        remoteUserId: 921,
        remoteCourseId: 922,
        versionId: 5,
      );
      await secureStorage.writeSyncItemState(
        remoteUserId: 921,
        domain: 'enrollment_sync_student_bundle',
        scopeKey: 'course:922',
        contentHash: 'bundle-hash-922',
        lastChangedAt: DateTime.utc(2025, 1, 1),
        lastSyncedAt: DateTime.utc(2025, 1, 1),
      );

      final service = EnrollmentSyncService(
        db: db,
        secureStorage: secureStorage,
        courseService: CourseService(db),
        marketplaceApi: _TestMarketplaceApiService(
          secureStorage: secureStorage,
        ),
        promptRepository: PromptRepository(db: db),
        courseArtifactService: CourseArtifactService(),
      );
      db.setSyncRelevantChangeCallback((change) async {
        await service.handleLocalSyncRelevantChange(change);
      });

      final student = await db.getUserById(studentId);
      expect(student, isNotNull);
      await service.refreshStoredLocalState2(currentUser: student!);
      final before = await secureStorage.readLocalSyncState2(
        remoteUserId: 921,
        domain: 'enrollment_sync_student',
      );
      expect(before, isNotNull);

      await db.updateUsername(
        userId: teacherId,
        username: 'teacher_state2_teacher_after',
      );

      final after = await secureStorage.readLocalSyncState2(
        remoteUserId: 921,
        domain: 'enrollment_sync_student',
      );
      expect(after, isNotNull);
      expect(after, isNot(equals(before)));
    },
  );

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
        courseArtifactService: CourseArtifactService(),
      );

      await service.syncIfReady(currentUser: student!);

      expect(api.getEnrollmentsState2Calls, equals(0));
      expect(api.listDeletionEventsCalls, equals(1));
    },
  );

  test('student sync compares state2 and skips full list on no change',
      () async {
    final teacherId = await db.createUser(
      username: 'teacher_h',
      pinHash: 'hash',
      role: 'teacher',
      remoteUserId: 850,
    );
    final studentId = await db.createUser(
      username: 'student_h',
      pinHash: 'hash',
      role: 'student',
      teacherId: teacherId,
      remoteUserId: 950,
    );
    final student = await db.getUserById(studentId);
    expect(student, isNotNull);

    final secureStorage = _TestSecureStorageService();
    await secureStorage.writeLocalSyncState2(
      remoteUserId: 950,
      domain: 'enrollment_sync_student',
      state2: 'stored-student-state2',
    );
    final api = _TestMarketplaceApiService(
      secureStorage: secureStorage,
      enrollments: const <EnrollmentSummary>[],
      enrollmentsState2: 'stored-student-state2',
    );
    final service = EnrollmentSyncService(
      db: db,
      secureStorage: secureStorage,
      courseService: CourseService(db),
      marketplaceApi: api,
      promptRepository: PromptRepository(db: db),
      courseArtifactService: CourseArtifactService(),
    );

    await service.syncIfReady(currentUser: student!);

    expect(api.getEnrollmentsState2Calls, equals(1));
    expect(api.listEnrollmentsCalls, equals(0));
  });

  test('teacher sync compares state2 and skips full list on no change',
      () async {
    final teacherId = await db.createUser(
      username: 'teacher_f',
      pinHash: 'hash',
      role: 'teacher',
      remoteUserId: 830,
    );
    final teacher = await db.getUserById(teacherId);
    expect(teacher, isNotNull);

    final secureStorage = _TestSecureStorageService();
    await secureStorage.writeLocalSyncState2(
      remoteUserId: 830,
      domain: 'enrollment_sync_teacher',
      state2: 'stored-teacher-state2',
    );
    final api = _TestMarketplaceApiService(
      secureStorage: secureStorage,
      teacherCourses: const <TeacherCourseSummary>[],
      teacherCoursesState2: 'stored-teacher-state2',
    );
    final service = EnrollmentSyncService(
      db: db,
      secureStorage: secureStorage,
      courseService: CourseService(db),
      marketplaceApi: api,
      promptRepository: PromptRepository(db: db),
      courseArtifactService: CourseArtifactService(),
    );

    await service.syncIfReady(currentUser: teacher!);

    expect(api.getTeacherCoursesState2Calls, equals(1));
    expect(api.listTeacherCoursesCalls, equals(0));
    final runAt = await secureStorage.readSyncRunAt(
      remoteUserId: 830,
      domain: 'enrollment_sync_teacher',
    );
    expect(runAt, isNotNull);
  });

  test(
    'teacher timer no-change uses stored local state2 without rewriting stale local hash',
    () async {
      final teacherId = await db.createUser(
        username: 'teacher_zero_compute',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 860,
      );
      final teacher = await db.getUserById(teacherId);
      expect(teacher, isNotNull);

      final courseDir = await _createCourseFolder(
        label: 'zero_compute_teacher',
        rootTitle: 'Timer Zero Compute',
      );
      tempPaths.add(courseDir.path);

      final courseVersionId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'Timer Zero Compute',
        granularity: 1,
        textbookText: '1 Timer Zero Compute\n',
        sourcePath: courseDir.path,
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: 861,
      );

      final artifactService = _CountingCourseArtifactService();
      await artifactService.rebuildCourseArtifacts(
        courseVersionId: courseVersionId,
        folderPath: courseDir.path,
      );

      final secureStorage = _TestSecureStorageService();
      await secureStorage.writeInstalledCourseBundleVersion(
        remoteUserId: 860,
        remoteCourseId: 861,
        versionId: 5,
      );
      await secureStorage.writeSyncItemState(
        remoteUserId: 860,
        domain: 'enrollment_sync_teacher_upload',
        scopeKey: 'course:861',
        contentHash: 'stale-hash',
        lastChangedAt: DateTime.utc(2025, 1, 1),
        lastSyncedAt: DateTime.utc(2025, 1, 1),
      );
      secureStorage.writeSyncItemStateCalls = 0;
      await secureStorage.writeLocalSyncState2(
        remoteUserId: 860,
        domain: 'enrollment_sync_teacher',
        state2: 'stored-teacher-state2',
      );

      final api = _TestMarketplaceApiService(
        secureStorage: secureStorage,
        teacherCourses: const <TeacherCourseSummary>[],
        teacherCoursesState2: 'stored-teacher-state2',
      );
      final service = EnrollmentSyncService(
        db: db,
        secureStorage: secureStorage,
        courseService:
            CourseService(db, courseArtifactService: artifactService),
        marketplaceApi: api,
        promptRepository: PromptRepository(db: db),
        courseArtifactService: artifactService,
      );

      await service.syncIfReady(currentUser: teacher!);

      expect(api.getTeacherCoursesState2Calls, equals(1));
      expect(api.listTeacherCoursesCalls, equals(0));
      expect(secureStorage.writeSyncItemStateCalls, equals(0));
    },
  );

  test(
    'teacher timer mismatch reuses locally refreshed hash after prompt change',
    () async {
      final teacherId = await db.createUser(
        username: 'teacher_timer_prompt_change',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 870,
      );
      final teacher = await db.getUserById(teacherId);
      expect(teacher, isNotNull);

      final courseDir = await _createCourseFolder(
        label: 'timer_prompt_change',
        rootTitle: 'Timer Prompt Change',
      );
      tempPaths.add(courseDir.path);

      final courseVersionId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'Timer Prompt Change',
        granularity: 1,
        textbookText: '1 Timer Prompt Change\n',
        sourcePath: courseDir.path,
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: 871,
      );

      final artifactService = _CountingCourseArtifactService();
      await artifactService.rebuildCourseArtifacts(
        courseVersionId: courseVersionId,
        folderPath: courseDir.path,
      );

      final secureStorage = _TestSecureStorageService();
      await secureStorage.writeInstalledCourseBundleVersion(
        remoteUserId: 870,
        remoteCourseId: 871,
        versionId: 5,
      );
      await secureStorage.writeSyncRunAt(
        remoteUserId: 870,
        domain: 'enrollment_sync_teacher',
        runAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      );

      final bootstrapApi = _TestMarketplaceApiService(
        secureStorage: secureStorage,
      );
      final service = EnrollmentSyncService(
        db: db,
        secureStorage: secureStorage,
        courseService:
            CourseService(db, courseArtifactService: artifactService),
        marketplaceApi: bootstrapApi,
        promptRepository: PromptRepository(db: db),
        courseArtifactService: artifactService,
      );
      db.setSyncRelevantChangeCallback((change) async {
        await service.handleLocalSyncRelevantChange(change);
      });

      await service.refreshStoredLocalState2(currentUser: teacher!);
      final oldLocalState2 = await secureStorage.readLocalSyncState2(
        remoteUserId: 870,
        domain: 'enrollment_sync_teacher',
      );
      expect(oldLocalState2, isNotNull);

      final initialSyncState = await secureStorage.readSyncItemState(
        remoteUserId: 870,
        domain: 'enrollment_sync_teacher_upload',
        scopeKey: 'course:871',
      );
      expect(initialSyncState, isNotNull);
      final initialHash = initialSyncState!.contentHash;
      await secureStorage.writeSyncItemState(
        remoteUserId: 870,
        domain: 'enrollment_sync_teacher_upload',
        scopeKey: 'course:871',
        contentHash: initialHash,
        lastChangedAt: DateTime.utc(2025, 1, 1),
        lastSyncedAt: DateTime.utc(2025, 1, 1),
      );

      artifactService.resetCounters();
      await db.insertPromptTemplate(
        teacherId: teacherId,
        promptName: 'system',
        content: 'Explain with a new metaphor.',
        courseKey: courseDir.path,
      );
      expect(artifactService.computeUploadHashCalls, equals(1));

      final refreshedLocalState2 = await secureStorage.readLocalSyncState2(
        remoteUserId: 870,
        domain: 'enrollment_sync_teacher',
      );
      expect(refreshedLocalState2, isNotNull);
      expect(refreshedLocalState2, isNot(equals(oldLocalState2)));
      final refreshedSyncState = await secureStorage.readSyncItemState(
        remoteUserId: 870,
        domain: 'enrollment_sync_teacher_upload',
        scopeKey: 'course:871',
      );
      expect(refreshedSyncState, isNotNull);
      final refreshedHash = refreshedSyncState!.contentHash;

      artifactService.resetCounters();
      final syncApi = _TestMarketplaceApiService(
        secureStorage: secureStorage,
        teacherCoursesState2: oldLocalState2,
        teacherCoursesProvider: (listCallCount) => <TeacherCourseSummary>[
          TeacherCourseSummary(
            courseId: 871,
            subject: 'Timer Prompt Change',
            grade: '',
            description: '',
            visibility: 'public',
            approvalStatus: 'approved',
            publishedAt: '',
            latestBundleVersionId: listCallCount == 1 ? 5 : 8710001,
            latestBundleHash: listCallCount == 1 ? initialHash : refreshedHash,
            status: '',
          ),
        ],
      );
      final syncService = EnrollmentSyncService(
        db: db,
        secureStorage: secureStorage,
        courseService:
            CourseService(db, courseArtifactService: artifactService),
        marketplaceApi: syncApi,
        promptRepository: PromptRepository(db: db),
        courseArtifactService: artifactService,
      );

      await syncService.syncIfReady(currentUser: teacher);

      expect(syncApi.getTeacherCoursesState2Calls, equals(1));
      expect(syncApi.listTeacherCoursesCalls, greaterThan(0));
      expect(artifactService.computeUploadHashCalls, equals(0));
      expect(syncApi.uploadedBundles, isNotEmpty);
    },
  );
}
