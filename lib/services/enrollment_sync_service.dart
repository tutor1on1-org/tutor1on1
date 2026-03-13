import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../db/app_database.dart';
import '../llm/prompt_repository.dart';
import 'course_artifact_service.dart';
import 'course_bundle_service.dart';
import 'course_service.dart';
import 'marketplace_api_service.dart';
import 'remote_student_identity_service.dart';
import 'remote_teacher_identity_service.dart';
import 'secure_storage_service.dart';
import 'sync_log_repository.dart';

class EnrollmentSyncService {
  EnrollmentSyncService({
    required AppDatabase db,
    required SecureStorageService secureStorage,
    required CourseService courseService,
    required MarketplaceApiService marketplaceApi,
    required PromptRepository promptRepository,
    CourseArtifactService? courseArtifactService,
    SyncLogRepository? syncLogRepository,
  })  : _db = db,
        _secureStorage = secureStorage,
        _courseService = courseService,
        _api = marketplaceApi,
        _promptRepository = promptRepository,
        _courseArtifactService = courseArtifactService,
        _syncLogRepository = syncLogRepository;

  final AppDatabase _db;
  final SecureStorageService _secureStorage;
  final CourseService _courseService;
  final MarketplaceApiService _api;
  final PromptRepository _promptRepository;
  final CourseArtifactService? _courseArtifactService;
  final SyncLogRepository? _syncLogRepository;
  final RemoteTeacherIdentityService _remoteTeacherIdentity =
      const RemoteTeacherIdentityService();
  final RemoteStudentIdentityService _remoteStudentIdentity =
      const RemoteStudentIdentityService();
  bool _syncing = false;
  static final RegExp _versionSuffixPattern = RegExp(r'_(\d{10,})$');
  static const Duration _syncMinInterval = Duration(seconds: 60);
  static const String _syncDomainDeletionEvents = 'enrollment_sync_deletions';
  static const String _syncDomainStudentEnrollments = 'enrollment_sync_student';
  static const String _syncDomainStudentCourseBundles =
      'enrollment_sync_student_bundle';
  static const String _syncDomainTeacherCourses = 'enrollment_sync_teacher';
  static const String _syncDomainTeacherCourseUpload =
      'enrollment_sync_teacher_upload';
  static const String _syncScopeEnrollments = 'enrollments';
  static const String _syncScopeTeacherCourses = 'teacher_courses';

  Future<void> forcePullFromServer({required User currentUser}) async {
    if (_syncing) {
      return;
    }
    final remoteUserId = currentUser.remoteUserId;
    if (remoteUserId == null || remoteUserId <= 0) {
      return;
    }
    final nowUtc = DateTime.now().toUtc();
    final summary = _SyncTransferSummary(
      domain: currentUser.role == 'teacher'
          ? 'enrollment_sync_teacher'
          : 'enrollment_sync_student',
    );
    _syncing = true;
    try {
      await _resetForcePullState(
        remoteUserId: remoteUserId,
        role: currentUser.role,
      );
      if (currentUser.role == 'student') {
        await _autoApproveLegacyCoursesWithoutTeacher(currentUser.id);
      }
      await _runCategoryIfDue(
        remoteUserId: remoteUserId,
        domain: _syncDomainDeletionEvents,
        nowUtc: nowUtc,
        force: true,
        action: () => _applyDeletionEvents(currentUser, remoteUserId),
      );
      if (currentUser.role == 'teacher') {
        await _runCategoryIfDue(
          remoteUserId: remoteUserId,
          domain: _syncDomainTeacherCourses,
          nowUtc: nowUtc,
          force: true,
          action: () => _syncTeacherCourses(
            currentUser: currentUser,
            remoteUserId: remoteUserId,
            summary: summary,
          ),
        );
      } else {
        await _runCategoryIfDue(
          remoteUserId: remoteUserId,
          domain: _syncDomainStudentEnrollments,
          nowUtc: nowUtc,
          force: true,
          action: () async {
            final enrollmentsResult = await _api.listEnrollmentsDelta(
              ifNoneMatch: null,
            );
            await _writeSyncListEtag(
              remoteUserId: remoteUserId,
              domain: _syncDomainStudentEnrollments,
              scopeKey: _syncScopeEnrollments,
              etag: enrollmentsResult.etag,
            );
            if (!enrollmentsResult.notModified) {
              await _syncStudentEnrollments(
                currentUser: currentUser,
                remoteUserId: remoteUserId,
                enrollments: enrollmentsResult.items,
                summary: summary,
              );
            }
          },
        );
      }
      await _appendSyncSummary(currentUser: currentUser, summary: summary);
    } finally {
      _syncing = false;
    }
  }

