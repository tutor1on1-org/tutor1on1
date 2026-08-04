import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../constants.dart';
import '../security/hash_utils.dart';
import 'auth_token_refresh_coordinator.dart';
import 'browser_window.dart';
import 'secure_storage_service.dart';

class OpenAiCodexOAuthCredentials {
  const OpenAiCodexOAuthCredentials({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAtMs,
    required this.accountId,
    this.email,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresAtMs;
  final String accountId;
  final String? email;

  bool get expiresSoon =>
      DateTime.now().millisecondsSinceEpoch + 60000 >= expiresAtMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at_ms': expiresAtMs,
        'account_id': accountId,
        'email': email,
      };

  static OpenAiCodexOAuthCredentials? fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final access = (decoded['access_token'] as String?)?.trim() ?? '';
      final refresh = (decoded['refresh_token'] as String?)?.trim() ?? '';
      final accountId = (decoded['account_id'] as String?)?.trim() ?? '';
      final expiresAt = decoded['expires_at_ms'];
      final expiresAtMs =
          expiresAt is num ? expiresAt.toInt() : int.tryParse('$expiresAt');
      if (access.isEmpty ||
          refresh.isEmpty ||
          accountId.isEmpty ||
          expiresAtMs == null) {
        return null;
      }
      final email = (decoded['email'] as String?)?.trim();
      return OpenAiCodexOAuthCredentials(
        accessToken: access,
        refreshToken: refresh,
        expiresAtMs: expiresAtMs,
        accountId: accountId,
        email: email == null || email.isEmpty ? null : email,
      );
    } catch (_) {
      return null;
    }
  }
}

class OpenAiCodexOAuthLoginAttempt {
  OpenAiCodexOAuthLoginAttempt({
    required this.authUrl,
    required this.userCode,
    required this.expiresAt,
    required this.waitForCredentials,
    required this.close,
  });

  final String authUrl;
  final String userCode;
  final DateTime expiresAt;
  final Future<OpenAiCodexOAuthCredentials> Function() waitForCredentials;
  final Future<void> Function() close;
}

class OpenAiCodexOAuthService {
  OpenAiCodexOAuthService(
    this._secureStorage, {
    http.Client? client,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
  })  : _client = client,
        _now = now ?? DateTime.now,
        _delay = delay ?? Future<void>.delayed;

  static const providerId = 'openai-codex';
  static const baseUrl = 'https://chatgpt.com/backend-api';
  static const relayModelsPath = '/api/llm/openai-codex/models';
  static const relayResponsesPath = '/api/llm/openai-codex/responses';
  static const oauthTokenHeader = 'X-OpenAI-OAuth-Token';
  static const accountIdHeader = 'X-OpenAI-Account-ID';
  static const _clientId = 'app_EMoamEEZ73f0CkXaXp7hrann';
  static const _deviceUserCodeUrl =
      'https://auth.openai.com/api/accounts/deviceauth/usercode';
  static const _deviceTokenUrl =
      'https://auth.openai.com/api/accounts/deviceauth/token';
  static const _deviceVerificationUrl = 'https://auth.openai.com/codex/device';
  static const _tokenUrl = 'https://auth.openai.com/oauth/token';
  static const _deviceRedirectUri =
      'https://auth.openai.com/deviceauth/callback';
  static const _authClaimPath = 'https://api.openai.com/auth';
  static const _profileClaimPath = 'https://api.openai.com/profile';
  static const _maxDeviceLoginDuration = Duration(minutes: 15);
  static const _maxRetryAfter = Duration(seconds: 60);
  static const _maxOAuthResponseBytes = 64 * 1024;
  static const _minPollIntervalSeconds = 1;
  static const _maxPollIntervalSeconds = 60;

  final SecureStorageService _secureStorage;
  final http.Client? _client;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;

  static String get relayModelsUrl =>
      '${_normalizeBaseUrl(kAuthBaseUrl)}$relayModelsPath';

  static String get relayResponsesUrl =>
      '${_normalizeBaseUrl(kAuthBaseUrl)}$relayResponsesPath';

