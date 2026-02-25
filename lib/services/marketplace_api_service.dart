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

class EnrollmentSummary {
  EnrollmentSummary({
    required this.enrollmentId,
    required this.courseId,
    required this.teacherId,
    required this.status,
    required this.assignedAt,
    required this.courseSubject,
    required this.teacherName,
  });

  final int enrollmentId;
  final int courseId;
  final int teacherId;
  final String status;
  final String assignedAt;
  final String courseSubject;
  final String teacherName;

  factory EnrollmentSummary.fromJson(Map<String, dynamic> json) {
    return EnrollmentSummary(
      enrollmentId: (json['enrollment_id'] as num?)?.toInt() ?? 0,
      courseId: (json['course_id'] as num?)?.toInt() ?? 0,
      teacherId: (json['teacher_id'] as num?)?.toInt() ?? 0,
      status: (json['status'] as String?) ?? '',
      assignedAt: (json['assigned_at'] as String?) ?? '',
      courseSubject: (json['course_subject'] as String?) ?? '',
      teacherName: (json['teacher_name'] as String?) ?? '',
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

class TeacherCourseSummary {
  TeacherCourseSummary({
    required this.courseId,
    required this.subject,
    required this.grade,
    required this.description,
    required this.visibility,
    required this.publishedAt,
    required this.latestBundleVersionId,
  });

  final int courseId;
  final String subject;
  final String grade;
  final String description;
  final String visibility;
  final String publishedAt;
  final int? latestBundleVersionId;

  factory TeacherCourseSummary.fromJson(Map<String, dynamic> json) {
    return TeacherCourseSummary(
      courseId: (json['course_id'] as num?)?.toInt() ?? 0,
      subject: (json['subject'] as String?) ?? '',
      grade: (json['grade'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      visibility: (json['visibility'] as String?) ?? '',
      publishedAt: (json['published_at'] as String?) ?? '',
      latestBundleVersionId:
          (json['latest_bundle_version_id'] as num?)?.toInt(),
    );
  }
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
  }) async {
    final params = <String, String>{};
    if ((query ?? '').trim().isNotEmpty) {
      params['q'] = query!.trim();
    }
    final response = await _get('/api/catalog/courses', params: params);
    return _decodeList(response, (json) => CatalogCourse.fromJson(json));
  }

  Future<List<EnrollmentRequestSummary>> listStudentRequests() async {
    final response = await _get('/api/enrollment-requests');
    return _decodeList(
      response,
      (json) => EnrollmentRequestSummary.fromJson(json),
    );
  }

  Future<List<EnrollmentSummary>> listEnrollments() async {
    final response = await _get('/api/enrollments');
    return _decodeList(
      response,
      (json) => EnrollmentSummary.fromJson(json),
    );
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

  Future<List<TeacherRequestSummary>> listTeacherRequests() async {
    final response = await _get('/api/teacher/enrollment-requests');
    return _decodeList(
      response,
      (json) => TeacherRequestSummary.fromJson(json),
    );
  }

  Future<void> approveRequest(int requestId) async {
    await _post('/api/teacher/enrollment-requests/$requestId/approve', {});
  }

  Future<void> rejectRequest(int requestId) async {
    await _post('/api/teacher/enrollment-requests/$requestId/reject', {});
  }

  Future<List<TeacherCourseSummary>> listTeacherCourses() async {
    final response = await _get('/api/teacher/courses');
    return _decodeList(
      response,
      (json) => TeacherCourseSummary.fromJson(json),
    );
  }

  Future<TeacherCourseSummary> createTeacherCourse({
    required String subject,
    String? grade,
    String? description,
  }) async {
    final response = await _post('/api/teacher/courses', {
      'subject': subject.trim(),
      'grade': grade?.trim() ?? '',
      'description': description?.trim() ?? '',
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

  Future<dynamic> _get(
    String path, {
    Map<String, String>? params,
  }) async {
    final token = await _requireAccessToken();
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: params);
    http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: _authHeaders(token),
      );
    } on Exception catch (error) {
      throw MarketplaceApiException('Request failed: $error');
    }
    return _decodeResponse(response);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final token = await _requireAccessToken();
    final uri = Uri.parse('$_baseUrl$path');
    http.Response response;
    try {
      response = await _client.post(
        uri,
        headers: _authHeaders(token),
        body: jsonEncode(body),
      );
    } on Exception catch (error) {
      throw MarketplaceApiException('Request failed: $error');
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

  dynamic _decodeResponse(http.Response response) {
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
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(parser)
        .toList();
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