  Future<void> syncIfReady({required User currentUser}) async {
    if (_syncing) {
      return;
    }
    final remoteUserId = currentUser.remoteUserId;
    if (remoteUserId == null || remoteUserId <= 0) {
      return;
    }
    final nowUtc = DateTime.now().toUtc();
    final summary = _SyncTransferSummary(
      domain: currentUser.role == 'teacher'
          ? 'enrollment_sync_teacher'
          : 'enrollment_sync_student',
    );
    _syncing = true;
    try {
      if (currentUser.role == 'student') {
        await _autoApproveLegacyCoursesWithoutTeacher(currentUser.id);
      }
      await _runCategoryIfDue(
        remoteUserId: remoteUserId,
        domain: _syncDomainDeletionEvents,
        nowUtc: nowUtc,
        force: false,
        action: () => _applyDeletionEvents(currentUser, remoteUserId),
      );
      if (currentUser.role == 'teacher') {
        await _runCategoryIfDue(
          remoteUserId: remoteUserId,
          domain: _syncDomainTeacherCourses,
          nowUtc: nowUtc,
          force: false,
          action: () => _syncTeacherCourses(
            currentUser: currentUser,
            remoteUserId: remoteUserId,
            summary: summary,
          ),
        );
      } else {
        await _runCategoryIfDue(
          remoteUserId: remoteUserId,
          domain: _syncDomainStudentEnrollments,
          nowUtc: nowUtc,
          force: false,
          action: () async {
            final ifNoneMatch = await _secureStorage.readSyncListEtag(
              remoteUserId: remoteUserId,
              domain: _syncDomainStudentEnrollments,
              scopeKey: _syncScopeEnrollments,
            );
            final enrollmentsResult = await _api.listEnrollmentsDelta(
              ifNoneMatch: ifNoneMatch,
            );
            await _writeSyncListEtag(
              remoteUserId: remoteUserId,
              domain: _syncDomainStudentEnrollments,
              scopeKey: _syncScopeEnrollments,
              etag: enrollmentsResult.etag,
            );
            if (!enrollmentsResult.notModified) {
              await _syncStudentEnrollments(
                currentUser: currentUser,
                remoteUserId: remoteUserId,
                enrollments: enrollmentsResult.items,
                summary: summary,
              );
            }
          },
        );
      }
      await _appendSyncSummary(currentUser: currentUser, summary: summary);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _runCategoryIfDue({
    required int remoteUserId,
    required String domain,
    required DateTime nowUtc,
    required bool force,
    required Future<void> Function() action,
  }) async {
    if (!force) {
      final lastRun = await _secureStorage.readSyncRunAt(
        remoteUserId: remoteUserId,
        domain: domain,
      );
      if (lastRun != null &&
          nowUtc.difference(lastRun.toUtc()) < _syncMinInterval) {
        return;
      }
    }
    await action();
    await _secureStorage.writeSyncRunAt(
      remoteUserId: remoteUserId,
      domain: domain,
      runAt: nowUtc,
    );
  }

  Future<void> _resetForcePullState({
    required int remoteUserId,
    required String role,
  }) async {
    await _secureStorage.clearSyncDomainState(
      remoteUserId: remoteUserId,
      domain: _syncDomainDeletionEvents,
      clearItemStates: false,
      clearListEtags: false,
    );
    if (role == 'teacher') {
      await _secureStorage.clearSyncDomainState(
        remoteUserId: remoteUserId,
        domain: _syncDomainTeacherCourses,
        clearItemStates: false,
      );
      return;
    }
    await _secureStorage.clearSyncDomainState(
      remoteUserId: remoteUserId,
      domain: _syncDomainStudentEnrollments,
      clearItemStates: false,
    );
  }

  Future<void> _autoApproveLegacyCoursesWithoutTeacher(int studentId) async {
    final assignedCourses = await _db.getAssignedCoursesForStudent(studentId);
    for (final course in assignedCourses) {
      final teacher = await _db.getUserById(course.teacherId);
      if (teacher != null && teacher.role == 'teacher') {
        continue;
      }
      final remoteCourseId = await _db.getRemoteCourseId(course.id);
      if (remoteCourseId != null && remoteCourseId > 0) {
        continue;
      }
      await _db.deleteStudentCourseData(
        studentId: studentId,
        courseVersionId: course.id,
        removeAssignment: true,
      );
      await _cleanupCourseIfOrphaned(course.id);
    }
  }

  Future<void> _applyDeletionEvents(User currentUser, int remoteUserId) async {
    final sinceId = await _secureStorage.readEnrollmentDeletionCursor(
      remoteUserId,
    );
    final events = await _api.listEnrollmentDeletionEvents(sinceId: sinceId);
    if (events.isEmpty) {
      return;
    }
    var maxEventId = sinceId ?? 0;
    for (final event in events) {
      if (event.eventId > maxEventId) {
        maxEventId = event.eventId;
      }
      if (currentUser.role == 'student') {
        if (event.studentId != remoteUserId) {
          continue;
        }
        await _removeRemoteCourseFromStudent(
          localStudentId: currentUser.id,
          remoteCourseId: event.courseId,
        );
        continue;
      }
      if (currentUser.role == 'teacher' &&
          event.teacherUserId == remoteUserId) {
        final localStudent = await _db.findUserByRemoteId(event.studentId);
        if (localStudent == null) {
          continue;
        }
        final courseVersionId =
            await _db.getCourseVersionIdForRemoteCourse(event.courseId);
        if (courseVersionId == null) {
          continue;
        }
        await _db.deleteStudentCourseData(
          studentId: localStudent.id,
          courseVersionId: courseVersionId,
          removeAssignment: true,
        );
      }
    }
    await _secureStorage.writeEnrollmentDeletionCursor(
        remoteUserId, maxEventId);
  }

  Future<void> _syncStudentEnrollments({
    required User currentUser,
    required int remoteUserId,
    required List<EnrollmentSummary> enrollments,
    required _SyncTransferSummary summary,
  }) async {
    final activeRemoteCourseIds = <int>{};
    for (final enrollment in enrollments) {
      if (enrollment.courseId <= 0) {
        continue;
      }
      final localTeacherId =
          await _remoteTeacherIdentity.resolveOrCreateLocalTeacherId(
        db: _db,
        remoteTeacherId: enrollment.teacherId,
        usernameHint: enrollment.teacherName,
      );
      activeRemoteCourseIds.add(enrollment.courseId);
      final latestBundleVersionId = enrollment.latestBundleVersionId;
      if (latestBundleVersionId == null || latestBundleVersionId <= 0) {
        final existingCourseVersionId =
            await _db.getCourseVersionIdForRemoteCourse(enrollment.courseId);
        if (existingCourseVersionId != null) {
          await _ensureCourseTeacher(
            courseVersionId: existingCourseVersionId,
            expectedTeacherId: localTeacherId,
          );
        }
        continue;
      }
      var existingCourseVersionId =
          await _db.getCourseVersionIdForRemoteCourse(enrollment.courseId);
      if (existingCourseVersionId != null) {
        await _ensureCourseTeacher(
          courseVersionId: existingCourseVersionId,
          expectedTeacherId: localTeacherId,
        );
      }
      final remoteBundle = await _resolveRemoteBundleInfo(
        remoteCourseId: enrollment.courseId,
        courseSubject: enrollment.courseSubject,
        latestBundleVersionId: latestBundleVersionId,
        latestBundleHash: enrollment.latestBundleHash,
      );
      final syncedCourse = await _syncRemoteCourseFromServer(
        remoteUserId: remoteUserId,
        remoteCourseId: enrollment.courseId,
        courseSubject: enrollment.courseSubject,
        latestBundleVersionId: remoteBundle.bundleVersionId,
        latestBundleHash: remoteBundle.hash,
        readLocalHash: (_, __) => _readStudentCourseSyncHash(
          remoteUserId: remoteUserId,
          remoteCourseId: enrollment.courseId,
        ),
        onHashesMatch: (_, __) async {},
        importRemoteCourse: (resolvedCourseVersionId) =>
            _downloadAndImportCourse(
          enrollment: enrollment,
          bundleVersionId: remoteBundle.bundleVersionId,
          existingCourseVersionId: resolvedCourseVersionId,
          localTeacherId: localTeacherId,
          bundleHash: remoteBundle.hash,
          summary: summary,
        ),
        onHashesDiffer: (localCourse, __, ___) => _downloadAndImportCourse(
          enrollment: enrollment,
          bundleVersionId: remoteBundle.bundleVersionId,
          existingCourseVersionId: localCourse.id,
          localTeacherId: localTeacherId,
          bundleHash: remoteBundle.hash,
          summary: summary,
        ),
      );
      existingCourseVersionId = syncedCourse.id;
      await _ensureCourseTeacher(
        courseVersionId: existingCourseVersionId,
        expectedTeacherId: localTeacherId,
      );
      await _db.upsertCourseRemoteLink(
        courseVersionId: existingCourseVersionId,
        remoteCourseId: enrollment.courseId,
      );
      await _db.assignStudent(
        studentId: currentUser.id,
        courseVersionId: existingCourseVersionId,
      );
      await _ensureCourseSubject(
        courseVersionId: existingCourseVersionId,
        expectedSubject: enrollment.courseSubject,
      );
      await _writeStudentCourseSyncState(
        remoteUserId: remoteUserId,
        remoteCourseId: enrollment.courseId,
        bundleVersionId: remoteBundle.bundleVersionId,
        bundleHash: remoteBundle.hash,
      );
    }

    final assignedLinks =
        await _db.getAssignedRemoteCoursesForStudent(currentUser.id);
    for (final link in assignedLinks) {
      if (activeRemoteCourseIds.contains(link.remoteCourseId)) {
        continue;
      }
      await _removeRemoteCourseFromStudent(
        localStudentId: currentUser.id,
        remoteCourseId: link.remoteCourseId,
      );
    }
    await _repairStudentStaleDuplicateCourses(
      currentUser: currentUser,
      enrollments: enrollments,
    );
  }

  Future<CourseVersion> _downloadAndImportCourse({
    required EnrollmentSummary enrollment,
    required int bundleVersionId,
    required int? existingCourseVersionId,
    required int localTeacherId,
    required String bundleHash,
    required _SyncTransferSummary summary,
  }) async {
    final bundleService = CourseBundleService();
    File? bundleFile;
    try {
      final targetPath = await bundleService.createTempBundlePath(
        label: enrollment.courseSubject,
      );
      bundleFile = await _api.downloadBundleToFile(
        bundleVersionId: bundleVersionId,
        targetPath: targetPath,
      );
      summary.downloaded.add(
        SyncTransferLogItem(
          direction: 'download',
          fileName: p.basename(bundleFile.path),
          sizeBytes: bundleFile.lengthSync(),
          courseSubject: enrollment.courseSubject,
          remoteCourseId: enrollment.courseId,
          bundleVersionId: bundleVersionId,
          hash: bundleHash,
          source: 'student_enrollment_sync',
        ),
      );
      await bundleService.validateBundleForImport(bundleFile);
      final folderPath = await bundleService.extractBundleFromFile(
        bundleFile: bundleFile,
        courseName: enrollment.courseSubject,
      );
      final preview = await _courseService.previewCourseLoad(
        folderPath: folderPath,
        courseVersionId: existingCourseVersionId,
        courseNameOverride: enrollment.courseSubject,
      );
      if (!preview.success) {
        throw StateError(preview.message);
      }
      final mode = existingCourseVersionId == null
          ? CourseReloadMode.fresh
          : CourseReloadMode.override;
      final result = await _courseService.applyCourseLoad(
        teacherId: localTeacherId,
        preview: preview,
        mode: mode,
      );
      if (!result.success || result.course == null) {
        throw StateError(result.message);
      }
      return result.course!;
    } finally {
      if (bundleFile != null && bundleFile.existsSync()) {
        await bundleFile.delete();
      }
    }
  }

  Future<void> _removeRemoteCourseFromStudent({
    required int localStudentId,
    required int remoteCourseId,
  }) async {
    final courseVersionId =
        await _db.getCourseVersionIdForRemoteCourse(remoteCourseId);
    if (courseVersionId == null) {
      return;
    }
    await _db.deleteStudentCourseData(
      studentId: localStudentId,
      courseVersionId: courseVersionId,
      removeAssignment: true,
    );
    await _cleanupCourseIfOrphaned(courseVersionId);
  }

  Future<void> _cleanupCourseIfOrphaned(int courseVersionId) async {
    final assignments = await _db.getAssignmentsForCourse(courseVersionId);
    if (assignments.isNotEmpty) {
      return;
    }
    await _db.deleteCourseVersion(courseVersionId);
  }

  Future<void> _syncTeacherCourses({
    required User currentUser,
    required int remoteUserId,
    required _SyncTransferSummary summary,
  }) async {
    final firstSync = await _secureStorage.readSyncRunAt(
          remoteUserId: remoteUserId,
          domain: _syncDomainTeacherCourses,
        ) ==
        null;
    var remoteCourses = await _loadTeacherCourses(
      remoteUserId: remoteUserId,
      preferDelta: true,
    );
    await _reconcileTeacherCourseMetadata(
      currentUser: currentUser,
      remoteCourses: remoteCourses,
    );
    await _pullTeacherCoursesFromServer(
      currentUser: currentUser,
      remoteUserId: remoteUserId,
      remoteCourses: remoteCourses,
      initializeOnly: firstSync,
      summary: summary,
    );
    if (firstSync) {
      await _cleanupTeacherLocalDuplicates(currentUser.id);
      return;
    }
    await _uploadLocalTeacherCourses(
      currentUser: currentUser,
      remoteUserId: remoteUserId,
      remoteCourses: remoteCourses,
      summary: summary,
    );
    remoteCourses = await _loadTeacherCourses(
      remoteUserId: remoteUserId,
      preferDelta: false,
    );
    await _reconcileTeacherCourseMetadata(
      currentUser: currentUser,
      remoteCourses: remoteCourses,
    );
    await _pullTeacherCoursesFromServer(
      currentUser: currentUser,
      remoteUserId: remoteUserId,
      remoteCourses: remoteCourses,
      initializeOnly: false,
      summary: summary,
    );
    await _cleanupTeacherLocalDuplicates(currentUser.id);
  }

  Future<List<TeacherCourseSummary>> _loadTeacherCourses({
    required int remoteUserId,
    required bool preferDelta,
  }) async {
    if (!preferDelta) {
      return _api.listTeacherCourses();
    }
    final ifNoneMatch = await _secureStorage.readSyncListEtag(
      remoteUserId: remoteUserId,
      domain: _syncDomainTeacherCourses,
      scopeKey: _syncScopeTeacherCourses,
    );
    final result = await _api.listTeacherCoursesDelta(
      ifNoneMatch: ifNoneMatch,
    );
    await _writeSyncListEtag(
      remoteUserId: remoteUserId,
      domain: _syncDomainTeacherCourses,
      scopeKey: _syncScopeTeacherCourses,
      etag: result.etag,
    );
    if (result.notModified) {
      return _api.listTeacherCourses();
    }
    return result.items;
  }

  Future<void> _reconcileTeacherCourseMetadata({
    required User currentUser,
    required List<TeacherCourseSummary> remoteCourses,
  }) async {
    final localCourses = await _db.getCourseVersionsForTeacher(currentUser.id);
    final localRemoteIdByCourseVersion = <int, int?>{};
    for (final course in localCourses) {
      localRemoteIdByCourseVersion[course.id] = await _db.getRemoteCourseId(
        course.id,
      );
    }

    for (final remoteCourse in remoteCourses) {
      var localCourseVersionId = await _db.getCourseVersionIdForRemoteCourse(
        remoteCourse.courseId,
      );
      if (localCourseVersionId == null) {
        final candidate = _findLocalCourseCandidate(
          localCourses: localCourses,
          localRemoteIdByCourseVersion: localRemoteIdByCourseVersion,
          targetSubject: remoteCourse.subject,
        );
        if (candidate != null) {
          localCourseVersionId = candidate.id;
        } else {
          localCourseVersionId = await _db.createCourseVersion(
            teacherId: currentUser.id,
            subject: remoteCourse.subject,
            granularity: 1,
            textbookText: '',
            sourcePath: null,
          );
          final created = await _db.getCourseVersionById(localCourseVersionId);
          if (created != null) {
            localCourses.add(created);
          }
        }
        await _db.upsertCourseRemoteLink(
          courseVersionId: localCourseVersionId,
          remoteCourseId: remoteCourse.courseId,
        );
        localRemoteIdByCourseVersion[localCourseVersionId] =
            remoteCourse.courseId;
      }
      await _claimTeacherCourseOwnership(
        currentUser: currentUser,
        courseVersionId: localCourseVersionId,
        localCourses: localCourses,
        localRemoteIdByCourseVersion: localRemoteIdByCourseVersion,
      );
      await _ensureCourseSubject(
        courseVersionId: localCourseVersionId,
        expectedSubject: remoteCourse.subject,
      );
    }
  }

  Future<void> _pullTeacherCoursesFromServer({
    required User currentUser,
    required int remoteUserId,
    required List<TeacherCourseSummary> remoteCourses,
    required bool initializeOnly,
    required _SyncTransferSummary summary,
  }) async {
    for (final remoteCourse in remoteCourses) {
      final latestBundleVersionId = remoteCourse.latestBundleVersionId ?? 0;
      if (latestBundleVersionId <= 0) {
        continue;
      }
      final remoteBundle = await _resolveRemoteBundleInfo(
        remoteCourseId: remoteCourse.courseId,
        courseSubject: remoteCourse.subject,
        latestBundleVersionId: latestBundleVersionId,
        latestBundleHash: remoteCourse.latestBundleHash,
      );
      await _syncRemoteCourseFromServer(
        remoteUserId: remoteUserId,
        remoteCourseId: remoteCourse.courseId,
        courseSubject: remoteCourse.subject,
        latestBundleVersionId: remoteBundle.bundleVersionId,
        latestBundleHash: remoteBundle.hash,
        readLocalHash: (localCourse, _) => _computeTeacherCourseSyncHash(
          teacher: currentUser,
          course: localCourse,
          remoteCourseId: remoteCourse.courseId,
        ),
        onHashesMatch: (localCourse, __) => _initializeTeacherCourseSyncState(
          currentUser: currentUser,
          remoteUserId: remoteUserId,
          remoteCourseId: remoteCourse.courseId,
          localCourse: localCourse,
          bundleVersionId: remoteBundle.bundleVersionId,
        ),
        importRemoteCourse: (resolvedCourseVersionId) =>
            _downloadAndImportTeacherCourse(
          currentUser: currentUser,
          remoteUserId: remoteUserId,
          remoteCourseId: remoteCourse.courseId,
          courseSubject: remoteCourse.subject,
          bundleVersionId: remoteBundle.bundleVersionId,
          existingCourseVersionId: resolvedCourseVersionId,
          summary: summary,
        ),
        onHashesDiffer: (localCourse, localHash, installedVersion) async {
          if (initializeOnly || installedVersion == null) {
            return _downloadAndImportTeacherCourse(
              currentUser: currentUser,
              remoteUserId: remoteUserId,
              remoteCourseId: remoteCourse.courseId,
              courseSubject: remoteCourse.subject,
              bundleVersionId: remoteBundle.bundleVersionId,
              existingCourseVersionId: localCourse.id,
              summary: summary,
            );
          }
          final syncState = await _secureStorage.readSyncItemState(
            remoteUserId: remoteUserId,
            domain: _syncDomainTeacherCourseUpload,
            scopeKey: _teacherCourseScopeKey(remoteCourse.courseId),
          );
          if (syncState != null && syncState.contentHash != localHash) {
            throw StateError(
              'Teacher course sync conflict for "${remoteCourse.subject}". '
              'Pull latest server course before uploading local changes.',
            );
          }
          return _downloadAndImportTeacherCourse(
            currentUser: currentUser,
            remoteUserId: remoteUserId,
            remoteCourseId: remoteCourse.courseId,
            courseSubject: remoteCourse.subject,
            bundleVersionId: remoteBundle.bundleVersionId,
            existingCourseVersionId: localCourse.id,
            summary: summary,
          );
        },
      );
    }
  }

  Future<_ResolvedRemoteBundleInfo> _resolveRemoteBundleInfo({
    required int remoteCourseId,
    required String courseSubject,
    required int latestBundleVersionId,
    required String latestBundleHash,
  }) async {
    final normalizedHash = latestBundleHash.trim();
    if (normalizedHash.isNotEmpty) {
      return _ResolvedRemoteBundleInfo(
        bundleVersionId: latestBundleVersionId,
        hash: normalizedHash,
      );
    }
    LatestCourseBundleInfo resolved;
    try {
      resolved = await _api.getLatestCourseBundleInfo(remoteCourseId);
    } on MarketplaceApiException catch (error) {
      if (error.statusCode == 404) {
        return _ResolvedRemoteBundleInfo(
          bundleVersionId: latestBundleVersionId,
          hash: '',
        );
      }
      rethrow;
    }
    final resolvedHash = resolved.hash.trim();
    if (resolved.bundleVersionId <= 0 || resolvedHash.isEmpty) {
      throw StateError(
        'Remote bundle hash is missing for "$courseSubject".',
      );
    }
    return _ResolvedRemoteBundleInfo(
      bundleVersionId: resolved.bundleVersionId,
      hash: resolvedHash,
    );
  }

  Future<_ResolvedCourseSyncState> _resolveCourseSyncState({
    required int remoteUserId,
    required int remoteCourseId,
  }) async {
    final courseVersionId =
        await _db.getCourseVersionIdForRemoteCourse(remoteCourseId);
    final installedVersion =
        await _secureStorage.readInstalledCourseBundleVersion(
      remoteUserId: remoteUserId,
      remoteCourseId: remoteCourseId,
    );
    final localCourse = courseVersionId == null
        ? null
        : await _db.getCourseVersionById(courseVersionId);
    if (localCourse == null) {
      return _ResolvedCourseSyncState(
        courseVersionId: courseVersionId,
        installedVersion: installedVersion,
        localCourse: null,
        canBuildLocalBundle: false,
      );
    }
    if (_courseArtifactService == null) {
      throw StateError(
        'Course artifact service is required for course sync.',
      );
    }
    var hasCachedArtifacts = await _hasCachedCourseArtifacts(localCourse.id);
    if (!hasCachedArtifacts) {
      final localSourcePath = (localCourse.sourcePath ?? '').trim();
      if (localSourcePath.isNotEmpty &&
          Directory(localSourcePath).existsSync()) {
        await _ensureCourseArtifacts(localCourse);
        hasCachedArtifacts = await _hasCachedCourseArtifacts(localCourse.id);
      }
    }
    return _ResolvedCourseSyncState(
      courseVersionId: courseVersionId,
      installedVersion: installedVersion,
      localCourse: localCourse,
      canBuildLocalBundle: hasCachedArtifacts,
    );
  }

  Future<CourseVersion> _syncRemoteCourseFromServer({
    required int remoteUserId,
    required int remoteCourseId,
    required String courseSubject,
    required int latestBundleVersionId,
    required String latestBundleHash,
    required Future<String?> Function(
      CourseVersion localCourse,
      int? installedVersion,
    ) readLocalHash,
    required Future<void> Function(
      CourseVersion localCourse,
      String localHash,
    ) onHashesMatch,
    required Future<CourseVersion> Function(int? existingCourseVersionId)
        importRemoteCourse,
    required Future<CourseVersion> Function(
      CourseVersion localCourse,
      String localHash,
      int? installedVersion,
    ) onHashesDiffer,
  }) async {
    final remoteHash = latestBundleHash.trim();
    final localState = await _resolveCourseSyncState(
      remoteUserId: remoteUserId,
      remoteCourseId: remoteCourseId,
    );
    if (remoteHash.isEmpty) {
      if (localState.localCourse != null &&
          localState.installedVersion != null &&
          latestBundleVersionId <= localState.installedVersion!) {
        return localState.localCourse!;
      }
      return importRemoteCourse(localState.courseVersionId);
    }
    if (localState.localCourse == null || !localState.canBuildLocalBundle) {
      return importRemoteCourse(localState.courseVersionId);
    }
    final localHash = (await readLocalHash(
                localState.localCourse!, localState.installedVersion))
            ?.trim() ??
        '';
    if (localHash.isEmpty) {
      return importRemoteCourse(localState.courseVersionId);
    }
    if (localHash == remoteHash) {
      await onHashesMatch(localState.localCourse!, localHash);
      return localState.localCourse!;
    }
    return onHashesDiffer(
      localState.localCourse!,
      localHash,
      localState.installedVersion,
    );
  }

  Future<String?> _readStudentCourseSyncHash({
    required int remoteUserId,
    required int remoteCourseId,
  }) async {
    final syncState = await _secureStorage.readSyncItemState(
      remoteUserId: remoteUserId,
      domain: _syncDomainStudentCourseBundles,
      scopeKey: _teacherCourseScopeKey(remoteCourseId),
    );
    final normalized = syncState?.contentHash.trim() ?? '';
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  Future<void> _writeStudentCourseSyncState({
    required int remoteUserId,
    required int remoteCourseId,
    required int bundleVersionId,
    required String bundleHash,
  }) async {
    final now = DateTime.now().toUtc();
    await _secureStorage.writeInstalledCourseBundleVersion(
      remoteUserId: remoteUserId,
      remoteCourseId: remoteCourseId,
      versionId: bundleVersionId,
    );
    await _secureStorage.writeSyncItemState(
      remoteUserId: remoteUserId,
      domain: _syncDomainStudentCourseBundles,
      scopeKey: _teacherCourseScopeKey(remoteCourseId),
      contentHash: bundleHash.trim(),
      lastChangedAt: now,
      lastSyncedAt: now,
    );
  }

  Future<void> _initializeTeacherCourseSyncState({
    required User currentUser,
    required int remoteUserId,
    required int remoteCourseId,
    required CourseVersion localCourse,
    required int bundleVersionId,
  }) async {
    final localHash = await _computeTeacherCourseSyncHash(
      teacher: currentUser,
      course: localCourse,
      remoteCourseId: remoteCourseId,
    );
    final now = DateTime.now().toUtc();
    await _secureStorage.writeInstalledCourseBundleVersion(
      remoteUserId: remoteUserId,
      remoteCourseId: remoteCourseId,
      versionId: bundleVersionId,
    );
    await _secureStorage.writeSyncItemState(
      remoteUserId: remoteUserId,
      domain: _syncDomainTeacherCourseUpload,
      scopeKey: _teacherCourseScopeKey(remoteCourseId),
      contentHash: localHash,
      lastChangedAt: now,
      lastSyncedAt: now,
    );
  }

  Future<void> _uploadLocalTeacherCourses({
    required User currentUser,
    required int remoteUserId,
    required List<TeacherCourseSummary> remoteCourses,
    required _SyncTransferSummary summary,
  }) async {
    final remoteCoursesById = <int, TeacherCourseSummary>{
      for (final remoteCourse in remoteCourses)
        remoteCourse.courseId: remoteCourse,
    };
    final localCourses = await _db.getCourseVersionsForTeacher(currentUser.id);
    for (final course in localCourses) {
      final sourcePath = (course.sourcePath ?? '').trim();
      if (_courseArtifactService != null) {
        await _ensureCourseArtifacts(course);
      }
      final hasArtifacts = _courseArtifactService != null &&
          await _hasCachedCourseArtifacts(course.id);
      if (!hasArtifacts &&
          (sourcePath.isEmpty || !Directory(sourcePath).existsSync())) {
        continue;
      }
      final target = await _resolveTeacherUploadTarget(
        courseVersionId: course.id,
        courseSubject: course.subject,
        remoteCoursesById: remoteCoursesById,
      );
      final remoteCourseId = target.courseId;
      final scopeKey = _teacherCourseScopeKey(remoteCourseId);
      final remoteCourse = remoteCoursesById[remoteCourseId];
      final remoteLatestVersion = remoteCourse?.latestBundleVersionId ?? 0;
      final installedVersion =
          await _secureStorage.readInstalledCourseBundleVersion(
        remoteUserId: remoteUserId,
        remoteCourseId: remoteCourseId,
      );
      final preparedBundle = await _prepareTeacherCourseBundle(
        teacher: currentUser,
        course: course,
        remoteCourseId: remoteCourseId,
      );
      try {
        final syncState = await _secureStorage.readSyncItemState(
          remoteUserId: remoteUserId,
          domain: _syncDomainTeacherCourseUpload,
          scopeKey: scopeKey,
        );
        final localChanged =
            syncState == null || syncState.contentHash != preparedBundle.hash;
        if (!localChanged &&
            installedVersion != null &&
            installedVersion == remoteLatestVersion) {
          continue;
        }
        if (remoteLatestVersion > 0 &&
            installedVersion != null &&
            remoteLatestVersion > installedVersion) {
          throw StateError(
            'Teacher course sync conflict for "${course.subject}". '
            'Pull latest server course before uploading local changes.',
          );
        }
        final uploadResponse = await _api.uploadBundle(
          bundleId: target.bundleId,
          courseName: course.subject,
          bundleFile: preparedBundle.bundleFile,
        );
        final uploadedVersionId =
            (uploadResponse['bundle_version_id'] as num?)?.toInt() ??
                remoteLatestVersion;
        summary.uploaded.add(
          SyncTransferLogItem(
            direction: 'upload',
            fileName: p.basename(preparedBundle.bundleFile.path),
            sizeBytes: preparedBundle.bundleFile.lengthSync(),
            courseSubject: course.subject,
            remoteCourseId: remoteCourseId,
            bundleId: target.bundleId,
            bundleVersionId: uploadedVersionId,
            hash: preparedBundle.hash,
            source: 'teacher_course_sync',
          ),
        );
        final now = DateTime.now().toUtc();
        await _secureStorage.writeInstalledCourseBundleVersion(
          remoteUserId: remoteUserId,
          remoteCourseId: remoteCourseId,
          versionId: uploadedVersionId,
        );
        await _secureStorage.writeSyncItemState(
          remoteUserId: remoteUserId,
          domain: _syncDomainTeacherCourseUpload,
          scopeKey: scopeKey,
          contentHash: preparedBundle.hash,
          lastChangedAt: now,
          lastSyncedAt: now,
        );
      } finally {
        if (preparedBundle.bundleFile.existsSync()) {
          await preparedBundle.bundleFile.delete();
        }
      }
    }
  }

  Future<EnsureBundleResult> _resolveTeacherUploadTarget({
    required int courseVersionId,
    required String courseSubject,
    required Map<int, TeacherCourseSummary> remoteCoursesById,
  }) async {
    final storedRemoteCourseId = await _db.getRemoteCourseId(courseVersionId);
    var remoteCourseId = storedRemoteCourseId;
    final normalizedCourseName = _normalizeCourseName(courseSubject);

    if (remoteCourseId == null || remoteCoursesById[remoteCourseId] == null) {
      for (final remoteCourse in remoteCoursesById.values) {
        if (_normalizeCourseName(remoteCourse.subject) ==
            normalizedCourseName) {
          remoteCourseId = remoteCourse.courseId;
          break;
        }
      }
    }
    if (remoteCourseId == null || remoteCourseId <= 0) {
      final created = await _api.createTeacherCourse(
        subject: courseSubject,
        grade: '',
        description: 'Uploaded from Tutor1on1.',
      );
      remoteCourseId = created.courseId;
      remoteCoursesById[remoteCourseId] = created;
    }
    await _db.upsertCourseRemoteLink(
      courseVersionId: courseVersionId,
      remoteCourseId: remoteCourseId,
    );

    try {
      final ensured = await _api.ensureBundle(
        remoteCourseId,
        courseName: courseSubject,
      );
      await _db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: ensured.courseId,
      );
      return ensured;
    } on MarketplaceApiException catch (error) {
      if (error.statusCode != 404) {
        rethrow;
      }
      final created = await _api.createTeacherCourse(
        subject: courseSubject,
        grade: '',
        description: 'Uploaded from Tutor1on1.',
      );
      remoteCourseId = created.courseId;
      remoteCoursesById[remoteCourseId] = created;
      await _db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: remoteCourseId,
      );
      final ensured = await _api.ensureBundle(
        remoteCourseId,
        courseName: courseSubject,
      );
      await _db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: ensured.courseId,
      );
      return ensured;
    }
  }

