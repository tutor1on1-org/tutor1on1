import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:family_teacher/db/app_database.dart';
import 'package:family_teacher/services/course_service.dart';
import 'package:family_teacher/services/enrollment_sync_service.dart';
import 'package:family_teacher/services/marketplace_api_service.dart';
import 'package:family_teacher/services/secure_storage_service.dart';

class _TestSecureStorageService extends SecureStorageService {
  _TestSecureStorageService({
    String? accessToken,
    int? deletionCursor,
  })  : _accessToken = accessToken,
        _deletionCursor = deletionCursor;

  final String? _accessToken;
  int? _deletionCursor;
  final Map<String, int> _installedVersionByKey = <String, int>{};

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
}

class _TestMarketplaceApiService extends MarketplaceApiService {
  _TestMarketplaceApiService({
    required SecureStorageService secureStorage,
    List<EnrollmentSummary>? enrollments,
    List<EnrollmentDeletionEvent>? deletionEvents,
    List<TeacherCourseSummary>? teacherCourses,
    List<EnrollmentDeletionEvent> Function(int? sinceId)? deletionEventsProvider,
  })  : _enrollments = enrollments ?? const <EnrollmentSummary>[],
        _deletionEvents = deletionEvents ?? const <EnrollmentDeletionEvent>[],
        _teacherCourses = teacherCourses ?? const <TeacherCourseSummary>[],
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
  final List<EnrollmentDeletionEvent> Function(int? sinceId)?
      _deletionEventsProvider;
  int? lastDeletionSinceId;

  @override
  Future<List<EnrollmentSummary>> listEnrollments() async {
    return _enrollments;
  }

  @override
  Future<List<EnrollmentDeletionEvent>> listEnrollmentDeletionEvents({
    int? sinceId,
  }) async {
    lastDeletionSinceId = sinceId;
    if (_deletionEventsProvider != null) {
      return _deletionEventsProvider(sinceId);
    }
    return _deletionEvents;
  }

  @override
  Future<List<TeacherCourseSummary>> listTeacherCourses() async {
    return _teacherCourses;
  }
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
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
      );
      final service = EnrollmentSyncService(
        db: db,
        secureStorage: secureStorage,
        courseService: CourseService(db),
        marketplaceApi: api,
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
}
