import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../constants.dart';
import 'auth_token_refresh_coordinator.dart';
import 'secure_storage_service.dart';

class ArtifactState1Item {
  ArtifactState1Item({
    required this.artifactId,
    required this.artifactClass,
    required this.courseId,
    required this.teacherUserId,
    required this.studentUserId,
    required this.kpKey,
    required this.bundleVersionId,
    required this.sha256,
    required this.lastModified,
  });

  final String artifactId;
  final String artifactClass;
  final int courseId;
  final int teacherUserId;
  final int studentUserId;
  final String kpKey;
  final int bundleVersionId;
  final String sha256;
  final String lastModified;

  factory ArtifactState1Item.fromJson(Map<String, dynamic> json) {
    return ArtifactState1Item(
      artifactId: (json['artifact_id'] as String?)?.trim() ?? '',
      artifactClass: (json['artifact_class'] as String?)?.trim() ?? '',
      courseId: (json['course_id'] as num?)?.toInt() ?? 0,
      teacherUserId: (json['teacher_user_id'] as num?)?.toInt() ?? 0,
      studentUserId: (json['student_user_id'] as num?)?.toInt() ?? 0,
      kpKey: (json['kp_key'] as String?)?.trim() ?? '',
      bundleVersionId: (json['bundle_version_id'] as num?)?.toInt() ?? 0,
      sha256: (json['sha256'] as String?)?.trim() ?? '',
      lastModified: (json['last_modified'] as String?)?.trim() ?? '',
    );
  }
}

class ArtifactState1Result {
  ArtifactState1Result({
    required this.state2,
    required this.items,
  });

  final String state2;
  final List<ArtifactState1Item> items;
}

class DownloadedArtifact {
  DownloadedArtifact({
    required this.artifactId,
    required this.artifactClass,
    required this.sha256,
    required this.lastModified,
    required this.bytes,
  });

  final String artifactId;
  final String artifactClass;
  final String sha256;
  final String lastModified;
  final Uint8List bytes;
}

class UploadArtifactResult {
  UploadArtifactResult({
    required this.artifactId,
    required this.sha256,
    required this.bundleVersionId,
    required this.state2,
  });

  final String artifactId;
  final String sha256;
  final int bundleVersionId;
  final String state2;

  factory UploadArtifactResult.fromJson(Map<String, dynamic> json) {
    return UploadArtifactResult(
      artifactId: (json['artifact_id'] as String?)?.trim() ?? '',
      sha256: (json['sha256'] as String?)?.trim() ?? '',
      bundleVersionId: (json['bundle_version_id'] as num?)?.toInt() ?? 0,
      state2: (json['state2'] as String?)?.trim() ?? '',
    );
  }
}

class ArtifactConflictException implements Exception {
  ArtifactConflictException({
    required this.message,
    required this.serverSha256,
    required this.expectedBaseSha256,
  });

  final String message;
  final String serverSha256;
  final String expectedBaseSha256;

  @override
  String toString() => message;
}

