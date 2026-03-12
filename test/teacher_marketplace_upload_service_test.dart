import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_teacher/db/app_database.dart';
import 'package:family_teacher/services/marketplace_api_service.dart';
import 'package:family_teacher/services/secure_storage_service.dart';
import 'package:family_teacher/services/teacher_marketplace_upload_service.dart';

class _TestSecureStorageService extends SecureStorageService {
  @override
  Future<String?> readAuthAccessToken() async => 'token';
}

class _FakeMarketplaceApiService extends MarketplaceApiService {
  _FakeMarketplaceApiService({
    required SecureStorageService secureStorage,
    List<TeacherCourseSummary>? teacherCourses,
    List<TeacherCourseSummary>? createCourseResponses,
    List<Object>? ensureBundleResponses,
  })  : _teacherCourses = teacherCourses ?? <TeacherCourseSummary>[],
        _createCourseResponses =
            createCourseResponses ?? <TeacherCourseSummary>[],
        _ensureBundleResponses = ensureBundleResponses ?? <Object>[],
        super(
          secureStorage: secureStorage,
          baseUrl: 'https://example.com',
        );

  final List<TeacherCourseSummary> _teacherCourses;
  final List<TeacherCourseSummary> _createCourseResponses;
  final List<Object> _ensureBundleResponses;

  final List<int> ensureBundleCourseIds = <int>[];
  final List<int> uploadBundleIds = <int>[];
  final List<String> uploadCourseNames = <String>[];
  final List<int> publishCourseIds = <int>[];
  final List<String> publishVisibilities = <String>[];
  int createTeacherCourseCalls = 0;

  @override
  Future<List<TeacherCourseSummary>> listTeacherCourses() async {
    return _teacherCourses;
  }

  @override
  Future<TeacherCourseSummary> createTeacherCourse({
    required String subject,
    String? grade,
    String? description,
    List<int> subjectLabelIds = const <int>[],
  }) async {
    createTeacherCourseCalls += 1;
    if (_createCourseResponses.isEmpty) {
      throw StateError('No createTeacherCourse response configured.');
    }
    return _createCourseResponses.removeAt(0);
  }

  @override
  Future<EnsureBundleResult> ensureBundle(
    int courseId, {
    String? courseName,
  }) async {
    ensureBundleCourseIds.add(courseId);
    if (_ensureBundleResponses.isEmpty) {
      throw StateError('No ensureBundle response configured.');
    }
    final next = _ensureBundleResponses.removeAt(0);
    if (next is MarketplaceApiException) {
      throw next;
    }
    if (next is EnsureBundleResult) {
      return next;
    }
    throw StateError(
        'Unsupported ensureBundle response type: ${next.runtimeType}');
  }

  @override
  Future<Map<String, dynamic>> uploadBundle({
    required int bundleId,
    required String courseName,
    required File bundleFile,
  }) async {
    uploadBundleIds.add(bundleId);
    uploadCourseNames.add(courseName);
    return <String, dynamic>{'status': 'uploaded'};
  }

  @override
  Future<void> updateCourseVisibility({
    required int courseId,
    required String visibility,
  }) async {
    publishCourseIds.add(courseId);
    publishVisibilities.add(visibility);
  }
}

TeacherCourseSummary _teacherCourse(int courseId, String subject) {
  return TeacherCourseSummary(
    courseId: courseId,
    subject: subject,
    grade: '',
    description: '',
    visibility: 'private',
    publishedAt: '',
    latestBundleVersionId: null,
    status: 'active',
  );
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
    'resolveUploadTarget recovers from stale link and stores ensureBundle returned course_id',
    () async {
      final teacherId = await db.createUser(
        username: 'teacher_upload',
        pinHash: 'hash',
        role: 'teacher',
        remoteUserId: 111,
      );
      final courseVersionId = await db.createCourseVersion(
        teacherId: teacherId,
        subject: 'Algebra',
        granularity: 1,
        textbookText: '',
        sourcePath: r'C:\courses\algebra',
      );
      await db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: 999,
      );

      final api = _FakeMarketplaceApiService(
        secureStorage: _TestSecureStorageService(),
        teacherCourses: <TeacherCourseSummary>[],
        createCourseResponses: <TeacherCourseSummary>[
          _teacherCourse(101, 'Algebra'),
          _teacherCourse(202, 'Algebra'),
        ],
        ensureBundleResponses: <Object>[
          MarketplaceApiException('course not found', statusCode: 404),
          EnsureBundleResult(bundleId: 333, courseId: 444),
        ],
      );
      final service = TeacherMarketplaceUploadService(
        db: db,
        marketplaceApi: api,
      );

      final target = await service.resolveUploadTarget(
        courseVersionId: courseVersionId,
        courseSubject: 'Algebra',
        subjectLabelIds: const <int>[1, 2],
      );

      expect(target.bundleId, equals(333));
      expect(target.remoteCourseId, equals(444));
      expect(api.createTeacherCourseCalls, equals(2));
      expect(api.ensureBundleCourseIds, equals(<int>[101, 202]));
      final persistedRemoteCourseId =
          await db.getRemoteCourseId(courseVersionId);
      expect(persistedRemoteCourseId, equals(444));
    },
  );

  test(
    'uploadBundleAndPublish uses resolved course_id for visibility update',
    () async {
      final api = _FakeMarketplaceApiService(
        secureStorage: _TestSecureStorageService(),
      );
      final service = TeacherMarketplaceUploadService(
        db: db,
        marketplaceApi: api,
      );

      final tempDir = await Directory.systemTemp.createTemp(
        'teacher_upload_service_test_',
      );
      final bundleFile = File('${tempDir.path}\\bundle.zip');
      await bundleFile.writeAsBytes(<int>[1, 2, 3], flush: true);
      try {
        final response = await service.uploadBundleAndPublish(
          target: ResolvedUploadTarget(
            remoteCourseId: 444,
            bundleId: 333,
            approvalStatus: 'approved',
          ),
          courseSubject: 'Algebra',
          bundleFile: bundleFile,
          visibility: 'public',
        );

        expect(response['status'], equals('uploaded'));
        expect(api.uploadBundleIds, equals(<int>[333]));
        expect(api.uploadCourseNames, equals(<String>['Algebra']));
        expect(api.publishCourseIds, equals(<int>[444]));
        expect(api.publishVisibilities, equals(<String>['public']));
      } finally {
        if (bundleFile.existsSync()) {
          await bundleFile.delete();
        }
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );
}