  static String? credentialHash(OpenAiCodexOAuthCredentials? credentials) {
    if (credentials == null) {
      return null;
    }
    final identity = credentials.accountId.trim().isNotEmpty
        ? credentials.accountId.trim()
        : (credentials.email ?? '').trim();
    if (identity.isEmpty) {
      return null;
    }
    return sha256Hex('$providerId:$identity');
  }

  Future<OpenAiCodexOAuthCredentials?> readCredentials() async {
    return OpenAiCodexOAuthCredentials.fromJsonString(
      await _secureStorage.readOAuthCredentials(providerId),
    );
  }

  Future<void> writeCredentials(
    OpenAiCodexOAuthCredentials credentials,
  ) async {
    await _secureStorage.writeOAuthCredentials(
      providerId,
      jsonEncode(credentials.toJson()),
    );
  }

  Future<void> deleteCredentials() {
    return _secureStorage.deleteOAuthCredentials(providerId);
  }

  Future<OpenAiCodexOAuthCredentials> resolveValidCredentials() async {
    final credentials = await readCredentials();
    if (credentials == null) {
      throw StateError('Missing ChatGPT OAuth login. Sign in in Settings.');
    }
    if (!credentials.expiresSoon) {
      return credentials;
    }
    final refreshed = await refreshCredentials(credentials.refreshToken);
    await writeCredentials(refreshed);
    return refreshed;
  }