  Future<_PreparedTeacherCourseBundle> _prepareTeacherCourseBundle({
    required User teacher,
    required CourseVersion course,
    required int remoteCourseId,
  }) async {
    if (_courseArtifactService != null) {
      await _ensureCourseArtifacts(course);
      final promptMetadata = await _buildPromptBundleMetadata(
        teacher: teacher,
        course: course,
        remoteCourseId: remoteCourseId,
      );
      final prepared = await _courseArtifactService.prepareUploadBundle(
        courseVersionId: course.id,
        promptMetadata: promptMetadata,
        bundleLabel: course.subject,
      );
      return _PreparedTeacherCourseBundle(
        bundleFile: prepared.bundleFile,
        hash: prepared.hash,
      );
    }
    final sourcePath = (course.sourcePath ?? '').trim();
    if (sourcePath.isEmpty) {
      throw StateError('Course source path missing for "${course.subject}".');
    }
    final bundleService = CourseBundleService();
    final promptMetadata = await _buildPromptBundleMetadata(
      teacher: teacher,
      course: course,
      remoteCourseId: remoteCourseId,
    );
    final bundleFile = await bundleService.createBundleFromFolder(
      sourcePath,
      promptMetadata: promptMetadata,
    );
    final hash = await bundleService.computeBundleSemanticHash(bundleFile);
    return _PreparedTeacherCourseBundle(
      bundleFile: bundleFile,
      hash: hash,
    );
  }

