import 'dart:io';

import '../db/app_database.dart';
import 'course_bundle_service.dart';
import 'course_service.dart';
import 'marketplace_api_service.dart';
import 'remote_teacher_identity_service.dart';
import 'secure_storage_service.dart';

class EnrollmentSyncService {
  EnrollmentSyncService({
    required AppDatabase db,
    required SecureStorageService secureStorage,
    required CourseService courseService,
    required MarketplaceApiService marketplaceApi,
  })  : _db = db,
        _secureStorage = secureStorage,
        _courseService = courseService,
        _api = marketplaceApi;

  final AppDatabase _db;
  final SecureStorageService _secureStorage;
  final CourseService _courseService;
  final MarketplaceApiService _api;
  final RemoteTeacherIdentityService _remoteTeacherIdentity =
      const RemoteTeacherIdentityService();
  bool _syncing = false;
  static final RegExp _versionSuffixPattern = RegExp(r'_(\d{10,})$');
  static const Duration _syncMinInterval = Duration(seconds: 60);
  static const String _syncDomainDeletionEvents = 'enrollment_sync_deletions';
  static const String _syncDomainStudentEnrollments = 'enrollment_sync_student';
  static const String _syncDomainTeacherCourses = 'enrollment_sync_teacher';
  static const String _syncScopeEnrollments = 'enrollments';
  static const String _syncScopeTeacherCourses = 'teacher_courses';

  Future<void> syncIfReady({required User currentUser}) async {
    if (_syncing) {
      return;
    }
    final remoteUserId = currentUser.remoteUserId;
    if (remoteUserId == null || remoteUserId <= 0) {
      return;
    }
    final nowUtc = DateTime.now().toUtc();
    _syncing = true;
    try {
      if (currentUser.role == 'student') {
        await _autoApproveLegacyCoursesWithoutTeacher(currentUser.id);
      }
      await _runCategoryIfDue(
        remoteUserId: remoteUserId,
        domain: _syncDomainDeletionEvents,
        nowUtc: nowUtc,
        action: () => _applyDeletionEvents(currentUser, remoteUserId),
      );
      if (currentUser.role == 'teacher') {
        await _runCategoryIfDue(
          remoteUserId: remoteUserId,
          domain: _syncDomainTeacherCourses,
          nowUtc: nowUtc,
          action: () => _syncTeacherCourses(
            currentUser: currentUser,
            remoteUserId: remoteUserId,
          ),
        );
      } else {
        await _runCategoryIfDue(
          remoteUserId: remoteUserId,
          domain: _syncDomainStudentEnrollments,
          nowUtc: nowUtc,
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
              );
            }
          },
        );
      }
    } finally {
      _syncing = false;
    }
  }

  Future<void> _runCategoryIfDue({
    required int remoteUserId,
    required String domain,
    required DateTime nowUtc,
    required Future<void> Function() action,
  }) async {
    final lastRun = await _secureStorage.readSyncRunAt(
      remoteUserId: remoteUserId,
      domain: domain,
    );
    if (lastRun != null &&
        nowUtc.difference(lastRun.toUtc()) < _syncMinInterval) {
      return;
    }
    await action();
    await _secureStorage.writeSyncRunAt(
      remoteUserId: remoteUserId,
      domain: domain,
      runAt: nowUtc,
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
      final existingInstalledVersion =
          await _secureStorage.readInstalledCourseBundleVersion(
        remoteUserId: remoteUserId,
        remoteCourseId: enrollment.courseId,
      );
      var existingCourseVersionId =
          await _db.getCourseVersionIdForRemoteCourse(enrollment.courseId);
      if (existingCourseVersionId != null) {
        await _ensureCourseTeacher(
          courseVersionId: existingCourseVersionId,
          expectedTeacherId: localTeacherId,
        );
      }
      final shouldDownload = existingCourseVersionId == null ||
          existingInstalledVersion == null ||
          latestBundleVersionId > existingInstalledVersion;
      if (shouldDownload) {
        final imported = await _downloadAndImportCourse(
          enrollment: enrollment,
          bundleVersionId: latestBundleVersionId,
          existingCourseVersionId: existingCourseVersionId,
          localTeacherId: localTeacherId,
        );
        existingCourseVersionId = imported.id;
      }
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
      await _secureStorage.writeInstalledCourseBundleVersion(
        remoteUserId: remoteUserId,
        remoteCourseId: enrollment.courseId,
        versionId: latestBundleVersionId,
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
  }) async {
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
      return;
    }
    final remoteCourses = result.items;
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
      await _ensureCourseSubject(
        courseVersionId: localCourseVersionId,
        expectedSubject: remoteCourse.subject,
      );
    }

    await _cleanupTeacherLocalDuplicates(currentUser.id);
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
}