  Future<OpenAiCodexOAuthLoginAttempt> createLoginAttempt() async {
    final response = await _postJson(
      Uri.parse(_deviceUserCodeUrl),
      const <String, String>{'client_id': _clientId},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 403) {
        throw StateError(
          'ChatGPT device login is unavailable. Enable device code login in '
          'ChatGPT security or workspace settings.',
        );
      }
      throw http.ClientException(
        'OpenAI device login could not start (HTTP ${response.statusCode}).',
      );
    }
    final decoded = _decodeOAuthObject(
      response,
      failureMessage: 'OpenAI device login response is invalid.',
    );
    final deviceAuthId = _requiredOAuthString(
      decoded['device_auth_id'],
      maxLength: 512,
    );
    final userCode = _requiredOAuthString(
      decoded['user_code'] ?? decoded['usercode'],
      maxLength: 128,
    );
    final intervalSeconds = _parseBoundedSeconds(
      decoded['interval'],
      minimum: _minPollIntervalSeconds,
      maximum: _maxPollIntervalSeconds,
    );
    final startedAt = _now().toUtc();
    if (deviceAuthId == null || userCode == null || intervalSeconds == null) {
      throw StateError('OpenAI device login response is invalid.');
    }
    final hardExpiresAt = startedAt.add(_maxDeviceLoginDuration);
    var expiresAt = hardExpiresAt;
    if (decoded.containsKey('expires_at')) {
      final serverExpiresAt = _parseOAuthExpiry(decoded['expires_at']);
      if (serverExpiresAt != null && !serverExpiresAt.isAfter(startedAt)) {
        throw StateError('OpenAI device login response is invalid.');
      }
      if (serverExpiresAt != null && serverExpiresAt.isBefore(hardExpiresAt)) {
        expiresAt = serverExpiresAt;
      }
    }
    final session = _OpenAiCodexDeviceLoginSession(
      interval: Duration(seconds: intervalSeconds),
      expiresAt: expiresAt,
      now: _now,
      delay: _delay,
      poll: () => _postJson(
        Uri.parse(_deviceTokenUrl),
        <String, String>{
          'device_auth_id': deviceAuthId,
          'user_code': userCode,
        },
      ),
      complete: _completeDeviceAuthorization,
      maxRetryAfter: _maxRetryAfter,
    );
    return OpenAiCodexOAuthLoginAttempt(
      authUrl: _deviceVerificationUrl,
      userCode: userCode,
      expiresAt: expiresAt,
      waitForCredentials: session.waitForCredentials,
      close: session.close,
    );
  }

  Future<void> openInBrowser(String url) async {
    openBrowserWindow(url);
  }

  Future<OpenAiCodexOAuthCredentials> _exchangeDeviceAuthorization({
    required String authorizationCode,
    required String verifier,
  }) {
    return _exchangeToken(
      <String, String>{
        'grant_type': 'authorization_code',
        'client_id': _clientId,
        'code': authorizationCode,
        'code_verifier': verifier,
        'redirect_uri': _deviceRedirectUri,
      },
    );
  }

  Future<OpenAiCodexOAuthCredentials> _completeDeviceAuthorization(
    http.Response response,
  ) {
    final decoded = _decodeOAuthObject(
      response,
      failureMessage: 'OpenAI device authorization response is invalid.',
    );
    final authorizationCode = _requiredOAuthString(
      decoded['authorization_code'],
      maxLength: 8192,
    );
    final challenge = _requiredOAuthString(
      decoded['code_challenge'],
      maxLength: 256,
    );
    final verifier = _requiredOAuthString(
      decoded['code_verifier'],
      maxLength: 512,
    );
    if (authorizationCode == null || challenge == null || verifier == null) {
      throw StateError('OpenAI device authorization response is invalid.');
    }
    final calculatedChallenge = base64Url
        .encode(sha256.convert(utf8.encode(verifier)).bytes)
        .replaceAll('=', '');
    if (calculatedChallenge != challenge) {
      throw StateError('OpenAI device authorization failed PKCE validation.');
    }
    return _exchangeDeviceAuthorization(
      authorizationCode: authorizationCode,
      verifier: verifier,
    );
  }

  Future<OpenAiCodexOAuthCredentials> refreshCredentials(
    String refreshToken,
  ) {
    return _exchangeToken(
      <String, String>{
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': _clientId,
      },
    );
  }

  Future<List<String>> fetchAvailableModelIds({
    required OpenAiCodexOAuthCredentials credentials,
    required String clientVersion,
  }) async {
    final accessToken = credentials.accessToken.trim();
    final accountId = credentials.accountId.trim();
    final version = clientVersion.trim();
    if (accessToken.isEmpty || accountId.isEmpty || version.isEmpty) {
      throw StateError('ChatGPT OAuth model request is missing credentials.');
    }
    final uri = Uri.parse(relayModelsUrl).replace(
      queryParameters: <String, String>{'client_version': version},
    );
    Future<http.Response> send(String tutorAccessToken) => _getModels(
          uri,
          <String, String>{
            'Authorization': 'Bearer $tutorAccessToken',
            oauthTokenHeader: accessToken,
            accountIdHeader: accountId,
            'Accept': 'application/json',
          },
        );
    var tutorAccessToken = await _requireTutorAccessToken();
    var response = await send(tutorAccessToken);
    if (response.statusCode == 401 && await _refreshTutorAccessToken()) {
      tutorAccessToken = await _requireTutorAccessToken();
      response = await send(tutorAccessToken);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'OpenAI OAuth model request failed: HTTP ${response.statusCode}: '
        '${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['models'] is! List) {
      throw StateError('OpenAI OAuth model response is missing models.');
    }
    final entries = <_OpenAiCodexModelEntry>[];
    var sourceIndex = 0;
    for (final item in decoded['models'] as List) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final slug = (item['slug'] as String?)?.trim() ?? '';
      final visibility = (item['visibility'] as String?)?.trim() ?? '';
      if (slug.isEmpty ||
          visibility != 'list' ||
          item['supported_in_api'] != true) {
        continue;
      }
      final priority = item['priority'];
      entries.add(
        _OpenAiCodexModelEntry(
          id: slug,
          priority: priority is num ? priority.toInt() : 1 << 30,
          sourceIndex: sourceIndex,
        ),
      );
      sourceIndex++;
    }
    entries.sort((left, right) {
      final priorityOrder = left.priority.compareTo(right.priority);
      return priorityOrder != 0
          ? priorityOrder
          : left.sourceIndex.compareTo(right.sourceIndex);
    });
    final seen = <String>{};
    return entries
        .map((entry) => entry.id)
        .where(seen.add)
        .toList(growable: false);
  }

  Future<String> _requireTutorAccessToken() async {
    final token = await AuthTokenRefreshCoordinator.readAccessToken(
      secureStorage: _secureStorage,
    );
    if (token == null || token.trim().isEmpty) {
      throw StateError('Missing Tutor login. Sign in again.');
    }
    return token.trim();
  }

  Future<bool> _refreshTutorAccessToken() async {
    final injected = _client;
    if (injected != null) {
      return AuthTokenRefreshCoordinator.refresh(
        client: injected,
        secureStorage: _secureStorage,
        baseUrl: kAuthBaseUrl,
      );
    }
    final client = http.Client();
    try {
      return await AuthTokenRefreshCoordinator.refresh(
        client: client,
        secureStorage: _secureStorage,
        baseUrl: kAuthBaseUrl,
      );
    } finally {
      client.close();
    }
  }

  Future<OpenAiCodexOAuthCredentials> _exchangeToken(
    Map<String, String> fields,
  ) async {
    final response = await _postToken(fields);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'OpenAI OAuth token exchange failed (HTTP ${response.statusCode}).',
      );
    }
    final decoded = _decodeOAuthObject(
      response,
      failureMessage: 'OpenAI OAuth response is invalid.',
    );
    final access = (decoded['access_token'] as String?)?.trim() ?? '';
    final refresh = (decoded['refresh_token'] as String?)?.trim() ?? '';
    final expiresIn = decoded['expires_in'];
    final expiresInSeconds =
        expiresIn is num ? expiresIn.toInt() : int.tryParse('$expiresIn');
    if (access.isEmpty ||
        refresh.isEmpty ||
        expiresInSeconds == null ||
        expiresInSeconds <= 0) {
      throw StateError('OpenAI OAuth response is missing token fields.');
    }
    final payload = _decodeJwtPayload(access);
    final auth = payload?[_authClaimPath];
    final profile = payload?[_profileClaimPath];
    final accountId = auth is Map<String, dynamic>
        ? (auth['chatgpt_account_id'] as String?)?.trim() ?? ''
        : '';
    if (accountId.isEmpty) {
      throw StateError('OpenAI OAuth token is missing ChatGPT account id.');
    }
    final email = profile is Map<String, dynamic>
        ? (profile['email'] as String?)?.trim()
        : null;
    return OpenAiCodexOAuthCredentials(
      accessToken: access,
      refreshToken: refresh,
      expiresAtMs: _now().millisecondsSinceEpoch + expiresInSeconds * 1000,
      accountId: accountId,
      email: email == null || email.isEmpty ? null : email,
    );
  }

  Future<http.Response> _postJson(
    Uri uri,
    Map<String, String> fields,
  ) async {
    final injected = _client;
    if (injected != null) {
      return injected
          .post(
            uri,
            headers: const <String, String>{
              'Content-Type': 'application/json',
            },
            body: jsonEncode(fields),
          )
          .timeout(const Duration(seconds: 30));
    }
    final client = http.Client();
    try {
      return await client
          .post(
            uri,
            headers: const <String, String>{
              'Content-Type': 'application/json',
            },
            body: jsonEncode(fields),
          )
          .timeout(const Duration(seconds: 30));
    } finally {
      client.close();
    }
  }

  Future<http.Response> _postToken(Map<String, String> fields) async {
    final injected = _client;
    if (injected != null) {
      return injected
          .post(
            Uri.parse(_tokenUrl),
            headers: const <String, String>{
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: fields,
          )
          .timeout(const Duration(seconds: 30));
    }
    final client = http.Client();
    try {
      return await client
          .post(
            Uri.parse(_tokenUrl),
            headers: const <String, String>{
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: fields,
          )
          .timeout(const Duration(seconds: 30));
    } finally {
      client.close();
    }
  }

  Future<http.Response> _getModels(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final injected = _client;
    if (injected != null) {
      return injected
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 20));
    }
    final client = http.Client();
    try {
      return await client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 20));
    } finally {
      client.close();
    }
  }

  Map<String, dynamic> _decodeOAuthObject(
    http.Response response, {
    required String failureMessage,
  }) {
    if (response.bodyBytes.length > _maxOAuthResponseBytes) {
      throw StateError(failureMessage);
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // The caller receives a bounded error that never includes OAuth data.
    }
    throw StateError(failureMessage);
  }

  String? _requiredOAuthString(Object? value, {required int maxLength}) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > maxLength) {
      return null;
    }
    for (final codeUnit in trimmed.codeUnits) {
      if (codeUnit < 0x20 || codeUnit == 0x7f) {
        return null;
      }
    }
    return trimmed;
  }

  int? _parseBoundedSeconds(
    Object? value, {
    required int minimum,
    required int maximum,
  }) {
    final parsed = value is num
        ? value.toInt()
        : value is String
            ? int.tryParse(value.trim())
            : null;
    if (parsed == null || parsed < minimum || parsed > maximum) {
      return null;
    }
    return parsed;
  }

  DateTime? _parseOAuthExpiry(Object? value) {
    if (value is num) {
      return _epochToUtc(value.toInt());
    }
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    final numeric = int.tryParse(trimmed);
    if (numeric != null) {
      return _epochToUtc(numeric);
    }
    return DateTime.tryParse(trimmed)?.toUtc();
  }

  DateTime? _epochToUtc(int value) {
    if (value <= 0) {
      return null;
    }
    try {
      final milliseconds = value >= 100000000000 ? value : value * 1000;
      return DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
        isUtc: true,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _decodeJwtPayload(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      return null;
    }
    try {
      final decoded =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final payload = jsonDecode(decoded);
      return payload is Map<String, dynamic> ? payload : null;
    } catch (_) {
      return null;
    }
  }
}