  Future<String> _computeTeacherCourseSyncHash({
    required User teacher,
    required CourseVersion course,
    required int remoteCourseId,
  }) async {
    if (_courseArtifactService != null) {
      await _ensureCourseArtifacts(course);
      final promptMetadata = await _buildPromptBundleMetadata(
        teacher: teacher,
        course: course,
        remoteCourseId: remoteCourseId,
      );
      return _courseArtifactService.computeUploadHash(
        courseVersionId: course.id,
        promptMetadata: promptMetadata,
      );
    }
    final preparedBundle = await _prepareTeacherCourseBundle(
      teacher: teacher,
      course: course,
      remoteCourseId: remoteCourseId,
    );
    try {
      return preparedBundle.hash;
    } finally {
      if (preparedBundle.bundleFile.existsSync()) {
        await preparedBundle.bundleFile.delete();
      }
    }
  }

  Future<CourseVersion> _downloadAndImportTeacherCourse({
    required User currentUser,
    required int remoteUserId,
    required int remoteCourseId,
    required String courseSubject,
    required int bundleVersionId,
    required int? existingCourseVersionId,
    required _SyncTransferSummary summary,
  }) async {
    final bundleService = CourseBundleService();
    File? bundleFile;
    try {
      final targetPath = await bundleService.createTempBundlePath(
        label: courseSubject,
      );
      bundleFile = await _api.downloadBundleToFile(
        bundleVersionId: bundleVersionId,
        targetPath: targetPath,
      );
      await bundleService.validateBundleForImport(bundleFile);
      final promptMetadata =
          await bundleService.readPromptMetadataFromBundleFile(bundleFile);
      final folderPath = await bundleService.extractBundleFromFile(
        bundleFile: bundleFile,
        courseName: courseSubject,
      );
      final preview = await _courseService.previewCourseLoad(
        folderPath: folderPath,
        courseVersionId: existingCourseVersionId,
        courseNameOverride: courseSubject,
      );
      if (!preview.success) {
        throw StateError(preview.message);
      }
      final mode = existingCourseVersionId == null
          ? CourseReloadMode.fresh
          : CourseReloadMode.override;
      final result = await _courseService.applyCourseLoad(
        teacherId: currentUser.id,
        preview: preview,
        mode: mode,
      );
      if (!result.success || result.course == null) {
        throw StateError(result.message);
      }
      await _db.upsertCourseRemoteLink(
        courseVersionId: result.course!.id,
        remoteCourseId: remoteCourseId,
      );
      if (promptMetadata != null) {
        await _applyPromptMetadataForTeacher(
          currentUser: currentUser,
          metadata: promptMetadata,
          course: result.course!,
        );
      }
      final remoteHash =
          await bundleService.computeBundleSemanticHash(bundleFile);
      summary.downloaded.add(
        SyncTransferLogItem(
          direction: 'download',
          fileName: p.basename(bundleFile.path),
          sizeBytes: bundleFile.lengthSync(),
          courseSubject: courseSubject,
          remoteCourseId: remoteCourseId,
          bundleVersionId: bundleVersionId,
          hash: remoteHash,
          source: 'teacher_course_sync',
        ),
      );
      final now = DateTime.now().toUtc();
      await _secureStorage.writeInstalledCourseBundleVersion(
        remoteUserId: remoteUserId,
        remoteCourseId: remoteCourseId,
        versionId: bundleVersionId,
      );
      await _secureStorage.writeSyncItemState(
        remoteUserId: remoteUserId,
        domain: _syncDomainTeacherCourseUpload,
        scopeKey: _teacherCourseScopeKey(remoteCourseId),
        contentHash: remoteHash,
        lastChangedAt: now,
        lastSyncedAt: now,
      );
      return result.course!;
    } finally {
      if (bundleFile != null && bundleFile.existsSync()) {
        await bundleFile.delete();
      }
    }
  }

