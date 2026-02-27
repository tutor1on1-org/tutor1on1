import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../constants.dart';
import 'secure_storage_service.dart';

class SessionSyncApiException implements Exception {
  SessionSyncApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class SyncListResult<T> {
  SyncListResult({
    required this.items,
    required this.etag,
    required this.notModified,
  });

  final List<T> items;
  final String? etag;
  final bool notModified;
}

class UserKeyRecord {
  UserKeyRecord({
    required this.publicKey,
    required this.encryptedPrivateKey,
    required this.kdfSalt,
    required this.kdfIterations,
    required this.kdfAlgorithm,
  });

  final String publicKey;
  final String encryptedPrivateKey;
  final String kdfSalt;
  final int kdfIterations;
  final String kdfAlgorithm;

  factory UserKeyRecord.fromJson(Map<String, dynamic> json) {
    return UserKeyRecord(
      publicKey: (json['public_key'] as String?) ?? '',
      encryptedPrivateKey: (json['enc_private_key'] as String?) ?? '',
      kdfSalt: (json['kdf_salt'] as String?) ?? '',
      kdfIterations: (json['kdf_iterations'] as num?)?.toInt() ?? 0,
      kdfAlgorithm: (json['kdf_algorithm'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'public_key': publicKey,
        'enc_private_key': encryptedPrivateKey,
        'kdf_salt': kdfSalt,
        'kdf_iterations': kdfIterations,
        'kdf_algorithm': kdfAlgorithm,
      };
}

class CourseKeyBundle {
  CourseKeyBundle({
    required this.courseId,
    required this.teacherUserId,
    required this.teacherPublicKey,
    required this.studentUserId,
    required this.studentPublicKey,
  });

  final int courseId;
  final int teacherUserId;
  final String teacherPublicKey;
  final int studentUserId;
  final String studentPublicKey;

  factory CourseKeyBundle.fromJson(Map<String, dynamic> json) {
    return CourseKeyBundle(
      courseId: (json['course_id'] as num?)?.toInt() ?? 0,
      teacherUserId: (json['teacher_user_id'] as num?)?.toInt() ?? 0,
      teacherPublicKey: (json['teacher_public_key'] as String?) ?? '',
      studentUserId: (json['student_user_id'] as num?)?.toInt() ?? 0,
      studentPublicKey: (json['student_public_key'] as String?) ?? '',
    );
  }
}

class SessionSyncItem {
  SessionSyncItem({
    required this.sessionSyncId,
    required this.courseId,
    required this.teacherUserId,
    required this.studentUserId,
    required this.senderUserId,
    required this.updatedAt,
    required this.envelope,
    required this.envelopeHash,
  });

  final String sessionSyncId;
  final int courseId;
  final int teacherUserId;
  final int studentUserId;
  final int senderUserId;
  final String updatedAt;
  final String envelope;
  final String envelopeHash;

  factory SessionSyncItem.fromJson(Map<String, dynamic> json) {
    return SessionSyncItem(
      sessionSyncId: (json['session_sync_id'] as String?) ?? '',
      courseId: (json['course_id'] as num?)?.toInt() ?? 0,
      teacherUserId: (json['teacher_user_id'] as num?)?.toInt() ?? 0,
      studentUserId: (json['student_user_id'] as num?)?.toInt() ?? 0,
      senderUserId: (json['sender_user_id'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updated_at'] as String?) ?? '',
      envelope: (json['envelope'] as String?) ?? '',
      envelopeHash: (json['envelope_hash'] as String?) ?? '',
    );
  }
}

class ProgressSyncItem {
  ProgressSyncItem({
    required this.courseId,
    required this.courseSubject,
    required this.teacherUserId,
    required this.studentUserId,
    required this.kpKey,
    required this.lit,
    required this.litPercent,
    required this.questionLevel,
    required this.summaryText,
    required this.summaryRawResponse,
    required this.summaryValid,
    required this.updatedAt,
    required this.envelope,
    required this.envelopeHash,
  });

  final int courseId;
  final String courseSubject;
  final int teacherUserId;
  final int studentUserId;
  final String kpKey;
  final bool lit;
  final int litPercent;
  final String questionLevel;
  final String summaryText;
  final String summaryRawResponse;
  final bool? summaryValid;
  final String updatedAt;
  final String envelope;
  final String envelopeHash;

  factory ProgressSyncItem.fromJson(Map<String, dynamic> json) {
    return ProgressSyncItem(
      courseId: (json['course_id'] as num?)?.toInt() ?? 0,
      courseSubject: (json['course_subject'] as String?) ?? '',
      teacherUserId: (json['teacher_user_id'] as num?)?.toInt() ?? 0,
      studentUserId: (json['student_user_id'] as num?)?.toInt() ?? 0,
      kpKey: (json['kp_key'] as String?) ?? '',
      lit: (json['lit'] as bool?) ?? false,
      litPercent: (json['lit_percent'] as num?)?.toInt() ?? 0,
      questionLevel: (json['question_level'] as String?) ?? '',
      summaryText: (json['summary_text'] as String?) ?? '',
      summaryRawResponse: (json['summary_raw_response'] as String?) ?? '',
      summaryValid: json['summary_valid'] as bool?,
      updatedAt: (json['updated_at'] as String?) ?? '',
      envelope: (json['envelope'] as String?) ?? '',
      envelopeHash: (json['envelope_hash'] as String?) ?? '',
    );
  }
}

class ProgressUploadEntry {
  ProgressUploadEntry({
    required this.courseId,
    required this.kpKey,
    required this.updatedAt,
    required this.envelope,
    required this.envelopeHash,
  });

  final int courseId;
  final String kpKey;
  final String updatedAt;
  final String envelope;
  final String envelopeHash;

  Map<String, dynamic> toJson() => {
        'course_id': courseId,
        'kp_key': kpKey,
        'updated_at': updatedAt,
        'envelope': envelope,
        'envelope_hash': envelopeHash,
      };
}

class SessionSyncApiService {
  SessionSyncApiService({
    required SecureStorageService secureStorage,
    String? baseUrl,
    http.Client? client,
  })  : _secureStorage = secureStorage,
        _baseUrl = _normalizeBaseUrl(baseUrl ?? kAuthBaseUrl),
        _client = client ?? _buildClient(kAuthAllowInsecureTls);

  final SecureStorageService _secureStorage;
  final String _baseUrl;
  final http.Client _client;

  Future<UserKeyRecord?> getUserKey() async {
    final response = await _get('/api/keys/self');
    if (response is Map<String, dynamic>) {
      if (response.isEmpty) {
        return null;
      }
      return UserKeyRecord.fromJson(response);
    }
    return null;
  }

  Future<void> upsertUserKey(UserKeyRecord record) async {
    await _post('/api/keys/self', record.toJson());
  }

  Future<CourseKeyBundle> getCourseKeys({
    required int courseId,
    required int studentUserId,
  }) async {
    final response = await _get(
      '/api/keys/course',
      params: {
        'course_id': courseId.toString(),
        'student_user_id': studentUserId.toString(),
      },
    );
    if (response is! Map<String, dynamic>) {
      throw SessionSyncApiException('Unexpected response format.');
    }
    return CourseKeyBundle.fromJson(response);
  }

  Future<void> uploadSession({
    required String sessionSyncId,
    required int courseId,
    required int studentUserId,
    required String updatedAt,
    required String envelope,
    String? envelopeHash,
  }) async {
    await _post('/api/sessions/sync/upload', {
      'session_sync_id': sessionSyncId,
      'course_id': courseId,
      'student_user_id': studentUserId,
      'updated_at': updatedAt,
      'envelope': envelope,
      'envelope_hash': envelopeHash ?? '',
    });
  }

  Future<List<SessionSyncItem>> listSessions({String? since}) async {
    final result = await listSessionsDelta(since: since);
    return result.items;
  }

  Future<SyncListResult<SessionSyncItem>> listSessionsDelta({
    String? since,
    int? limit,
    String? ifNoneMatch,
  }) async {
    final params = <String, String>{};
    if ((since ?? '').trim().isNotEmpty) {
      params['since'] = since!.trim();
    }
    if ((limit ?? 0) > 0) {
      params['limit'] = limit!.toString();
    }
    final response = await _getResponse(
      '/api/sessions/sync/list',
      params: params,
      ifNoneMatch: ifNoneMatch,
    );
    if (response.statusCode == 304) {
      return SyncListResult<SessionSyncItem>(
        items: const <SessionSyncItem>[],
        etag: response.headers['etag'],
        notModified: true,
      );
    }
    final decoded = _decodeResponse(response);
    if (decoded is! List) {
      throw SessionSyncApiException('Unexpected response format.');
    }
    return SyncListResult<SessionSyncItem>(
      items: decoded
          .whereType<Map<String, dynamic>>()
          .map(SessionSyncItem.fromJson)
          .toList(),
      etag: response.headers['etag'],
      notModified: false,
    );
  }

  Future<void> uploadProgress({
    required int courseId,
    required String kpKey,
    required String updatedAt,
    required String envelope,
    String? envelopeHash,
  }) async {
    await _post('/api/progress/sync/upload', {
      'course_id': courseId,
      'kp_key': kpKey,
      'updated_at': updatedAt,
      'envelope': envelope,
      'envelope_hash': envelopeHash ?? '',
    });
  }

  Future<void> uploadProgressBatch(List<ProgressUploadEntry> entries) async {
    if (entries.isEmpty) {
      return;
    }
    try {
      await _post(
        '/api/progress/sync/upload-batch',
        {
          'items':
              entries.map((entry) => entry.toJson()).toList(growable: false),
        },
      );
      return;
    } on SessionSyncApiException catch (error) {
      if (error.statusCode != 404) {
        rethrow;
      }
    }
    for (final entry in entries) {
      await uploadProgress(
        courseId: entry.courseId,
        kpKey: entry.kpKey,
        updatedAt: entry.updatedAt,
        envelope: entry.envelope,
        envelopeHash: entry.envelopeHash,
      );
    }
  }

  Future<List<ProgressSyncItem>> listProgress({String? since}) async {
    final result = await listProgressDelta(since: since);
    return result.items;
  }

  Future<SyncListResult<ProgressSyncItem>> listProgressDelta({
    String? since,
    int? limit,
    String? ifNoneMatch,
  }) async {
    final params = <String, String>{};
    if ((since ?? '').trim().isNotEmpty) {
      params['since'] = since!.trim();
    }
    if ((limit ?? 0) > 0) {
      params['limit'] = limit!.toString();
    }
    final response = await _getResponse(
      '/api/progress/sync/list',
      params: params,
      ifNoneMatch: ifNoneMatch,
    );
    if (response.statusCode == 304) {
      return SyncListResult<ProgressSyncItem>(
        items: const <ProgressSyncItem>[],
        etag: response.headers['etag'],
        notModified: true,
      );
    }
    final decoded = _decodeResponse(response);
    if (decoded is! List) {
      throw SessionSyncApiException('Unexpected response format.');
    }
    return SyncListResult<ProgressSyncItem>(
      items: decoded
          .whereType<Map<String, dynamic>>()
          .map(ProgressSyncItem.fromJson)
          .toList(),
      etag: response.headers['etag'],
      notModified: false,
    );
  }

  Future<dynamic> _get(
    String path, {
    Map<String, String>? params,
  }) async {
    final response = await _getResponse(path, params: params);
    return _decodeResponse(response);
  }

  Future<http.Response> _getResponse(
    String path, {
    Map<String, String>? params,
    String? ifNoneMatch,
  }) async {
    final token = await _requireAccessToken();
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: params);
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
      throw SessionSyncApiException('Request failed: $error');
    }
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
      throw SessionSyncApiException('Request failed: $error');
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
      throw SessionSyncApiException('Missing auth token.');
    }
    return token.trim();
  }

  dynamic _decodeResponse(http.Response response) {
    if (response.statusCode == 304) {
      return const <String, dynamic>{};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SessionSyncApiException(
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