class ArtifactSyncApiException implements Exception {
  ArtifactSyncApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ArtifactSyncApiService {
  ArtifactSyncApiService({
    required SecureStorageService secureStorage,
    String? baseUrl,
    http.Client? client,
  })  : _secureStorage = secureStorage,
        _baseUrl = _normalizeBaseUrl(baseUrl ?? kAuthBaseUrl),
        _client = client ?? _buildClient(kAuthAllowInsecureTls);

  final SecureStorageService _secureStorage;
  final String _baseUrl;
  final http.Client _client;

  Future<String> getState2({required String artifactClass}) async {
    final response = await _get(
      '/api/artifacts/sync/state2',
      params: {'artifact_class': artifactClass},
    );
    if (response is! Map<String, dynamic>) {
      throw ArtifactSyncApiException('Unexpected response format.');
    }
    return ((response['state2'] as String?) ?? '').trim();
  }

  Future<ArtifactState1Result> getState1(
      {required String artifactClass}) async {
    final response = await _get(
      '/api/artifacts/sync/state1',
      params: {'artifact_class': artifactClass},
    );
    if (response is! Map<String, dynamic>) {
      throw ArtifactSyncApiException('Unexpected response format.');
    }
    return ArtifactState1Result(
      state2: ((response['state2'] as String?) ?? '').trim(),
      items: ((response['items'] as List?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(ArtifactState1Item.fromJson)
          .toList(growable: false),
    );
  }

  Future<DownloadedArtifact> downloadArtifact(String artifactId) async {
    final uri = Uri.parse('$_baseUrl/api/artifacts/download').replace(
      queryParameters: <String, String>{
        'artifact_id': artifactId,
      },
    );
    Future<http.Response> send(String token) {
      return _client.get(uri, headers: _authHeaders(token));
    }

    var token = await _requireAccessToken();
    var response = await send(token);
    if (response.statusCode == 401 && await _refreshAccessToken()) {
      token = await _requireAccessToken();
      response = await send(token);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ArtifactSyncApiException(
        _extractError(response.body) ?? 'Artifact download failed.',
        statusCode: response.statusCode,
      );
    }
    return DownloadedArtifact(
      artifactId: (response.headers['x-artifact-id'] ?? '').trim(),
      artifactClass: (response.headers['x-artifact-class'] ?? '').trim(),
      sha256: (response.headers['x-artifact-sha256'] ?? '').trim(),
      lastModified: (response.headers['x-artifact-last-modified'] ?? '').trim(),
      bytes: response.bodyBytes,
    );
  }

  Future<UploadArtifactResult> uploadArtifact({
    required String artifactId,
    required String sha256,
    required Uint8List bytes,
    required String baseSha256,
    required bool overwriteServer,
  }) async {
    Future<http.Response> send(String token) async {
      final request = http.MultipartRequest(
          'POST', Uri.parse('$_baseUrl/api/artifacts/upload'));
      request.headers.addAll(_authHeaders(token, includeContentType: false));
      request.fields['artifact_id'] = artifactId.trim();
      request.fields['sha256'] = sha256.trim();
      request.fields['base_sha256'] = baseSha256.trim();
      request.fields['overwrite_server'] = overwriteServer ? 'true' : 'false';
      request.files.add(
        http.MultipartFile.fromBytes(
          'artifact',
          bytes,
          filename: _artifactFilename(artifactId),
        ),
      );
      final streamed = await _client.send(request);
      return http.Response.fromStream(streamed);
    }

    var token = await _requireAccessToken();
    var response = await send(token);
    if (response.statusCode == 401 && await _refreshAccessToken()) {
      token = await _requireAccessToken();
      response = await send(token);
    }
    if (response.statusCode == 409) {
      final decoded = _decodeJsonBody(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw ArtifactSyncApiException(
          'Unexpected conflict response format.',
          statusCode: response.statusCode,
        );
      }
      throw ArtifactConflictException(
        message: (decoded['conflict_type'] as String?)?.trim().isNotEmpty ==
                true
            ? 'Artifact conflict: ${(decoded['conflict_type'] as String).trim()}'
            : 'Artifact conflict.',
        serverSha256: (decoded['server_sha256'] as String?)?.trim() ?? '',
        expectedBaseSha256: (decoded['expected_base'] as String?)?.trim() ?? '',
      );
    }
    final decoded = _decodeResponse(response);
    if (decoded is! Map<String, dynamic>) {
      throw ArtifactSyncApiException('Unexpected response format.');
    }
    return UploadArtifactResult.fromJson(decoded);
  }

  Future<dynamic> _get(
    String path, {
    Map<String, String>? params,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(
      queryParameters: params == null || params.isEmpty ? null : params,
    );
    Future<http.Response> send(String token) {
      return _client.get(uri, headers: _authHeaders(token));
    }

    var token = await _requireAccessToken();
    var response = await send(token);
    if (response.statusCode == 401 && await _refreshAccessToken()) {
      token = await _requireAccessToken();
      response = await send(token);
    }
    return _decodeResponse(response);
  }

  Map<String, String> _authHeaders(
    String token, {
    bool includeContentType = true,
  }) {
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'X-Device-Id': SecureStorageService.syncRunDeviceHash,
    };
    if (includeContentType) {
      headers['Content-Type'] = 'application/json';
    }
    return headers;
  }

  Future<String> _requireAccessToken() async {
    final token = await _secureStorage.readAuthAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw ArtifactSyncApiException('Missing auth token.');
    }
    return token.trim();
  }

  Future<bool> _refreshAccessToken() async {
    try {
      return await AuthTokenRefreshCoordinator.refresh(
        client: _client,
        secureStorage: _secureStorage,
        baseUrl: _baseUrl,
      );
    } on AuthTokenRefreshException catch (error) {
      throw ArtifactSyncApiException(
        error.message,
        statusCode: error.statusCode,
      );
    }
  }

  dynamic _decodeResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ArtifactSyncApiException(
        _extractError(response.body) ?? 'Request failed.',
        statusCode: response.statusCode,
      );
    }
    return _decodeJsonBody(response.body);
  }

  dynamic _decodeJsonBody(String body) {
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }
    try {
      return jsonDecode(body);
    } catch (error) {
      throw ArtifactSyncApiException('Invalid server response: $error');
    }
  }

  String? _extractError(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        final message = (decoded['error'] as String?)?.trim();
        if (message != null && message.isNotEmpty) {
          return message;
        }
        final status = (decoded['status'] as String?)?.trim();
        if (status != null && status.isNotEmpty && status != 'ok') {
          return status;
        }
      }
    } catch (_) {
      return trimmed;
    }
    return trimmed;
  }

  static String _artifactFilename(String artifactId) {
    return artifactId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_') + '.zip';
  }
}

String _normalizeBaseUrl(String baseUrl) {
  final trimmed = baseUrl.trim();
  if (trimmed.endsWith('/')) {
    return trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

http.Client _buildClient(bool allowInsecureTls) {
  if (!allowInsecureTls) {
    return http.Client();
  }
  final httpClient = HttpClient()
    ..badCertificateCallback = (cert, host, port) => true;
  return IOClient(httpClient);
}