  Future<bool> _hasCachedCourseArtifacts(int courseVersionId) async {
    final manifest = await _courseArtifactService!.readCourseArtifacts(
      courseVersionId,
    );
    if (manifest == null) {
      return false;
    }
    return File(manifest.contentBundlePath).existsSync();
  }

  Future<void> _ensureCourseArtifacts(CourseVersion course) async {
    if (_courseArtifactService == null) {
      return;
    }
    if (await _hasCachedCourseArtifacts(course.id)) {
      return;
    }
    final sourcePath = (course.sourcePath ?? '').trim();
    if (sourcePath.isEmpty || !Directory(sourcePath).existsSync()) {
      throw StateError(
        'Cached course artifacts are missing for "${course.subject}", and '
        'the source folder is unavailable.',
      );
    }
    await _courseArtifactService.rebuildCourseArtifacts(
      courseVersionId: course.id,
      folderPath: sourcePath,
    );
  }

  Future<Map<String, dynamic>> _buildPromptBundleMetadata({
    required User teacher,
    required CourseVersion course,
    required int remoteCourseId,
  }) async {
    final courseKey = (course.sourcePath ?? '').trim();
    if (courseKey.isEmpty) {
      return <String, dynamic>{
        'schema': 'family_teacher_prompt_bundle_v1',
        'remote_course_id': remoteCourseId,
        'teacher_username': teacher.username,
        'prompt_templates': const <Map<String, dynamic>>[],
        'student_prompt_profiles': const <Map<String, dynamic>>[],
      };
    }

    final scopeTemplates = <PromptTemplate>[];
    final courseTemplates = await (_db.select(_db.promptTemplates)
          ..where((tbl) =>
              tbl.teacherId.equals(teacher.id) &
              tbl.isActive.equals(true) &
              tbl.courseKey.equals(courseKey))
          ..orderBy([
            (tbl) =>
                OrderingTerm(expression: tbl.createdAt, mode: OrderingMode.desc)
          ]))
        .get();
    scopeTemplates.addAll(courseTemplates);

    final dedupedByScope = <String, PromptTemplate>{};
    for (final template in scopeTemplates) {
      final key = [
        template.promptName,
        template.courseKey ?? '',
        template.studentId?.toString() ?? '',
      ].join('::');
      dedupedByScope.putIfAbsent(key, () => template);
    }

    final studentCache = <int, User?>{};
    final promptTemplatesPayload = <Map<String, dynamic>>[];
    for (final template in dedupedByScope.values) {
      final studentId = template.studentId;
      User? student;
      if (studentId != null) {
        student = studentCache[studentId];
        student ??= await _db.getUserById(studentId);
        studentCache[studentId] = student;
      }

      var scope = 'teacher';
      if (template.courseKey != null && template.studentId == null) {
        scope = 'course';
      } else if (template.courseKey != null && template.studentId != null) {
        scope = 'student';
      }

      promptTemplatesPayload.add({
        'prompt_name': template.promptName,
        'scope': scope,
        'content': template.content,
        'student_remote_user_id': student?.remoteUserId,
        'student_username': student?.username,
        'created_at': template.createdAt.toUtc().toIso8601String(),
      });
    }

    final profilesPayload = <Map<String, dynamic>>[];
    final courseProfile = await _db.getStudentPromptProfile(
      teacherId: teacher.id,
      courseKey: courseKey,
      studentId: null,
    );
    if (courseProfile != null) {
      profilesPayload.add(
        _profileToJson(courseProfile, scope: 'course'),
      );
    }

    final studentProfileRows = await (_db.select(_db.studentPromptProfiles)
          ..where((tbl) =>
              tbl.teacherId.equals(teacher.id) &
              tbl.courseKey.equals(courseKey) &
              tbl.studentId.isNotNull())
          ..orderBy([
            (tbl) => OrderingTerm(
                  expression: tbl.updatedAt,
                  mode: OrderingMode.desc,
                ),
            (tbl) => OrderingTerm(
                  expression: tbl.createdAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .get();

    final studentIds = <int>{};
    for (final row in studentProfileRows) {
      final studentId = row.studentId;
      if (studentId != null) {
        studentIds.add(studentId);
      }
    }

    for (final studentId in studentIds) {
      final profile = await _db.getStudentPromptProfile(
        teacherId: teacher.id,
        courseKey: courseKey,
        studentId: studentId,
      );
      if (profile == null) {
        continue;
      }
      var student = studentCache[studentId];
      student ??= await _db.getUserById(studentId);
      studentCache[studentId] = student;
      profilesPayload.add(
        _profileToJson(
          profile,
          scope: 'student',
          studentRemoteUserId: student?.remoteUserId,
          studentUsername: student?.username,
        ),
      );
    }

    return {
      'schema': 'family_teacher_prompt_bundle_v1',
      'remote_course_id': remoteCourseId,
      'teacher_username': teacher.username,
      'prompt_templates': promptTemplatesPayload,
      'student_prompt_profiles': profilesPayload,
    };
  }

  Map<String, dynamic> _profileToJson(
    StudentPromptProfile profile, {
    required String scope,
    int? studentRemoteUserId,
    String? studentUsername,
  }) {
    return {
      'scope': scope,
      'student_remote_user_id': studentRemoteUserId,
      'student_username': studentUsername,
      'grade_level': profile.gradeLevel,
      'reading_level': profile.readingLevel,
      'preferred_language': profile.preferredLanguage,
      'interests': profile.interests,
      'preferred_tone': profile.preferredTone,
      'preferred_pace': profile.preferredPace,
      'preferred_format': profile.preferredFormat,
      'support_notes': profile.supportNotes,
      'updated_at':
          (profile.updatedAt ?? profile.createdAt).toUtc().toIso8601String(),
    };
  }

  Future<void> _applyPromptMetadataForTeacher({
    required User currentUser,
    required Map<String, dynamic> metadata,
    required CourseVersion course,
  }) async {
    final schema = (metadata['schema'] as String?)?.trim() ?? '';
    if (schema != 'family_teacher_prompt_bundle_v1') {
      return;
    }
    final courseKey = course.sourcePath?.trim();
    if (courseKey == null || courseKey.isEmpty) {
      return;
    }

    await _db.transaction(() async {
      await (_db.update(_db.promptTemplates)
            ..where((tbl) =>
                tbl.teacherId.equals(currentUser.id) &
                tbl.courseKey.equals(courseKey)))
          .write(PromptTemplatesCompanion(isActive: Value(false)));
      await (_db.delete(_db.studentPromptProfiles)
            ..where((tbl) =>
                tbl.teacherId.equals(currentUser.id) &
                tbl.courseKey.equals(courseKey)))
          .go();
    });

    final promptTemplates = metadata['prompt_templates'];
    if (promptTemplates is List) {
      for (final item in promptTemplates) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final promptName = (item['prompt_name'] as String?)?.trim() ?? '';
        final content = (item['content'] as String?)?.trim() ?? '';
        final scope = (item['scope'] as String?)?.trim() ?? '';
        if (promptName.isEmpty || content.isEmpty) {
          continue;
        }

        String? scopeCourseKey;
        int? scopeStudentId;
        if (scope == 'course') {
          scopeCourseKey = courseKey;
          scopeStudentId = null;
        } else if (scope == 'student') {
          final targetRemoteUserId =
              (item['student_remote_user_id'] as num?)?.toInt() ?? 0;
          if (targetRemoteUserId <= 0) {
            continue;
          }
          final targetUsername =
              (item['student_username'] as String?)?.trim() ?? '';
          scopeCourseKey = courseKey;
          scopeStudentId =
              await _remoteStudentIdentity.resolveOrCreateLocalStudentId(
            db: _db,
            remoteStudentId: targetRemoteUserId,
            usernameHint: targetUsername,
            teacherId: currentUser.id,
          );
        } else {
          continue;
        }

        await _db.insertPromptTemplate(
          teacherId: currentUser.id,
          promptName: promptName,
          content: content,
          courseKey: scopeCourseKey,
          studentId: scopeStudentId,
        );
      }
    }

    final profiles = metadata['student_prompt_profiles'];
    if (profiles is List) {
      for (final item in profiles) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final scope = (item['scope'] as String?)?.trim() ?? '';
        String? scopeCourseKey;
        int? scopeStudentId;

        if (scope == 'course') {
          scopeCourseKey = courseKey;
          scopeStudentId = null;
        } else if (scope == 'student') {
          final targetRemoteUserId =
              (item['student_remote_user_id'] as num?)?.toInt() ?? 0;
          if (targetRemoteUserId <= 0) {
            continue;
          }
          final targetUsername =
              (item['student_username'] as String?)?.trim() ?? '';
          scopeCourseKey = courseKey;
          scopeStudentId =
              await _remoteStudentIdentity.resolveOrCreateLocalStudentId(
            db: _db,
            remoteStudentId: targetRemoteUserId,
            usernameHint: targetUsername,
            teacherId: currentUser.id,
          );
        } else {
          continue;
        }

        await _db.upsertStudentPromptProfile(
          teacherId: currentUser.id,
          courseKey: scopeCourseKey,
          studentId: scopeStudentId,
          gradeLevel: item['grade_level'] as String?,
          readingLevel: item['reading_level'] as String?,
          preferredLanguage: item['preferred_language'] as String?,
          interests: item['interests'] as String?,
          preferredTone: item['preferred_tone'] as String?,
          preferredPace: item['preferred_pace'] as String?,
          preferredFormat: item['preferred_format'] as String?,
          supportNotes: item['support_notes'] as String?,
        );
      }
    }

    _promptRepository.invalidatePromptCache();
  }

  String _teacherCourseScopeKey(int remoteCourseId) {
    return 'course:$remoteCourseId';
  }

  Future<void> _writeSyncListEtag({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
    required String? etag,
  }) async {
    final normalized = (etag ?? '').trim();
    if (normalized.isEmpty) {
      return;
    }
    await _secureStorage.writeSyncListEtag(
      remoteUserId: remoteUserId,
      domain: domain,
      scopeKey: scopeKey,
      etag: normalized,
    );
  }

  CourseVersion? _findLocalCourseCandidate({
    required List<CourseVersion> localCourses,
    required Map<int, int?> localRemoteIdByCourseVersion,
    required String targetSubject,
  }) {
    final normalizedTarget =
        _normalizeCourseName(_stripVersionSuffix(targetSubject));
    final candidates = localCourses.where((course) {
      if ((localRemoteIdByCourseVersion[course.id] ?? 0) > 0) {
        return false;
      }
      final normalizedCourse =
          _normalizeCourseName(_stripVersionSuffix(course.subject));
      return normalizedCourse == normalizedTarget;
    }).toList();
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort((left, right) {
      final leftSuffix = _hasVersionSuffix(left.subject) ? 1 : 0;
      final rightSuffix = _hasVersionSuffix(right.subject) ? 1 : 0;
      if (leftSuffix != rightSuffix) {
        return leftSuffix - rightSuffix;
      }
      final leftHasSource = ((left.sourcePath ?? '').trim().isNotEmpty) ? 0 : 1;
      final rightHasSource =
          ((right.sourcePath ?? '').trim().isNotEmpty) ? 0 : 1;
      if (leftHasSource != rightHasSource) {
        return leftHasSource - rightHasSource;
      }
      return left.id - right.id;
    });
    return candidates.first;
  }

  Future<void> _cleanupTeacherLocalDuplicates(int teacherId) async {
    final localCourses = await _db.getCourseVersionsForTeacher(teacherId);
    final localRemoteIdByCourseVersion = <int, int?>{};
    for (final course in localCourses) {
      localRemoteIdByCourseVersion[course.id] = await _db.getRemoteCourseId(
        course.id,
      );
    }

    for (final course in localCourses) {
      final remoteId = localRemoteIdByCourseVersion[course.id];
      if (remoteId != null && remoteId > 0) {
        continue;
      }
      if (!_hasVersionSuffix(course.subject)) {
        continue;
      }
      final baseSubject = _stripVersionSuffix(course.subject);
      CourseVersion? canonical;
      for (final other in localCourses) {
        if (other.id == course.id) {
          continue;
        }
        final otherRemoteId = localRemoteIdByCourseVersion[other.id];
        if (otherRemoteId == null || otherRemoteId <= 0) {
          continue;
        }
        final otherBase = _stripVersionSuffix(other.subject);
        if (_normalizeCourseName(otherBase) ==
            _normalizeCourseName(baseSubject)) {
          canonical = other;
          break;
        }
      }
      if (canonical == null) {
        continue;
      }
      final assignments = await _db.getAssignmentsForCourse(course.id);
      for (final assignment in assignments) {
        await _db.migrateStudentCourseData(
          studentId: assignment.studentId,
          fromCourseVersionId: course.id,
          toCourseVersionId: canonical.id,
        );
      }
      await _cleanupCourseIfOrphaned(course.id);
    }
  }

  Future<void> _repairStudentStaleDuplicateCourses({
    required User currentUser,
    required List<EnrollmentSummary> enrollments,
  }) async {
    final canonicalCourseByBase = <String, int>{};
    for (final enrollment in enrollments) {
      final courseVersionId =
          await _db.getCourseVersionIdForRemoteCourse(enrollment.courseId);
      if (courseVersionId == null) {
        continue;
      }
      final baseKey = _normalizeCourseName(enrollment.courseSubject);
      canonicalCourseByBase[baseKey] = courseVersionId;
    }

    final assignedCourses =
        await _db.getAssignedCoursesForStudent(currentUser.id);
    for (final course in assignedCourses) {
      final remoteCourseId = await _db.getRemoteCourseId(course.id);
      if (remoteCourseId != null && remoteCourseId > 0) {
        continue;
      }
      if (!_hasVersionSuffix(course.subject)) {
        continue;
      }
      final baseKey = _normalizeCourseName(_stripVersionSuffix(course.subject));
      final canonicalCourseVersionId = canonicalCourseByBase[baseKey];
      if (canonicalCourseVersionId == null ||
          canonicalCourseVersionId == course.id) {
        continue;
      }
      await _db.migrateStudentCourseData(
        studentId: currentUser.id,
        fromCourseVersionId: course.id,
        toCourseVersionId: canonicalCourseVersionId,
      );
      await _cleanupCourseIfOrphaned(course.id);
    }
  }

  Future<void> _ensureCourseSubject({
    required int courseVersionId,
    required String expectedSubject,
  }) async {
    final normalizedExpected = expectedSubject.trim();
    if (normalizedExpected.isEmpty) {
      return;
    }
    final existing = await _db.getCourseVersionById(courseVersionId);
    if (existing == null) {
      return;
    }
    if (existing.subject.trim() == normalizedExpected) {
      return;
    }
    await _db.updateCourseVersionSubject(
      id: courseVersionId,
      subject: normalizedExpected,
    );
  }

  Future<void> _ensureCourseTeacher({
    required int courseVersionId,
    required int expectedTeacherId,
  }) async {
    final existing = await _db.getCourseVersionById(courseVersionId);
    if (existing == null) {
      return;
    }
    if (existing.teacherId == expectedTeacherId) {
      return;
    }
    await _db.updateCourseVersionTeacherId(
      id: courseVersionId,
      teacherId: expectedTeacherId,
    );
  }

  Future<void> _claimTeacherCourseOwnership({
    required User currentUser,
    required int courseVersionId,
    required List<CourseVersion> localCourses,
    required Map<int, int?> localRemoteIdByCourseVersion,
  }) async {
    final existing = await _db.getCourseVersionById(courseVersionId);
    if (existing == null) {
      return;
    }
    if (existing.teacherId != currentUser.id) {
      final existingTeacher = await _db.getUserById(existing.teacherId);
      if (existingTeacher != null && existingTeacher.role == 'teacher') {
        await _db.mergeUsers(
          keepUserId: currentUser.id,
          removeUserId: existingTeacher.id,
        );
      } else {
        await _db.updateCourseVersionTeacherId(
          id: courseVersionId,
          teacherId: currentUser.id,
        );
      }
    }
    final refreshed = await _db.getCourseVersionById(courseVersionId);
    if (refreshed == null) {
      return;
    }
    final assignments = await _db.getAssignmentsForCourse(refreshed.id);
    for (final assignment in assignments) {
      await _db.updateStudentTeacherId(
        studentId: assignment.studentId,
        teacherId: currentUser.id,
      );
    }
    final existingIndex = localCourses.indexWhere((course) {
      return course.id == refreshed.id;
    });
    if (existingIndex >= 0) {
      localCourses[existingIndex] = refreshed;
    } else {
      localCourses.add(refreshed);
    }
    localRemoteIdByCourseVersion[refreshed.id] = await _db.getRemoteCourseId(
      refreshed.id,
    );
  }

  String _normalizeCourseName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _hasVersionSuffix(String value) {
    return _versionSuffixPattern.hasMatch(value.trim());
  }

  String _stripVersionSuffix(String value) {
    final trimmed = value.trim();
    return trimmed.replaceFirst(_versionSuffixPattern, '');
  }

  Future<void> _appendSyncSummary({
    required User currentUser,
    required _SyncTransferSummary summary,
  }) async {
    if (_syncLogRepository == null) {
      return;
    }
    await _syncLogRepository.appendSummary(
      domain: summary.domain,
      actorRole: currentUser.role,
      actorUserId: currentUser.id,
      uploaded: summary.uploaded,
      downloaded: summary.downloaded,
    );
  }
}

class _PreparedTeacherCourseBundle {
  _PreparedTeacherCourseBundle({
    required this.bundleFile,
    required this.hash,
  });

  final File bundleFile;
  final String hash;
}

class _ResolvedRemoteBundleInfo {
  const _ResolvedRemoteBundleInfo({
    required this.bundleVersionId,
    required this.hash,
  });

  final int bundleVersionId;
  final String hash;
}

class _ResolvedCourseSyncState {
  const _ResolvedCourseSyncState({
    required this.courseVersionId,
    required this.installedVersion,
    required this.localCourse,
    required this.canBuildLocalBundle,
  });

  final int? courseVersionId;
  final int? installedVersion;
  final CourseVersion? localCourse;
  final bool canBuildLocalBundle;
}

class _SyncTransferSummary {
  _SyncTransferSummary({required this.domain});

  final String domain;
  final List<SyncTransferLogItem> uploaded = <SyncTransferLogItem>[];
  final List<SyncTransferLogItem> downloaded = <SyncTransferLogItem>[];
}
