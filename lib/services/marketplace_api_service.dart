import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../constants.dart';
import 'secure_storage_service.dart';

class MarketplaceApiException implements Exception {
  MarketplaceApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class MarketplaceListResult<T> {
  MarketplaceListResult({
    required this.items,
    required this.etag,
    required this.notModified,
  });

  final List<T> items;
  final String? etag;
  final bool notModified;
}

class SubjectLabelSummary {
  SubjectLabelSummary({
    required this.subjectLabelId,
    required this.slug,
    required this.name,
    required this.isActive,
  });

  final int subjectLabelId;
  final String slug;
  final String name;
  final bool isActive;

  factory SubjectLabelSummary.fromJson(Map<String, dynamic> json) {
    return SubjectLabelSummary(
      subjectLabelId: (json['subject_label_id'] as num?)?.toInt() ?? 0,
      slug: (json['slug'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}

List<SubjectLabelSummary> _decodeSubjectLabelsList(dynamic raw) {
  if (raw is! List) {
    return const <SubjectLabelSummary>[];
  }
  return raw
      .whereType<Map<String, dynamic>>()
      .map(SubjectLabelSummary.fromJson)
      .toList();
}

class CatalogCourse {
  CatalogCourse({
    required this.courseId,
    required this.subject,
    required this.grade,
    required this.description,
    required this.teacherId,
    required this.teacherName,
    required this.teacherAvatarUrl,
    required this.visibility,
    required this.publishedAt,
    required this.latestBundleVersionId,
    this.subjectLabels = const <SubjectLabelSummary>[],
  });

  final int courseId;
  final String subject;
  final String grade;
  final String description;
  final int teacherId;
  final String teacherName;
  final String teacherAvatarUrl;
  final String visibility;
  final String publishedAt;
  final int? latestBundleVersionId;
  final List<SubjectLabelSummary> subjectLabels;

  factory CatalogCourse.fromJson(Map<String, dynamic> json) {
    return CatalogCourse(
      courseId: (json['course_id'] as num?)?.toInt() ?? 0,
      subject: (json['subject'] as String?) ?? '',
      grade: (json['grade'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      teacherId: (json['teacher_id'] as num?)?.toInt() ?? 0,
      teacherName: (json['teacher_name'] as String?) ?? '',
      teacherAvatarUrl: (json['teacher_avatar_url'] as String?) ?? '',
      visibility: (json['visibility'] as String?) ?? '',
      publishedAt: (json['published_at'] as String?) ?? '',
      latestBundleVersionId:
          (json['latest_bundle_version_id'] as num?)?.toInt(),
      subjectLabels: _decodeSubjectLabelsList(json['subject_labels']),
    );
  }
}

class EnrollmentRequestSummary {
  EnrollmentRequestSummary({
    required this.requestId,
    required this.courseId,
    required this.status,
    required this.message,
    required this.createdAt,
    required this.resolvedAt,
    required this.courseSubject,
    required this.teacherId,
    required this.teacherName,
  });

  final int requestId;
  final int courseId;
  final String status;
  final String message;
  final String createdAt;
  final String resolvedAt;
  final String courseSubject;
  final int teacherId;
  final String teacherName;

  factory EnrollmentRequestSummary.fromJson(Map<String, dynamic> json) {
    return EnrollmentRequestSummary(
      requestId: (json['request_id'] as num?)?.toInt() ?? 0,
      courseId: (json['course_id'] as num?)?.toInt() ?? 0,
      status: (json['status'] as String?) ?? '',
      message: (json['message'] as String?) ?? '',
      createdAt: (json['created_at'] as String?) ?? '',
      resolvedAt: (json['resolved_at'] as String?) ?? '',
      courseSubject: (json['course_subject'] as String?) ?? '',
      teacherId: (json['teacher_id'] as num?)?.toInt() ?? 0,
      teacherName: (json['teacher_name'] as String?) ?? '',
    );
  }
}

class StudentQuitRequestSummary {
  StudentQuitRequestSummary({
    required this.requestId,
    required this.courseId,
    required this.status,
    required this.reason,
    required this.createdAt,
    required this.resolvedAt,
    required this.courseSubject,
    required this.teacherId,
    required this.teacherName,
  });

  final int requestId;
  final int courseId;
  final String status;
  final String reason;
  final String createdAt;
  final String resolvedAt;
  final String courseSubject;
  final int teacherId;
  final String teacherName;

  factory StudentQuitRequestSummary.fromJson(Map<String, dynamic> json) {
    return StudentQuitRequestSummary(
      requestId: (json['request_id'] as num?)?.toInt() ?? 0,
      courseId: (json['course_id'] as num?)?.toInt() ?? 0,
      status: (json['status'] as String?) ?? '',
      reason: (json['reason'] as String?) ?? '',
      createdAt: (json['created_at'] as String?) ?? '',
      resolvedAt: (json['resolved_at'] as String?) ?? '',
      courseSubject: (json['course_subject'] as String?) ?? '',
      teacherId: (json['teacher_id'] as num?)?.toInt() ?? 0,
      teacherName: (json['teacher_name'] as String?) ?? '',
    );
  }
}

class EnrollmentSummary {
  EnrollmentSummary({
    required this.enrollmentId,
    required this.courseId,
    required this.teacherId,
    required this.status,
    required this.assignedAt,
    required this.courseSubject,
    required this.teacherName,
    required this.latestBundleVersionId,
    this.latestBundleHash = '',
  });

  final int enrollmentId;
  final int courseId;
  final int teacherId;
  final String status;
  final String assignedAt;
  final String courseSubject;
  final String teacherName;
  final int? latestBundleVersionId;
  final String latestBundleHash;

  factory EnrollmentSummary.fromJson(Map<String, dynamic> json) {
    return EnrollmentSummary(
      enrollmentId: (json['enrollment_id'] as num?)?.toInt() ?? 0,
      courseId: (json['course_id'] as num?)?.toInt() ?? 0,
      teacherId: (json['teacher_id'] as num?)?.toInt() ?? 0,
      status: (json['status'] as String?) ?? '',
      assignedAt: (json['assigned_at'] as String?) ?? '',
      courseSubject: (json['course_subject'] as String?) ?? '',
      teacherName: (json['teacher_name'] as String?) ?? '',
      latestBundleVersionId:
          (json['latest_bundle_version_id'] as num?)?.toInt(),
      latestBundleHash: (json['latest_bundle_hash'] as String?) ?? '',
    );
  }
}

class TeacherRequestSummary {
  TeacherRequestSummary({
    required this.requestId,
    required this.courseId,
    required this.courseSubject,
    required this.studentId,
    required this.studentUsername,
    required this.message,
    required this.status,
    required this.createdAt,
  });

  final int requestId;
  final int courseId;
  final String courseSubject;
  final int studentId;
  final String studentUsername;
  final String message;
  final String status;
  final String createdAt;

  factory TeacherRequestSummary.fromJson(Map<String, dynamic> json) {
    return TeacherRequestSummary(
      requestId: (json['request_id'] as num?)?.toInt() ?? 0,
      courseId: (json['course_id'] as num?)?.toInt() ?? 0,
      courseSubject: (json['course_subject'] as String?) ?? '',
      studentId: (json['student_id'] as num?)?.toInt() ?? 0,
      studentUsername: (json['student_username'] as String?) ?? '',
      message: (json['message'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      createdAt: (json['created_at'] as String?) ?? '',
    );
  }
}

class TeacherQuitRequestSummary {
  TeacherQuitRequestSummary({
    required this.requestId,
    required this.courseId,
    required this.courseSubject,
    required this.studentId,
    required this.studentUsername,
    required this.reason,
    required this.status,
    required this.createdAt,
  });

  final int requestId;
  final int courseId;
  final String courseSubject;
  final int studentId;
  final String studentUsername;
  final String reason;
  final String status;
  final String createdAt;

  factory TeacherQuitRequestSummary.fromJson(Map<String, dynamic> json) {
    return TeacherQuitRequestSummary(
      requestId: (json['request_id'] as num?)?.toInt() ?? 0,
      courseId: (json['course_id'] as num?)?.toInt() ?? 0,
      courseSubject: (json['course_subject'] as String?) ?? '',
      studentId: (json['student_id'] as num?)?.toInt() ?? 0,
      studentUsername: (json['student_username'] as String?) ?? '',
      reason: (json['reason'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      createdAt: (json['created_at'] as String?) ?? '',
    );
  }
}

class EnrollmentDeletionEvent {
  EnrollmentDeletionEvent({
    required this.eventId,
    required this.studentId,
    required this.teacherUserId,
    required this.courseId,
    required this.reason,
    required this.createdAt,
  });

  final int eventId;
  final int studentId;
  final int teacherUserId;
  final int courseId;
  final String reason;
  final String createdAt;

  factory EnrollmentDeletionEvent.fromJson(Map<String, dynamic> json) {
    return EnrollmentDeletionEvent(
      eventId: (json['event_id'] as num?)?.toInt() ?? 0,
      studentId: (json['student_id'] as num?)?.toInt() ?? 0,
      teacherUserId: (json['teacher_user_id'] as num?)?.toInt() ?? 0,
      courseId: (json['course_id'] as num?)?.toInt() ?? 0,
      reason: (json['reason'] as String?) ?? '',
      createdAt: (json['created_at'] as String?) ?? '',
    );
  }
}

class TeacherCourseSummary {
  TeacherCourseSummary({
    required this.courseId,
    required this.subject,
    required this.grade,
    required this.description,
    required this.visibility,
    this.approvalStatus = '',
    required this.publishedAt,
    required this.latestBundleVersionId,
    this.latestBundleHash = '',
    required this.status,
    this.subjectLabels = const <SubjectLabelSummary>[],
  });

  final int courseId;
  final String subject;
  final String grade;
  final String description;
  final String visibility;
  final String approvalStatus;
  final String publishedAt;
  final int? latestBundleVersionId;
  final String latestBundleHash;
  final String status;
  final List<SubjectLabelSummary> subjectLabels;

  factory TeacherCourseSummary.fromJson(Map<String, dynamic> json) {
    return TeacherCourseSummary(
      courseId: (json['course_id'] as num?)?.toInt() ?? 0,
      subject: (json['subject'] as String?) ?? '',
      grade: (json['grade'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      visibility: (json['visibility'] as String?) ?? '',
      approvalStatus: (json['approval_status'] as String?) ?? '',
      publishedAt: (json['published_at'] as String?) ?? '',
      latestBundleVersionId:
          (json['latest_bundle_version_id'] as num?)?.toInt(),
      latestBundleHash: (json['latest_bundle_hash'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      subjectLabels: _decodeSubjectLabelsList(json['subject_labels']),
    );
  }
}

class AdminUserSummary {
  AdminUserSummary({
    required this.userId,
    required this.username,
    required this.email,
    required this.role,
    required this.teacherId,
    required this.teacherStatus,
    required this.teacherSubjectLabels,
  });

  final int userId;
  final String username;
  final String email;
  final String role;
  final int? teacherId;
  final String teacherStatus;
  final List<SubjectLabelSummary> teacherSubjectLabels;

  factory AdminUserSummary.fromJson(Map<String, dynamic> json) {
    return AdminUserSummary(
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      username: (json['username'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      role: (json['role'] as String?) ?? '',
      teacherId: (json['teacher_id'] as num?)?.toInt(),
      teacherStatus: (json['teacher_status'] as String?) ?? '',
      teacherSubjectLabels:
          _decodeSubjectLabelsList(json['teacher_subject_labels']),
    );
  }
}

class SubjectAdminAssignmentSummary {
  SubjectAdminAssignmentSummary({
    required this.teacherId,
    required this.userId,
    required this.username,
  });

  final int teacherId;
  final int userId;
  final String username;

  factory SubjectAdminAssignmentSummary.fromJson(Map<String, dynamic> json) {
    return SubjectAdminAssignmentSummary(
      teacherId: (json['teacher_id'] as num?)?.toInt() ?? 0,
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      username: (json['username'] as String?) ?? '',
    );
  }
}

class AdminSubjectLabelSummary {
  AdminSubjectLabelSummary({
    required this.subjectLabelId,
    required this.slug,
    required this.name,
    required this.isActive,
    required this.subjectAdmins,
  });

  final int subjectLabelId;
  final String slug;
  final String name;
  final bool isActive;
  final List<SubjectAdminAssignmentSummary> subjectAdmins;

  factory AdminSubjectLabelSummary.fromJson(Map<String, dynamic> json) {
    final rawAdmins = json['subject_admins'];
    final admins = rawAdmins is List
        ? rawAdmins
            .whereType<Map<String, dynamic>>()
            .map(SubjectAdminAssignmentSummary.fromJson)
            .toList()
        : <SubjectAdminAssignmentSummary>[];
    return AdminSubjectLabelSummary(
      subjectLabelId: (json['subject_label_id'] as num?)?.toInt() ?? 0,
      slug: (json['slug'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      isActive: (json['is_active'] as bool?) ?? true,
      subjectAdmins: admins,
    );
  }
}

class TeacherRegistrationApprovalRequest {
  TeacherRegistrationApprovalRequest({
    required this.requestId,
    required this.userId,
    required this.teacherId,
    required this.username,
    required this.displayName,
    required this.status,
    required this.createdAt,
    required this.subjectLabels,
  });

  final int requestId;
  final int userId;
  final int teacherId;
  final String username;
  final String displayName;
  final String status;
  final String createdAt;
  final List<SubjectLabelSummary> subjectLabels;

  factory TeacherRegistrationApprovalRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    return TeacherRegistrationApprovalRequest(
      requestId: (json['request_id'] as num?)?.toInt() ?? 0,
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      teacherId: (json['teacher_id'] as num?)?.toInt() ?? 0,
      username: (json['username'] as String?) ?? '',
      displayName: (json['display_name'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      createdAt: (json['created_at'] as String?) ?? '',
      subjectLabels: _decodeSubjectLabelsList(json['subject_labels']),
    );
  }
}

class CourseUploadApprovalRequest {
  CourseUploadApprovalRequest({
    required this.requestId,
    required this.courseId,
    required this.bundleId,
    required this.bundleVersionId,
    required this.courseSubject,
    required this.teacherId,
    required this.teacherName,
    required this.status,
    required this.requestedVisibility,
    required this.createdAt,
    required this.subjectLabels,
  });

  final int requestId;
  final int courseId;
  final int bundleId;
  final int bundleVersionId;
  final String courseSubject;
  final int teacherId;
  final String teacherName;
  final String status;
  final String requestedVisibility;
  final String createdAt;
  final List<SubjectLabelSummary> subjectLabels;

  factory CourseUploadApprovalRequest.fromJson(Map<String, dynamic> json) {
    return CourseUploadApprovalRequest(
      requestId: (json['request_id'] as num?)?.toInt() ?? 0,
      courseId: (json['course_id'] as num?)?.toInt() ?? 0,
      bundleId: (json['bundle_id'] as num?)?.toInt() ?? 0,
      bundleVersionId: (json['bundle_version_id'] as num?)?.toInt() ?? 0,
      courseSubject: (json['course_subject'] as String?) ?? '',
      teacherId: (json['teacher_id'] as num?)?.toInt() ?? 0,
      teacherName: (json['teacher_name'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      requestedVisibility: (json['requested_visibility'] as String?) ?? '',
      createdAt: (json['created_at'] as String?) ?? '',
      subjectLabels: _decodeSubjectLabelsList(json['subject_labels']),
    );
  }
}

class TeacherBundleVersionSummary {
  TeacherBundleVersionSummary({
    required this.bundleVersionId,
    required this.bundleId,
    required this.version,
    required this.hash,
    required this.createdAt,
    required this.sizeBytes,
    required this.isLatest,
    required this.fileMissing,
  });

  final int bundleVersionId;
  final int bundleId;
  final int version;
  final String hash;
  final String createdAt;
  final int sizeBytes;
  final bool isLatest;
  final bool fileMissing;

  factory TeacherBundleVersionSummary.fromJson(Map<String, dynamic> json) {
    return TeacherBundleVersionSummary(
      bundleVersionId: (json['bundle_version_id'] as num?)?.toInt() ?? 0,
      bundleId: (json['bundle_id'] as num?)?.toInt() ?? 0,
      version: (json['version'] as num?)?.toInt() ?? 0,
      hash: (json['hash'] as String?) ?? '',
      createdAt: (json['created_at'] as String?) ?? '',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      isLatest: (json['is_latest'] as bool?) ?? false,
      fileMissing: (json['file_missing'] as bool?) ?? false,
    );
  }
}

class LatestCourseBundleInfo {
  LatestCourseBundleInfo({
    required this.courseId,
    required this.bundleId,
    required this.bundleVersionId,
    required this.version,
    required this.hash,
    required this.fileMissing,
  });

  final int courseId;
  final int bundleId;
  final int bundleVersionId;
  final int version;
  final String hash;
  final bool fileMissing;

  factory LatestCourseBundleInfo.fromJson(Map<String, dynamic> json) {
    return LatestCourseBundleInfo(
      courseId: (json['course_id'] as num?)?.toInt() ?? 0,
      bundleId: (json['bundle_id'] as num?)?.toInt() ?? 0,
      bundleVersionId: (json['bundle_version_id'] as num?)?.toInt() ?? 0,
      version: (json['version'] as num?)?.toInt() ?? 0,
      hash: (json['hash'] as String?) ?? '',
      fileMissing: (json['file_missing'] as bool?) ?? false,
    );
  }
}

class EnsureBundleResult {
  EnsureBundleResult({
    required this.bundleId,
    required this.courseId,
  });

  final int bundleId;
  final int courseId;
}

class MarketplaceApiService {
  MarketplaceApiService({
    required SecureStorageService secureStorage,
    String? baseUrl,
    http.Client? client,
  })  : _secureStorage = secureStorage,
        _baseUrl = _normalizeBaseUrl(baseUrl ?? kAuthBaseUrl),
        _client = client ?? _buildClient(kAuthAllowInsecureTls);

  final SecureStorageService _secureStorage;
  final String _baseUrl;
  final http.Client _client;

  Future<List<CatalogCourse>> listCourses({
    String? query,
    List<int> subjectLabelIds = const <int>[],
  }) async {
    final params = <String, String>{};
    if ((query ?? '').trim().isNotEmpty) {
      params['q'] = query!.trim();
    }
    final normalizedLabelIds = subjectLabelIds.where((id) => id > 0).toList();
    if (normalizedLabelIds.isNotEmpty) {
      params['subject_label_ids'] = normalizedLabelIds.join(',');
    }
    final response = await _get('/api/catalog/courses', params: params);
    return _decodeList(response, (json) => CatalogCourse.fromJson(json));
  }

  Future<List<SubjectLabelSummary>> listSubjectLabels() async {
    final response = await _getPublic('/api/subject-labels');
    return _decodeList(response, (json) => SubjectLabelSummary.fromJson(json));
  }

  Future<List<EnrollmentRequestSummary>> listStudentRequests() async {
    final response = await _get('/api/enrollment-requests');
    return _decodeList(
      response,
      (json) => EnrollmentRequestSummary.fromJson(json),
    );
  }

  Future<List<EnrollmentSummary>> listEnrollments() async {
    final result = await listEnrollmentsDelta();
    return result.items;
  }

  Future<MarketplaceListResult<EnrollmentSummary>> listEnrollmentsDelta({
    String? ifNoneMatch,
  }) async {
    final response = await _getResponse(
      '/api/enrollments',
      ifNoneMatch: ifNoneMatch,
    );
    if (response.statusCode == 304) {
      return MarketplaceListResult<EnrollmentSummary>(
        items: const <EnrollmentSummary>[],
        etag: response.headers['etag'],
        notModified: true,
      );
    }
    final decoded = _decodeResponse(response);
    return MarketplaceListResult<EnrollmentSummary>(
      items: _decodeList(
        decoded,
        (json) => EnrollmentSummary.fromJson(json),
      ),
      etag: response.headers['etag'],
      notModified: false,
    );
  }

  Future<List<StudentQuitRequestSummary>> listStudentQuitRequests() async {
    try {
      final response = await _get('/api/enrollments/quit-requests');
      return _decodeList(
        response,
        (json) => StudentQuitRequestSummary.fromJson(json),
      );
    } on MarketplaceApiException catch (error) {
      if (error.statusCode == 404) {
        return [];
      }
      rethrow;
    }
  }

  Future<void> createEnrollmentRequest({
    required int courseId,
    String? message,
  }) async {
    await _post('/api/enrollment-requests', {
      'course_id': courseId,
      'message': message ?? '',
    });
  }

  Future<void> createQuitRequest({
    required int enrollmentId,
    String? reason,
  }) async {
    await _post('/api/enrollments/$enrollmentId/quit-request', {
      'reason': reason ?? '',
    });
  }

  Future<List<TeacherRequestSummary>> listTeacherRequests() async {
    final response = await _get('/api/teacher/enrollment-requests');
    return _decodeList(
      response,
      (json) => TeacherRequestSummary.fromJson(json),
    );
  }

  Future<List<TeacherQuitRequestSummary>> listTeacherQuitRequests() async {
    final response = await _get('/api/teacher/quit-requests');
    return _decodeList(
      response,
      (json) => TeacherQuitRequestSummary.fromJson(json),
    );
  }

  Future<void> approveRequest(int requestId) async {
    await _post('/api/teacher/enrollment-requests/$requestId/approve', {});
  }

  Future<void> rejectRequest(int requestId) async {
    await _post('/api/teacher/enrollment-requests/$requestId/reject', {});
  }

  Future<void> approveQuitRequest(int requestId) async {
    await _post('/api/teacher/quit-requests/$requestId/approve', {});
  }

  Future<void> rejectQuitRequest(int requestId) async {
    await _post('/api/teacher/quit-requests/$requestId/reject', {});
  }

  Future<List<EnrollmentDeletionEvent>> listEnrollmentDeletionEvents({
    int? sinceId,
  }) async {
    final params = <String, String>{};
    if ((sinceId ?? 0) > 0) {
      params['since_id'] = sinceId.toString();
    }
    final response =
        await _get('/api/enrollments/deletion-events', params: params);
    return _decodeList(
      response,
      (json) => EnrollmentDeletionEvent.fromJson(json),
    );
  }

  Future<List<TeacherCourseSummary>> listTeacherCourses() async {
    final result = await listTeacherCoursesDelta();
    return result.items;
  }

  Future<MarketplaceListResult<TeacherCourseSummary>> listTeacherCoursesDelta({
    String? ifNoneMatch,
  }) async {
    final response = await _getResponse(
      '/api/teacher/courses',
      ifNoneMatch: ifNoneMatch,
    );
    if (response.statusCode == 304) {
      return MarketplaceListResult<TeacherCourseSummary>(
        items: const <TeacherCourseSummary>[],
        etag: response.headers['etag'],
        notModified: true,
      );
    }
    final decoded = _decodeResponse(response);
    return MarketplaceListResult<TeacherCourseSummary>(
      items: _decodeList(
        decoded,
        (json) => TeacherCourseSummary.fromJson(json),
      ),
      etag: response.headers['etag'],
      notModified: false,
    );
  }

  Future<TeacherCourseSummary> createTeacherCourse({
    required String subject,
    String? grade,
    String? description,
    List<int> subjectLabelIds = const <int>[],
  }) async {
    final response = await _post('/api/teacher/courses', {
      'subject': subject.trim(),
      'grade': grade?.trim() ?? '',
      'description': description?.trim() ?? '',
      'subject_label_ids': subjectLabelIds,
    });
    if (response is! Map<String, dynamic>) {
      throw MarketplaceApiException('Unexpected response format.');
    }
    return TeacherCourseSummary.fromJson(response);
  }

  Future<void> updateCourseVisibility({
    required int courseId,
    required String visibility,
  }) async {
    await _post('/api/teacher/courses/$courseId/publish', {
      'visibility': visibility,
    });
  }

  Future<TeacherCourseSummary> updateCourseSubjectLabels({
    required int courseId,
    required List<int> subjectLabelIds,
  }) async {
    final response =
        await _post('/api/teacher/courses/$courseId/subject-labels', {
      'subject_label_ids': subjectLabelIds,
    });
    if (response is! Map<String, dynamic>) {
      throw MarketplaceApiException('Unexpected response format.');
    }
    final refreshed = await listTeacherCourses();
    return refreshed.firstWhere(
      (course) => course.courseId == courseId,
      orElse: () => TeacherCourseSummary(
        courseId: courseId,
        subject: '',
        grade: '',
        description: '',
        visibility: 'private',
        publishedAt: '',
        latestBundleVersionId: null,
        status: 'updated',
        approvalStatus: '',
        subjectLabels: _decodeSubjectLabelsList(response['subject_labels']),
      ),
    );
  }

  Future<void> deleteTeacherCourse(int courseId) async {
    await _post('/api/teacher/courses/$courseId/delete', {});
  }

  Future<List<AdminUserSummary>> listAdminUsers() async {
    final response = await _get('/api/admin/users');
    return _decodeList(response, (json) => AdminUserSummary.fromJson(json));
  }

  Future<void> deleteAdminTeacher(int userId) async {
    await _post('/api/admin/users/$userId/delete', {});
  }

  Future<List<AdminSubjectLabelSummary>> listAdminSubjectLabels() async {
    final response = await _get('/api/admin/subject-labels');
    return _decodeList(
      response,
      (json) => AdminSubjectLabelSummary.fromJson(json),
    );
  }

  Future<void> createAdminSubjectLabel({
    required String name,
    bool isActive = true,
  }) async {
    await _post('/api/admin/subject-labels', {
      'name': name.trim(),
      'is_active': isActive,
    });
  }

  Future<void> updateAdminSubjectLabel({
    required int subjectLabelId,
    required String name,
    required bool isActive,
  }) async {
    await _post('/api/admin/subject-labels/$subjectLabelId', {
      'name': name.trim(),
      'is_active': isActive,
    });
  }

  Future<void> assignSubjectAdmin({
    required int subjectLabelId,
    required int teacherUserId,
  }) async {
    await _post('/api/admin/subject-labels/$subjectLabelId/subject-admins', {
      'teacher_user_id': teacherUserId,
    });
  }

  Future<void> removeSubjectAdmin({
    required int subjectLabelId,
    required int teacherUserId,
  }) async {
    await _post(
      '/api/admin/subject-labels/$subjectLabelId/subject-admins/$teacherUserId/delete',
      {},
    );
  }

  Future<List<TeacherRegistrationApprovalRequest>>
      listAdminTeacherRegistrationRequests() async {
    final response = await _get('/api/admin/teacher-registration-requests');
    return _decodeList(
      response,
      (json) => TeacherRegistrationApprovalRequest.fromJson(json),
    );
  }

  Future<void> approveAdminTeacherRegistration(int requestId) async {
    await _post(
        '/api/admin/teacher-registration-requests/$requestId/approve', {});
  }

  Future<void> rejectAdminTeacherRegistration(int requestId) async {
    await _post(
        '/api/admin/teacher-registration-requests/$requestId/reject', {});
  }

  Future<List<TeacherRegistrationApprovalRequest>>
      listSubjectAdminTeacherRegistrationRequests() async {
    final response =
        await _get('/api/subject-admin/teacher-registration-requests');
    return _decodeList(
      response,
      (json) => TeacherRegistrationApprovalRequest.fromJson(json),
    );
  }

  Future<void> approveSubjectAdminTeacherRegistration(int requestId) async {
    await _post(
        '/api/subject-admin/teacher-registration-requests/$requestId/approve',
        {});
  }

  Future<void> rejectSubjectAdminTeacherRegistration(int requestId) async {
    await _post(
        '/api/subject-admin/teacher-registration-requests/$requestId/reject',
        {});
  }

  Future<List<CourseUploadApprovalRequest>>
      listAdminCourseUploadRequests() async {
    final response = await _get('/api/admin/course-upload-requests');
    return _decodeList(
      response,
      (json) => CourseUploadApprovalRequest.fromJson(json),
    );
  }

  Future<void> approveAdminCourseUpload(int requestId) async {
    await _post('/api/admin/course-upload-requests/$requestId/approve', {});
  }

  Future<void> rejectAdminCourseUpload(int requestId) async {
    await _post('/api/admin/course-upload-requests/$requestId/reject', {});
  }

  Future<List<CourseUploadApprovalRequest>>
      listSubjectAdminCourseUploadRequests() async {
    final response = await _get('/api/subject-admin/course-upload-requests');
    return _decodeList(
      response,
      (json) => CourseUploadApprovalRequest.fromJson(json),
    );
  }

  Future<void> approveSubjectAdminCourseUpload(int requestId) async {
    await _post(
        '/api/subject-admin/course-upload-requests/$requestId/approve', {});
  }

  Future<void> rejectSubjectAdminCourseUpload(int requestId) async {
    await _post(
        '/api/subject-admin/course-upload-requests/$requestId/reject', {});
  }

  Future<EnsureBundleResult> ensureBundle(
    int courseId, {
    String? courseName,
  }) async {
    final params = <String, String>{};
    final normalizedName = (courseName ?? '').trim();
    if (normalizedName.isNotEmpty) {
      params['course_name'] = normalizedName;
    }
    final response = await _post(
      '/api/teacher/courses/$courseId/bundles',
      {},
      params: params,
    );
    if (response is Map<String, dynamic>) {
      final bundleId = (response['bundle_id'] as num?)?.toInt() ?? 0;
      final resolvedCourseId = (response['course_id'] as num?)?.toInt() ?? 0;
      if (bundleId > 0 && resolvedCourseId > 0) {
        return EnsureBundleResult(
          bundleId: bundleId,
          courseId: resolvedCourseId,
        );
      }
    }
    throw MarketplaceApiException('Unexpected response format.');
  }

  Future<List<TeacherBundleVersionSummary>> listTeacherBundleVersions(
    int courseId,
  ) async {
    final response =
        await _get('/api/teacher/courses/$courseId/bundle-versions');
    return _decodeList(
      response,
      (json) => TeacherBundleVersionSummary.fromJson(json),
    );
  }

  Future<LatestCourseBundleInfo> getLatestCourseBundleInfo(int courseId) async {
    final response = await _get(
      '/api/bundles/latest-info',
      params: <String, String>{'course_id': courseId.toString()},
    );
    if (response is! Map<String, dynamic>) {
      throw MarketplaceApiException('Unexpected response format.');
    }
    return LatestCourseBundleInfo.fromJson(response);
  }

  Future<void> deleteTeacherBundleVersion({
    required int courseId,
    required int bundleVersionId,
  }) async {
    await _post(
      '/api/teacher/courses/$courseId/bundle-versions/$bundleVersionId/delete',
      {},
    );
  }

  Future<Map<String, dynamic>> uploadBundle({
    required int bundleId,
    required String courseName,
    required File bundleFile,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/bundles/upload').replace(
      queryParameters: {
        'bundle_id': bundleId.toString(),
        'course_name': courseName.trim(),
      },
    );
    Future<http.StreamedResponse> send(String token) async {
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(await http.MultipartFile.fromPath(
        'bundle',
        bundleFile.path,
      ));
      try {
        return await _client.send(request);
      } on Exception catch (error) {
        throw MarketplaceApiException('Request failed: $error');
      }
    }

    var token = await _requireAccessToken();
    var streamed = await send(token);
    if (streamed.statusCode == 401 && await _refreshAccessToken()) {
      token = await _requireAccessToken();
      streamed = await send(token);
    }
    final response = await http.Response.fromStream(streamed);
    final decoded = _decodeResponse(response);
    if (decoded is! Map<String, dynamic>) {
      throw MarketplaceApiException('Unexpected response format.');
    }
    return decoded;
  }

  Future<File> downloadBundleToFile({
    required int bundleVersionId,
    required String targetPath,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/bundles/download').replace(
      queryParameters: {
        'bundle_version_id': bundleVersionId.toString(),
      },
    );
    Future<http.StreamedResponse> send(String token) async {
      final request = http.Request('GET', uri);
      request.headers['Authorization'] = 'Bearer $token';
      try {
        return await _client.send(request);
      } on Exception catch (error) {
        throw MarketplaceApiException('Request failed: $error');
      }
    }

    var token = await _requireAccessToken();
    var streamed = await send(token);
    if (streamed.statusCode == 401 && await _refreshAccessToken()) {
      await streamed.stream.drain();
      token = await _requireAccessToken();
      streamed = await send(token);
    }
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final body = await streamed.stream.bytesToString();
      throw MarketplaceApiException(
        _extractError(body) ?? 'Request failed.',
        statusCode: streamed.statusCode,
      );
    }
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    if (!file.existsSync()) {
      await file.create(recursive: true);
    }
    final sink = file.openWrite();
    var writtenBytes = 0;
    try {
      await for (final chunk in streamed.stream) {
        writtenBytes += chunk.length;
        sink.add(chunk);
      }
    } finally {
      await sink.close();
    }
    if (writtenBytes <= 0) {
      if (file.existsSync()) {
        await file.delete();
      }
      throw MarketplaceApiException(
        'Download returned empty body for bundle_version_id=$bundleVersionId.',
      );
    }
    return file;
  }

  Future<dynamic> _get(
    String path, {
    Map<String, String>? params,
  }) async {
    final response = await _getResponse(path, params: params);
    return _decodeResponse(response);
  }

  Future<dynamic> _getPublic(
    String path, {
    Map<String, String>? params,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: params);
    http.Response response;
    try {
      response = await _client.get(uri);
    } on Exception catch (error) {
      throw MarketplaceApiException('Request failed: $error');
    }
    return _decodeResponse(response);
  }

  Future<http.Response> _getResponse(
    String path, {
    Map<String, String>? params,
    String? ifNoneMatch,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: params);
    Future<http.Response> send(String token) async {
      final headers = _authHeaders(token);
      final etag = (ifNoneMatch ?? '').trim();
      if (etag.isNotEmpty) {
        headers['If-None-Match'] = etag;
      }
      try {
        return await _client.get(
          uri,
          headers: headers,
        );
      } on Exception catch (error) {
        throw MarketplaceApiException('Request failed: $error');
      }
    }

    var token = await _requireAccessToken();
    var response = await send(token);
    if (response.statusCode == 401 && await _refreshAccessToken()) {
      token = await _requireAccessToken();
      response = await send(token);
    }
    return response;
  }

  Future<dynamic> _post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? params,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: params);
    Future<http.Response> send(String token) async {
      try {
        return await _client.post(
          uri,
          headers: _authHeaders(token),
          body: jsonEncode(body),
        );
      } on Exception catch (error) {
        throw MarketplaceApiException('Request failed: $error');
      }
    }

    var token = await _requireAccessToken();
    var response = await send(token);
    if (response.statusCode == 401 && await _refreshAccessToken()) {
      token = await _requireAccessToken();
      response = await send(token);
    }
    return _decodeResponse(response);
  }

  Map<String, String> _authHeaders(String token) {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<String> _requireAccessToken() async {
    final token = await _secureStorage.readAuthAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw MarketplaceApiException('Missing auth token.');
    }
    return token.trim();
  }

  Future<bool> _refreshAccessToken() async {
    final refreshToken = await _secureStorage.readAuthRefreshToken();
    if (refreshToken == null || refreshToken.trim().isEmpty) {
      return false;
    }
    http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$_baseUrl/api/auth/refresh'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken.trim()}),
      );
    } on Exception catch (error) {
      throw MarketplaceApiException('Token refresh failed: $error');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 400 || response.statusCode == 401) {
        await _secureStorage.deleteAuthTokens();
        return false;
      }
      throw MarketplaceApiException(
        _extractError(response.body) ?? 'Token refresh failed.',
        statusCode: response.statusCode,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw MarketplaceApiException('Token refresh response invalid.');
    }
    final accessToken = (decoded['access_token'] as String?)?.trim() ?? '';
    final nextRefreshToken =
        (decoded['refresh_token'] as String?)?.trim() ?? '';
    if (accessToken.isEmpty || nextRefreshToken.isEmpty) {
      throw MarketplaceApiException('Token refresh response missing tokens.');
    }
    await _secureStorage.writeAuthTokens(
      accessToken: accessToken,
      refreshToken: nextRefreshToken,
    );
    return true;
  }

  dynamic _decodeResponse(http.Response response) {
    if (response.statusCode == 304) {
      return const <String, dynamic>{};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MarketplaceApiException(
        _extractError(response.body) ?? 'Request failed.',
        statusCode: response.statusCode,
      );
    }
    if (response.body.trim().isEmpty) {
      return {};
    }
    final decoded = jsonDecode(response.body);
    return decoded;
  }

  List<T> _decodeList<T>(
    dynamic decoded,
    T Function(Map<String, dynamic>) parser,
  ) {
    if (decoded is! List) {
      throw MarketplaceApiException('Unexpected response format.');
    }
    return decoded.whereType<Map<String, dynamic>>().map(parser).toList();
  }

  static http.Client _buildClient(bool allowInsecureTls) {
    if (!allowInsecureTls) {
      return http.Client();
    }
    final httpClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    return IOClient(httpClient);
  }

  static String _normalizeBaseUrl(String value) {
    var trimmed = value.trim();
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  static String? _extractError(String body) {
    if (body.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message'] ?? decoded['error'];
        if (message is String && message.trim().isNotEmpty) {
          return message;
        }
      }
    } catch (_) {
      return body.trim();
    }
    return body.trim();
  }
}