class _OpenAiCodexDeviceLoginSession {
  _OpenAiCodexDeviceLoginSession({
    required this.interval,
    required this.expiresAt,
    required this.now,
    required this.delay,
    required this.poll,
    required this.complete,
    required this.maxRetryAfter,
  });

  final Duration interval;
  final DateTime expiresAt;
  final DateTime Function() now;
  final Future<void> Function(Duration) delay;
  final Future<http.Response> Function() poll;
  final Future<OpenAiCodexOAuthCredentials> Function(http.Response) complete;
  final Duration maxRetryAfter;

  final Completer<void> _cancelled = Completer<void>();
  Future<OpenAiCodexOAuthCredentials>? _credentialsFuture;

  Future<OpenAiCodexOAuthCredentials> waitForCredentials() {
    return _credentialsFuture ??= _pollUntilComplete();
  }

  Future<void> close() async {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }

  Future<OpenAiCodexOAuthCredentials> _pollUntilComplete() async {
    while (true) {
      _throwIfCancelledOrExpired();
      final response = await _unlessCancelled(poll());
      _throwIfCancelledOrExpired();
      if (response.statusCode == 403 || response.statusCode == 404) {
        await _wait(interval);
        continue;
      }
      if (response.statusCode == 429) {
        await _wait(_retryAfter(response));
        continue;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException(
          'OpenAI device authorization failed '
          '(HTTP ${response.statusCode}).',
        );
      }
      return _unlessCancelled(complete(response));
    }
  }

