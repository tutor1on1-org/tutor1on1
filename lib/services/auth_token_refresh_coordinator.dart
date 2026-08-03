import 'dart:convert';

import 'package:http/http.dart' as http;

import 'browser_auth_session.dart' as browser_auth;
import 'browser_exclusive_lock.dart';
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

  static Future<String?> readAccessToken({
    required SecureStorageService secureStorage,
    int? Function()? browserAuthUserReader,
  }) async {
    final expectedRemoteUserId = secureStorage.boundAuthRemoteUserId;
    return runWithBrowserExclusiveLock<String?>(
      browserAuthRefreshLockName,
      () => _readAccessTokenForSession(
        secureStorage: secureStorage,
        expectedRemoteUserId: expectedRemoteUserId,
        browserAuthUserReader:
            browserAuthUserReader ?? browser_auth.readBrowserAuthUser,
      ),
    );
  }

  static Future<bool> refresh({
    required http.Client client,
    required SecureStorageService secureStorage,
    required String baseUrl,
    int? Function()? browserAuthUserReader,
  }) async {
    final normalizedBaseUrl = _normalizeBaseUrl(baseUrl);
    final expectedRemoteUserId = secureStorage.boundAuthRemoteUserId;
    final refreshKey = '$normalizedBaseUrl#${expectedRemoteUserId ?? 0}';
    final existing = _inFlightByBaseUrl[refreshKey];
    if (existing != null) {
      return _awaitOutcome(existing);
    }

    final refreshFuture = _performRefreshWithLock(
      client: client,
      secureStorage: secureStorage,
      baseUrl: normalizedBaseUrl,
      expectedRemoteUserId: expectedRemoteUserId,
      browserAuthUserReader:
          browserAuthUserReader ?? browser_auth.readBrowserAuthUser,
    );
    _inFlightByBaseUrl[refreshKey] = refreshFuture;
    try {
      return await _awaitOutcome(refreshFuture);
    } finally {
      if (identical(_inFlightByBaseUrl[refreshKey], refreshFuture)) {
        _inFlightByBaseUrl.remove(refreshKey);
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
    required String accessToken,
    required String refreshToken,
    required int? browserAuthUserId,
    required int? expectedRemoteUserId,
    required int? Function() browserAuthUserReader,
  }) async {
    if (refreshToken.isEmpty) {
      await secureStorage.invalidateAuthSession();
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
      final changed = await _changedSessionOutcome(
        secureStorage: secureStorage,
        expectedAccessToken: accessToken,
        expectedRefreshToken: refreshToken,
        expectedBrowserAuthUserId: browserAuthUserId,
        expectedRemoteUserId: expectedRemoteUserId,
        browserAuthUserReader: browserAuthUserReader,
      );
      if (changed != null) {
        return changed;
      }
      return _RefreshOutcome(
        refreshed: false,
        errorMessage: 'Token refresh failed: $error',
      );
    }

    final changed = await _changedSessionOutcome(
      secureStorage: secureStorage,
      expectedAccessToken: accessToken,
      expectedRefreshToken: refreshToken,
      expectedBrowserAuthUserId: browserAuthUserId,
      expectedRemoteUserId: expectedRemoteUserId,
      browserAuthUserReader: browserAuthUserReader,
    );
    if (changed != null) {
      return changed;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 400 || response.statusCode == 401) {
        await secureStorage.invalidateAuthSession();
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

    final responseAccessToken =
        (decoded['access_token'] as String?)?.trim() ?? '';
    final nextRefreshToken =
        (decoded['refresh_token'] as String?)?.trim() ?? '';
    if (responseAccessToken.isEmpty || nextRefreshToken.isEmpty) {
      return const _RefreshOutcome(
        refreshed: false,
        errorMessage: 'Token refresh response missing tokens.',
      );
    }
    if (!_accessTokenMatchesRemoteUser(
      responseAccessToken,
      expectedRemoteUserId,
    )) {
      return const _RefreshOutcome(
        refreshed: false,
        errorMessage: 'Token refresh response belongs to another account.',
      );
    }

    await secureStorage.writeAuthTokens(
      accessToken: responseAccessToken,
      refreshToken: nextRefreshToken,
    );
    return const _RefreshOutcome(refreshed: true);
  }

  static Future<_RefreshOutcome> _performRefreshWithLock({
    required http.Client client,
    required SecureStorageService secureStorage,
    required String baseUrl,
    required int? expectedRemoteUserId,
    required int? Function() browserAuthUserReader,
  }) async {
    final accessTokenBefore =
        (await secureStorage.readAuthAccessToken())?.trim() ?? '';
    final refreshToken =
        (await secureStorage.readAuthRefreshToken())?.trim() ?? '';
    final accessTokenAfter =
        (await secureStorage.readAuthAccessToken())?.trim() ?? '';
    if (accessTokenBefore != accessTokenAfter ||
        !_accessTokenMatchesRemoteUser(
          accessTokenBefore,
          expectedRemoteUserId,
        )) {
      return const _RefreshOutcome(refreshed: false);
    }
    final outcome = await runWithBrowserExclusiveLock<_RefreshOutcome>(
      browserAuthRefreshLockName,
      () async {
        final browserAuthUserId = browserAuthUserReader();
        if (secureStorage.boundAuthRemoteUserId != expectedRemoteUserId ||
            browserAuthUserId != expectedRemoteUserId) {
          return const _RefreshOutcome(refreshed: false);
        }
        final changed = await _changedSessionOutcome(
          secureStorage: secureStorage,
          expectedAccessToken: accessTokenBefore,
          expectedRefreshToken: refreshToken,
          expectedBrowserAuthUserId: browserAuthUserId,
          expectedRemoteUserId: expectedRemoteUserId,
          browserAuthUserReader: browserAuthUserReader,
        );
        if (changed != null) {
          return changed;
        }
        return _performRefresh(
          client: client,
          secureStorage: secureStorage,
          baseUrl: baseUrl,
          accessToken: accessTokenBefore,
          refreshToken: refreshToken,
          browserAuthUserId: browserAuthUserId,
          expectedRemoteUserId: expectedRemoteUserId,
          browserAuthUserReader: browserAuthUserReader,
        );
      },
    );
    return outcome ??
        const _RefreshOutcome(
          refreshed: false,
          errorMessage: 'Could not acquire the browser auth-token lock.',
        );
  }

  static Future<_RefreshOutcome?> _changedSessionOutcome({
    required SecureStorageService secureStorage,
    required String expectedAccessToken,
    required String expectedRefreshToken,
    required int? expectedBrowserAuthUserId,
    required int? expectedRemoteUserId,
    required int? Function() browserAuthUserReader,
  }) async {
    if (secureStorage.boundAuthRemoteUserId != expectedRemoteUserId) {
      return const _RefreshOutcome(refreshed: false);
    }
    final browserAuthUserIdBefore = browserAuthUserReader();
    final currentAccessTokenBefore =
        (await secureStorage.readAuthAccessToken())?.trim() ?? '';
    final currentRefreshToken =
        (await secureStorage.readAuthRefreshToken())?.trim() ?? '';
    final currentAccessTokenAfter =
        (await secureStorage.readAuthAccessToken())?.trim() ?? '';
    final browserAuthUserIdAfter = browserAuthUserReader();
    if (browserAuthUserIdBefore != expectedBrowserAuthUserId ||
        browserAuthUserIdAfter != expectedBrowserAuthUserId ||
        secureStorage.boundAuthRemoteUserId != expectedRemoteUserId) {
      return const _RefreshOutcome(refreshed: false);
    }
    if (currentAccessTokenBefore != currentAccessTokenAfter) {
      return const _RefreshOutcome(refreshed: false);
    }
    if (currentAccessTokenBefore != expectedAccessToken ||
        currentRefreshToken != expectedRefreshToken) {
      return _RefreshOutcome(
        refreshed: currentRefreshToken.isNotEmpty &&
            _accessTokenMatchesRemoteUser(
              currentAccessTokenBefore,
              expectedRemoteUserId,
            ),
      );
    }
    return null;
  }

  static Future<String?> _readAccessTokenForSession({
    required SecureStorageService secureStorage,
    required int? expectedRemoteUserId,
    required int? Function() browserAuthUserReader,
  }) async {
    if (secureStorage.boundAuthRemoteUserId != expectedRemoteUserId ||
        browserAuthUserReader() != expectedRemoteUserId) {
      return null;
    }
    final token = (await secureStorage.readAuthAccessToken())?.trim() ?? '';
    if (token.isEmpty ||
        secureStorage.boundAuthRemoteUserId != expectedRemoteUserId ||
        browserAuthUserReader() != expectedRemoteUserId ||
        !_accessTokenMatchesRemoteUser(token, expectedRemoteUserId)) {
      return null;
    }
    return token;
  }

  static bool _accessTokenMatchesRemoteUser(
    String token,
    int? expectedRemoteUserId,
  ) {
    if (token.trim().isEmpty) {
      return false;
    }
    if (expectedRemoteUserId == null) {
      return true;
    }
    return _accessTokenRemoteUserId(token) == expectedRemoteUserId;
  }

  static int? _accessTokenRemoteUserId(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      return null;
    }
    try {
      final payload =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final subject = decoded['sub'];
      final remoteUserId = subject is num
          ? subject.toInt()
          : int.tryParse(subject?.toString().trim() ?? '');
      return remoteUserId != null && remoteUserId > 0 ? remoteUserId : null;
    } on Object {
      return null;
    }
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
