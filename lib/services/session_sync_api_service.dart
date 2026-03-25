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

class SyncDownloadManifestResult {
  SyncDownloadManifestResult({
    required this.sessions,
    required this.progressChunks,
    required this.progressRows,
    required this.etag,
    required this.notModified,
  });

  final List<SessionSyncManifestItem> sessions;
  final List<ProgressSyncChunkManifestItem> progressChunks;
  final List<ProgressSyncManifestItem> progressRows;
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
    required this.cursorId,
    required this.sessionSyncId,
    required this.courseId,
    required this.teacherUserId,
    required this.studentUserId,
    required this.senderUserId,
    this.chapterKey = '',
    required this.updatedAt,
    required this.envelope,
    required this.envelopeHash,
  });

  final int cursorId;
  final String sessionSyncId;
  final int courseId;
  final int teacherUserId;
  final int studentUserId;
  final int senderUserId;
  final String chapterKey;
  final String updatedAt;
  final String envelope;
  final String envelopeHash;

  factory SessionSyncItem.fromJson(Map<String, dynamic> json) {
    return SessionSyncItem(
      cursorId: (json['cursor_id'] as num?)?.toInt() ?? 0,
      sessionSyncId: (json['session_sync_id'] as String?) ?? '',
      courseId: (json['course_id'] as num?)?.toInt() ?? 0,
      teacherUserId: (json['teacher_user_id'] as num?)?.toInt() ?? 0,
      studentUserId: (json['student_user_id'] as num?)?.toInt() ?? 0,
      senderUserId: (json['sender_user_id'] as num?)?.toInt() ?? 0,
      chapterKey: (json['chapter_key'] as String?) ?? '',
      updatedAt: (json['updated_at'] as String?) ?? '',
      envelope: (json['envelope'] as String?) ?? '',
      envelopeHash: (json['envelope_hash'] as String?) ?? '',
    );
  }
}

class SessionUploadEntry {
  SessionUploadEntry({
    required this.sessionSyncId,
    required this.courseId,
    required this.studentUserId,
    required this.chapterKey,
    required this.updatedAt,
    required this.envelope,
    required this.envelopeHash,
  });

  final String sessionSyncId;
  final int courseId;
  final int studentUserId;
  final String chapterKey;
  final String updatedAt;
  final String envelope;
  final String envelopeHash;

  Map<String, dynamic> toJson() => {
        'session_sync_id': sessionSyncId,
        'course_id': courseId,
        'student_user_id': studentUserId,
        'chapter_key': chapterKey,
        'updated_at': updatedAt,
        'envelope': envelope,
        'envelope_hash': envelopeHash,
      };
}

class ProgressSyncItem {
  ProgressSyncItem({
    required this.cursorId,
    required this.courseId,
    required this.courseSubject,
    required this.teacherUserId,
    required this.studentUserId,
    required this.kpKey,
    required this.lit,
    required this.litPercent,
    required this.questionLevel,
    this.easyPassedCount = 0,
    this.mediumPassedCount = 0,
    this.hardPassedCount = 0,
    required this.summaryText,
    required this.summaryRawResponse,
    required this.summaryValid,
    required this.updatedAt,
    required this.envelope,
    required this.envelopeHash,
  });

  final int cursorId;
  final int courseId;
  final String courseSubject;
  final int teacherUserId;
  final int studentUserId;
  final String kpKey;
  final bool lit;
  final int litPercent;
  final String questionLevel;
  final int easyPassedCount;
  final int mediumPassedCount;
  final int hardPassedCount;
  final String summaryText;
  final String summaryRawResponse;
  final bool? summaryValid;
  final String updatedAt;
  final String envelope;
  final String envelopeHash;

  factory ProgressSyncItem.fromJson(Map<String, dynamic> json) {
    return ProgressSyncItem(
      cursorId: (json['cursor_id'] as num?)?.toInt() ?? 0,
      courseId: (json['course_id'] as num?)?.toInt() ?? 0,
      courseSubject: (json['course_subject'] as String?) ?? '',
      teacherUserId: (json['teacher_user_id'] as num?)?.toInt() ?? 0,
      studentUserId: (json['student_user_id'] as num?)?.toInt() ?? 0,
      kpKey: (json['kp_key'] as String?) ?? '',
      lit: (json['lit'] as bool?) ?? false,
      litPercent: (json['lit_percent'] as num?)?.toInt() ?? 0,
      questionLevel: (json['question_level'] as String?) ?? '',
      easyPassedCount: (json['easy_passed_count'] as num?)?.toInt() ?? 0,
      mediumPassedCount: (json['medium_passed_count'] as num?)?.toInt() ?? 0,
      hardPassedCount: (json['hard_passed_count'] as num?)?.toInt() ?? 0,
      summaryText: (json['summary_text'] as String?) ?? '',
      summaryRawResponse: (json['summary_raw_response'] as String?) ?? '',
      summaryValid: json['summary_valid'] as bool?,
      updatedAt: (json['updated_at'] as String?) ?? '',
      envelope: (json['envelope'] as String?) ?? '',
      envelopeHash: (json['envelope_hash'] as String?) ?? '',
    );
  }
}

