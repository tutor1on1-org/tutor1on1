import 'dart:convert';

import 'package:http/http.dart' as http;

import 'secure_storage_service.dart';

class AuthTokenRefreshException implements Exception {
  AuthTokenRefreshException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AuthTokenRefreshCoordinator {
  AuthTokenRefreshCoordinator._();

  static final Map<String, Future<_RefreshOutcome>> _inFlightByBaseUrl = {};

  static Future<bool> refresh({
    required http.Client client,
    required SecureStorageService secureStorage,
    required String baseUrl,
  }) async {
    final normalizedBaseUrl = _normalizeBaseUrl(baseUrl);
    final existing = _inFlightByBaseUrl[normalizedBaseUrl];
    if (existing != null) {
      return _awaitOutcome(existing);
    }

    final refreshFuture = _performRefresh(
      client: client,
      secureStorage: secureStorage,
      baseUrl: normalizedBaseUrl,
    );
    _inFlightByBaseUrl[normalizedBaseUrl] = refreshFuture;
    try {
      return await _awaitOutcome(refreshFuture);
    } finally {
      if (identical(_inFlightByBaseUrl[normalizedBaseUrl], refreshFuture)) {
        _inFlightByBaseUrl.remove(normalizedBaseUrl);
      }
    }
  }

  static Future<bool> _awaitOutcome(Future<_RefreshOutcome> future) async {
    final outcome = await future;
    if (outcome.errorMessage != null) {
      throw AuthTokenRefreshException(
        outcome.errorMessage!,
        statusCode: outcome.statusCode,
      );
    }
    return outcome.refreshed;
  }

  static Future<_RefreshOutcome> _performRefresh({
    required http.Client client,
    required SecureStorageService secureStorage,
    required String baseUrl,
  }) async {
    final refreshToken =
        (await secureStorage.readAuthRefreshToken())?.trim() ?? '';
    if (refreshToken.isEmpty) {
      return const _RefreshOutcome(refreshed: false);
    }

    http.Response response;
    try {
      response = await client.post(
        Uri.parse('$baseUrl/api/auth/refresh'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );
    } on Exception catch (error) {
      return _RefreshOutcome(
        refreshed: false,
        errorMessage: 'Token refresh failed: $error',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 400 || response.statusCode == 401) {
        final latestRefreshToken =
            (await secureStorage.readAuthRefreshToken())?.trim() ?? '';
        if (latestRefreshToken == refreshToken) {
          await secureStorage.deleteAuthTokens();
        }
        return const _RefreshOutcome(refreshed: false);
      }
      return _RefreshOutcome(
        refreshed: false,
        errorMessage: _extractError(response.body) ?? 'Token refresh failed.',
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return const _RefreshOutcome(
        refreshed: false,
        errorMessage: 'Token refresh response invalid.',
      );
    }

    final accessToken = (decoded['access_token'] as String?)?.trim() ?? '';
    final nextRefreshToken =
        (decoded['refresh_token'] as String?)?.trim() ?? '';
    if (accessToken.isEmpty || nextRefreshToken.isEmpty) {
      return const _RefreshOutcome(
        refreshed: false,
        errorMessage: 'Token refresh response missing tokens.',
      );
    }

    await secureStorage.writeAuthTokens(
      accessToken: accessToken,
      refreshToken: nextRefreshToken,
    );
    return const _RefreshOutcome(refreshed: true);
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

class _RefreshOutcome {
  const _RefreshOutcome({
    required this.refreshed,
    this.errorMessage,
    this.statusCode,
  });

  final bool refreshed;
  final String? errorMessage;
  final int? statusCode;
}