  Future<void> _wait(Duration requested) async {
    _throwIfCancelledOrExpired();
    final remaining = expiresAt.difference(now().toUtc());
    final bounded = requested < remaining ? requested : remaining;
    await _unlessCancelled(delay(bounded));
    _throwIfCancelledOrExpired();
  }

  Duration _retryAfter(http.Response response) {
    var raw = '';
    for (final entry in response.headers.entries) {
      if (entry.key.toLowerCase() == 'retry-after') {
        raw = entry.value.trim();
        break;
      }
    }
    final parsed = int.tryParse(raw);
    if (parsed == null) {
      return interval;
    }
    final seconds = parsed.clamp(1, maxRetryAfter.inSeconds).toInt();
    return Duration(seconds: seconds);
  }

  Future<T> _unlessCancelled<T>(Future<T> operation) {
    if (_cancelled.isCompleted) {
      return Future<T>.error(
        StateError('ChatGPT device login was cancelled.'),
      );
    }
    return Future.any<T>(<Future<T>>[
      operation,
      _cancelled.future.then<T>(
        (_) => throw StateError('ChatGPT device login was cancelled.'),
      ),
    ]);
  }

  void _throwIfCancelledOrExpired() {
    if (_cancelled.isCompleted) {
      throw StateError('ChatGPT device login was cancelled.');
    }
    if (!now().toUtc().isBefore(expiresAt)) {
      throw StateError('ChatGPT device login expired. Start again.');
    }
  }
}

class _OpenAiCodexModelEntry {
  const _OpenAiCodexModelEntry({
    required this.id,
    required this.priority,
    required this.sourceIndex,
  });

  final String id;
  final int priority;
  final int sourceIndex;
}

String _normalizeBaseUrl(String value) {
  var trimmed = value.trim();
  while (trimmed.endsWith('/')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}