class ProgressSyncChunkItem {
  ProgressSyncChunkItem({
    required this.cursorId,
    required this.courseId,
    required this.courseSubject,
    required this.teacherUserId,
    required this.studentUserId,
    required this.chapterKey,
    required this.itemCount,
    required this.updatedAt,
    required this.envelope,
    required this.envelopeHash,
  });

  final int cursorId;
  final int courseId;
  final String courseSubject;
  final int teacherUserId;
  final int studentUserId;
  final String chapterKey;
  final int itemCount;
  final String updatedAt;
  final String envelope;
  final String envelopeHash;

  factory ProgressSyncChunkItem.fromJson(Map<String, dynamic> json) {
    return ProgressSyncChunkItem(
      cursorId: (json['cursor_id'] as num?)?.toInt() ?? 0,
      courseId: (json['course_id'] as num?)?.toInt() ?? 0,
      courseSubject: (json['course_subject'] as String?) ?? '',
      teacherUserId: (json['teacher_user_id'] as num?)?.toInt() ?? 0,
      studentUserId: (json['student_user_id'] as num?)?.toInt() ?? 0,
      chapterKey: (json['chapter_key'] as String?) ?? '',
      itemCount: (json['item_count'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updated_at'] as String?) ?? '',
      envelope: (json['envelope'] as String?) ?? '',
      envelopeHash: (json['envelope_hash'] as String?) ?? '',
    );
  }
}

class SessionSyncManifestItem {
  SessionSyncManifestItem({
    required this.sessionSyncId,
    required this.updatedAt,
    required this.envelopeHash,
  });

  final String sessionSyncId;
  final String updatedAt;
  final String envelopeHash;

  factory SessionSyncManifestItem.fromJson(Map<String, dynamic> json) {
    return SessionSyncManifestItem(
      sessionSyncId: (json['session_sync_id'] as String?) ?? '',
      updatedAt: (json['updated_at'] as String?) ?? '',
      envelopeHash: (json['envelope_hash'] as String?) ?? '',
    );
  }
}

class ProgressSyncChunkManifestItem {
  ProgressSyncChunkManifestItem({
    required this.studentUserId,
    required this.courseId,
    required this.chapterKey,
    required this.updatedAt,
    required this.envelopeHash,
  });

  final int studentUserId;
  final int courseId;
  final String chapterKey;
  final String updatedAt;
  final String envelopeHash;

  factory ProgressSyncChunkManifestItem.fromJson(Map<String, dynamic> json) {
    return ProgressSyncChunkManifestItem(
      studentUserId: (json['student_user_id'] as num?)?.toInt() ?? 0,
      courseId: (json['course_id'] as num?)?.toInt() ?? 0,
      chapterKey: (json['chapter_key'] as String?) ?? '',
      updatedAt: (json['updated_at'] as String?) ?? '',
      envelopeHash: (json['envelope_hash'] as String?) ?? '',
    );
  }
}

class ProgressSyncManifestItem {
  ProgressSyncManifestItem({
    required this.studentUserId,
    required this.courseId,
    required this.kpKey,
    required this.updatedAt,
    required this.envelopeHash,
  });

  final int studentUserId;
  final int courseId;
  final String kpKey;
  final String updatedAt;
  final String envelopeHash;

  factory ProgressSyncManifestItem.fromJson(Map<String, dynamic> json) {
    return ProgressSyncManifestItem(
      studentUserId: (json['student_user_id'] as num?)?.toInt() ?? 0,
      courseId: (json['course_id'] as num?)?.toInt() ?? 0,
      kpKey: (json['kp_key'] as String?) ?? '',
      updatedAt: (json['updated_at'] as String?) ?? '',
      envelopeHash: (json['envelope_hash'] as String?) ?? '',
    );
  }
}

class SyncDownloadFetchRequest {
  SyncDownloadFetchRequest({
    required this.sessionSyncIds,
    required this.progressChunks,
    required this.progressRows,
  });

  final List<String> sessionSyncIds;
  final List<ProgressChunkFetchKey> progressChunks;
  final List<ProgressRowFetchKey> progressRows;

  Map<String, dynamic> toJson() => {
        'session_sync_ids': sessionSyncIds,
        'progress_chunks':
            progressChunks.map((item) => item.toJson()).toList(growable: false),
        'progress_rows':
            progressRows.map((item) => item.toJson()).toList(growable: false),
      };
}

class ProgressChunkFetchKey {
  ProgressChunkFetchKey({
    required this.studentUserId,
    required this.courseId,
    required this.chapterKey,
  });

  final int studentUserId;
  final int courseId;
  final String chapterKey;

  Map<String, dynamic> toJson() => {
        'student_user_id': studentUserId,
        'course_id': courseId,
        'chapter_key': chapterKey,
      };
}

class ProgressRowFetchKey {
  ProgressRowFetchKey({
    required this.studentUserId,
    required this.courseId,
    required this.kpKey,
  });

  final int studentUserId;
  final int courseId;
  final String kpKey;

  Map<String, dynamic> toJson() => {
        'student_user_id': studentUserId,
        'course_id': courseId,
        'kp_key': kpKey,
      };
}

class SyncDownloadFetchResult {
  SyncDownloadFetchResult({
    required this.sessions,
    required this.progressChunks,
    required this.progressRows,
  });

  final List<SessionSyncItem> sessions;
  final List<ProgressSyncChunkItem> progressChunks;
  final List<ProgressSyncItem> progressRows;

  factory SyncDownloadFetchResult.fromJson(Map<String, dynamic> json) {
    return SyncDownloadFetchResult(
      sessions: ((json['sessions'] as List?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(SessionSyncItem.fromJson)
          .toList(),
      progressChunks: ((json['progress_chunks'] as List?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(ProgressSyncChunkItem.fromJson)
          .toList(),
      progressRows: ((json['progress_rows'] as List?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(ProgressSyncItem.fromJson)
          .toList(),
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

class ProgressChunkUploadEntry {
  ProgressChunkUploadEntry({
    required this.courseId,
    required this.chapterKey,
    required this.itemCount,
    required this.updatedAt,
    required this.envelope,
    required this.envelopeHash,
  });

  final int courseId;
  final String chapterKey;
  final int itemCount;
  final String updatedAt;
  final String envelope;
  final String envelopeHash;

  Map<String, dynamic> toJson() => {
        'course_id': courseId,
        'chapter_key': chapterKey,
        'item_count': itemCount,
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

  Future<SyncDownloadManifestResult> getDownloadManifest({
    required bool includeProgress,
    String? ifNoneMatch,
  }) async {
    final response = await _getResponse(
      '/api/sync/download-manifest',
      params: <String, String>{
        'include_progress': includeProgress ? 'true' : 'false',
      },
      ifNoneMatch: ifNoneMatch,
    );
    if (response.statusCode == 304) {
      return SyncDownloadManifestResult(
        sessions: const <SessionSyncManifestItem>[],
        progressChunks: const <ProgressSyncChunkManifestItem>[],
        progressRows: const <ProgressSyncManifestItem>[],
        etag: response.headers['etag'],
        notModified: true,
      );
    }
    final decoded = _decodeResponse(response);
    if (decoded is! Map<String, dynamic>) {
      throw SessionSyncApiException('Unexpected response format.');
    }
    return SyncDownloadManifestResult(
      sessions: ((decoded['sessions'] as List?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(SessionSyncManifestItem.fromJson)
          .toList(),
      progressChunks:
          ((decoded['progress_chunks'] as List?) ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(ProgressSyncChunkManifestItem.fromJson)
              .toList(),
      progressRows: ((decoded['progress_rows'] as List?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(ProgressSyncManifestItem.fromJson)
          .toList(),
      etag: response.headers['etag'],
      notModified: false,
    );
  }

  Future<SyncDownloadFetchResult> fetchDownloadPayload({
    required SyncDownloadFetchRequest request,
  }) async {
    final response = await _post(
      '/api/sync/download-fetch',
      request.toJson(),
    );
    if (response is! Map<String, dynamic>) {
      throw SessionSyncApiException('Unexpected response format.');
    }
    return SyncDownloadFetchResult.fromJson(response);
  }

  Future<void> uploadSession({
    required String sessionSyncId,
    required int courseId,
    required int studentUserId,
    String chapterKey = '',
    required String updatedAt,
    required String envelope,
    String? envelopeHash,
  }) async {
    await _post('/api/sessions/sync/upload', {
      'session_sync_id': sessionSyncId,
      'course_id': courseId,
      'student_user_id': studentUserId,
      'chapter_key': chapterKey,
      'updated_at': updatedAt,
      'envelope': envelope,
      'envelope_hash': envelopeHash ?? '',
    });
  }

  Future<void> uploadSessionBatch(List<SessionUploadEntry> entries) async {
    if (entries.isEmpty) {
      return;
    }
    await _post(
      '/api/sessions/sync/upload-batch',
      {
        'items': entries.map((entry) => entry.toJson()).toList(growable: false),
      },
    );
  }

  Future<List<SessionSyncItem>> listSessions({String? since}) async {
    final result = await listSessionsDelta(since: since);
    return result.items;
  }

  Future<SyncListResult<SessionSyncItem>> listSessionsDelta({
    String? since,
    int? sinceId,
    int? limit,
    String? ifNoneMatch,
  }) async {
    final params = <String, String>{};
    final normalizedSince = (since ?? '').trim();
    final normalizedSinceId = sinceId ?? 0;
    if (normalizedSince.isNotEmpty) {
      params['since'] = normalizedSince;
    }
    if (normalizedSinceId > 0) {
      if (normalizedSince.isEmpty) {
        throw SessionSyncApiException('since_id requires since.');
      }
      params['since_id'] = normalizedSinceId.toString();
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
    await _post(
      '/api/progress/sync/upload-batch',
      {
        'items': entries.map((entry) => entry.toJson()).toList(growable: false),
      },
    );
  }

  Future<void> uploadProgressChunkBatch(
      List<ProgressChunkUploadEntry> entries) async {
    if (entries.isEmpty) {
      return;
    }
    await _post(
      '/api/progress/sync/chunks/upload-batch',
      {
        'items': entries.map((entry) => entry.toJson()).toList(growable: false),
      },
    );
  }

  Future<List<ProgressSyncItem>> listProgress({String? since}) async {
    final result = await listProgressDelta(since: since);
    return result.items;
  }

  Future<SyncListResult<ProgressSyncItem>> listProgressDelta({
    String? since,
    int? sinceId,
    int? limit,
    String? ifNoneMatch,
  }) async {
    final params = <String, String>{};
    final normalizedSince = (since ?? '').trim();
    final normalizedSinceId = sinceId ?? 0;
    if (normalizedSince.isNotEmpty) {
      params['since'] = normalizedSince;
    }
    if (normalizedSinceId > 0) {
      if (normalizedSince.isEmpty) {
        throw SessionSyncApiException('since_id requires since.');
      }
      params['since_id'] = normalizedSinceId.toString();
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

  Future<SyncListResult<ProgressSyncChunkItem>> listProgressChunksDelta({
    String? since,
    int? sinceId,
    int? limit,
    String? ifNoneMatch,
  }) async {
    final params = <String, String>{};
    final normalizedSince = (since ?? '').trim();
    final normalizedSinceId = sinceId ?? 0;
    if (normalizedSince.isNotEmpty) {
      params['since'] = normalizedSince;
    }
    if (normalizedSinceId > 0) {
      if (normalizedSince.isEmpty) {
        throw SessionSyncApiException('since_id requires since.');
      }
      params['since_id'] = normalizedSinceId.toString();
    }
    if ((limit ?? 0) > 0) {
      params['limit'] = limit!.toString();
    }
    final response = await _getResponse(
      '/api/progress/sync/chunks/list',
      params: params,
      ifNoneMatch: ifNoneMatch,
    );
    if (response.statusCode == 304) {
      return SyncListResult<ProgressSyncChunkItem>(
        items: const <ProgressSyncChunkItem>[],
        etag: response.headers['etag'],
        notModified: true,
      );
    }
    final decoded = _decodeResponse(response);
    if (decoded is! List) {
      throw SessionSyncApiException('Unexpected response format.');
    }
    return SyncListResult<ProgressSyncChunkItem>(
      items: decoded
          .whereType<Map<String, dynamic>>()
          .map(ProgressSyncChunkItem.fromJson)
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
        throw SessionSyncApiException('Request failed: $error');
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

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_baseUrl$path');
    Future<http.Response> send(String token) async {
      try {
        return await _client.post(
          uri,
          headers: _authHeaders(token),
          body: jsonEncode(body),
        );
      } on Exception catch (error) {
        throw SessionSyncApiException('Request failed: $error');
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
      'X-Device-Id': SecureStorageService.syncRunDeviceHash,
    };
  }

  Future<String> _requireAccessToken() async {
    final token = await _secureStorage.readAuthAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw SessionSyncApiException('Missing auth token.');
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
      throw SessionSyncApiException('Token refresh failed: $error');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 400 || response.statusCode == 401) {
        await _secureStorage.deleteAuthTokens();
        return false;
      }
      throw SessionSyncApiException(
        _extractError(response.body) ?? 'Token refresh failed.',
        statusCode: response.statusCode,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw SessionSyncApiException('Token refresh response invalid.');
    }
    final accessToken = (decoded['access_token'] as String?)?.trim() ?? '';
    final nextRefreshToken =
        (decoded['refresh_token'] as String?)?.trim() ?? '';
    if (accessToken.isEmpty || nextRefreshToken.isEmpty) {
      throw SessionSyncApiException('Token refresh response missing tokens.');
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
