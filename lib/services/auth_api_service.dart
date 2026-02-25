import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class AuthApiException implements Exception {
  AuthApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AuthResponse {
  AuthResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresIn,
    required this.userId,
    required this.role,
    required this.teacherId,
  });

  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final int expiresIn;
  final int userId;
  final String role;
  final int? teacherId;

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      accessToken: (json['access_token'] as String?) ?? '',
      refreshToken: (json['refresh_token'] as String?) ?? '',
      tokenType: (json['token_type'] as String?) ?? 'bearer',
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 0,
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      role: (json['role'] as String?) ?? 'student',
      teacherId: (json['teacher_id'] as num?)?.toInt(),
    );
  }
}

class AuthApiService {
  AuthApiService({
    required String baseUrl,
    required bool allowInsecureTls,
    http.Client? client,
  })  : _baseUrl = _normalizeBaseUrl(baseUrl),
        _client = client ?? _buildClient(allowInsecureTls);

  final String _baseUrl;
  final http.Client _client;

  Future<AuthResponse> login({
    required String username,
    required String password,
  }) async {
    return _post('/api/auth/login', {
      'username': username.trim(),
      'password': password,
    });
  }

  Future<AuthResponse> registerStudent({
    required String username,
    required String email,
    required String password,
  }) async {
    return _post('/api/auth/register-student', {
      'username': username.trim(),
      'email': email.trim(),
      'password': password,
    });
  }

  Future<AuthResponse> registerTeacher({
    required String username,
    required String email,
    required String password,
    required String displayName,
    String? bio,
    String? avatarUrl,
    String? contact,
    bool contactPublished = false,
  }) async {
    return _post('/api/auth/register-teacher', {
      'username': username.trim(),
      'email': email.trim(),
      'password': password,
      'display_name': displayName.trim(),
      'bio': bio?.trim() ?? '',
      'avatar_url': avatarUrl?.trim() ?? '',
      'contact': contact?.trim() ?? '',
      'contact_published': contactPublished,
    });
  }

  Future<AuthResponse> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_baseUrl$path');
    http.Response response;
    try {
      response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } on Exception catch (error) {
      throw AuthApiException('Request failed: $error');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthApiException(
        _extractError(response.body) ?? 'Request failed.',
        statusCode: response.statusCode,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw AuthApiException('Unexpected response format.');
    }
    return AuthResponse.fromJson(decoded);
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
