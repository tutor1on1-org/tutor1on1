import 'dart:io';

import '../db/app_database.dart';
import 'marketplace_api_service.dart';

class ResolvedUploadTarget {
  ResolvedUploadTarget({
    required this.remoteCourseId,
    required this.bundleId,
  });

  final int remoteCourseId;
  final int bundleId;
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
  }) async {
    final storedRemoteCourseId = await _db.getRemoteCourseId(courseVersionId);
    var remoteCourseId = storedRemoteCourseId;
    final teacherCourses = await _marketplaceApi.listTeacherCourses();
    final normalizedCourseName = _normalizeCourseName(courseSubject);
    TeacherCourseSummary? sameNameCourse;
    for (final remoteCourse in teacherCourses) {
      if (_normalizeCourseName(remoteCourse.subject) == normalizedCourseName) {
        sameNameCourse = remoteCourse;
        break;
      }
    }
    if (sameNameCourse != null) {
      remoteCourseId = sameNameCourse.courseId;
      if (storedRemoteCourseId != remoteCourseId) {
        await _db.upsertCourseRemoteLink(
          courseVersionId: courseVersionId,
          remoteCourseId: remoteCourseId,
        );
      }
    } else if (remoteCourseId != null && remoteCourseId > 0) {
      final remoteExists = teacherCourses
          .any((remoteCourse) => remoteCourse.courseId == remoteCourseId);
      if (!remoteExists) {
        remoteCourseId = null;
      }
    }
    if (remoteCourseId == null || remoteCourseId <= 0) {
      final created = await _marketplaceApi.createTeacherCourse(
        subject: courseSubject,
        grade: '',
        description: 'Uploaded from Family Teacher app.',
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
      );
    } on MarketplaceApiException catch (error) {
      if (error.statusCode != 404) {
        rethrow;
      }
      final created = await _marketplaceApi.createTeacherCourse(
        subject: courseSubject,
        grade: '',
        description: 'Uploaded from Family Teacher app.',
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
    await _marketplaceApi.updateCourseVisibility(
      courseId: target.remoteCourseId,
      visibility: visibility,
    );
    return uploadResponse;
  }

  String _normalizeCourseName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
