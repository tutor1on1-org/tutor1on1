import 'dart:io';

import '../db/app_database.dart';
import 'marketplace_api_service.dart';

class ResolvedUploadTarget {
  ResolvedUploadTarget({
    required this.remoteCourseId,
    required this.bundleId,
    required this.approvalStatus,
  });

  final int remoteCourseId;
  final int bundleId;
  final String approvalStatus;
}

class TeacherMarketplaceUploadService {
  TeacherMarketplaceUploadService({
    required AppDatabase db,
    required MarketplaceApiService marketplaceApi,
  })  : _db = db,
        _marketplaceApi = marketplaceApi;

  final AppDatabase _db;
  final MarketplaceApiService _marketplaceApi;

  Future<ResolvedUploadTarget> resolveUploadTarget({
    required int courseVersionId,
    required String courseSubject,
    required List<int> subjectLabelIds,
  }) async {
    final storedRemoteCourseId = await _db.getRemoteCourseId(courseVersionId);
    var remoteCourseId = storedRemoteCourseId;
    final teacherCourses = await _marketplaceApi.listTeacherCourses();
    final normalizedCourseName = _normalizeCourseName(courseSubject);
    TeacherCourseSummary? sameNameCourse;
    TeacherCourseSummary? resolvedCourse;
    for (final remoteCourse in teacherCourses) {
      if (_normalizeCourseName(remoteCourse.subject) == normalizedCourseName) {
        sameNameCourse = remoteCourse;
        break;
      }
    }
    if (sameNameCourse != null) {
      remoteCourseId = sameNameCourse.courseId;
      resolvedCourse = sameNameCourse;
      if (storedRemoteCourseId != remoteCourseId) {
        await _db.upsertCourseRemoteLink(
          courseVersionId: courseVersionId,
          remoteCourseId: remoteCourseId,
        );
      }
    } else if (remoteCourseId != null && remoteCourseId > 0) {
      final matchingById = teacherCourses
          .where((remoteCourse) => remoteCourse.courseId == remoteCourseId)
          .toList(growable: false);
      final remoteExists = matchingById.isNotEmpty;
      if (remoteExists) {
        resolvedCourse = matchingById.first;
      }
      if (!remoteExists) {
        remoteCourseId = null;
      }
    }
    if (remoteCourseId == null || remoteCourseId <= 0) {
      final created = await _marketplaceApi.createTeacherCourse(
        subject: courseSubject,
        grade: '',
        description: 'Uploaded from Family Teacher app.',
        subjectLabelIds: subjectLabelIds,
      );
      remoteCourseId = created.courseId;
      await _db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: remoteCourseId,
      );
    }

    try {
      final ensured = await _marketplaceApi.ensureBundle(
        remoteCourseId,
        courseName: courseSubject,
      );
      await _db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: ensured.courseId,
      );
      return ResolvedUploadTarget(
        remoteCourseId: ensured.courseId,
        bundleId: ensured.bundleId,
        approvalStatus: resolvedCourse?.approvalStatus ?? 'pending',
      );
    } on MarketplaceApiException catch (error) {
      if (error.statusCode != 404) {
        rethrow;
      }
      final created = await _marketplaceApi.createTeacherCourse(
        subject: courseSubject,
        grade: '',
        description: 'Uploaded from Family Teacher app.',
        subjectLabelIds: subjectLabelIds,
      );
      remoteCourseId = created.courseId;
      await _db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: remoteCourseId,
      );
      final ensured = await _marketplaceApi.ensureBundle(
        remoteCourseId,
        courseName: courseSubject,
      );
      await _db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: ensured.courseId,
      );
      return ResolvedUploadTarget(
        remoteCourseId: ensured.courseId,
        bundleId: ensured.bundleId,
        approvalStatus: created.approvalStatus,
      );
    }
  }

  Future<Map<String, dynamic>> uploadBundleAndPublish({
    required ResolvedUploadTarget target,
    required String courseSubject,
    required File bundleFile,
    String visibility = 'public',
  }) async {
    final uploadResponse = await _marketplaceApi.uploadBundle(
      bundleId: target.bundleId,
      courseName: courseSubject,
      bundleFile: bundleFile,
    );
    if (target.approvalStatus == 'approved') {
      await _marketplaceApi.updateCourseVisibility(
        courseId: target.remoteCourseId,
        visibility: visibility,
      );
      uploadResponse['approval_status'] = 'approved';
    } else {
      uploadResponse['approval_status'] = 'pending';
    }
    return uploadResponse;
  }

  String _normalizeCourseName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
