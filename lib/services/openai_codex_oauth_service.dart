import 'dart:convert';
import 'dart:math';

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
    required this.state,
    required this.verifier,
    required this.waitForCode,
    required this.close,
  });

  final String authUrl;
  final String state;
  final String verifier;
  final Future<String?> Function() waitForCode;
  final Future<void> Function() close;
}

class OpenAiCodexOAuthService {
  OpenAiCodexOAuthService(
    this._secureStorage, {
    http.Client? client,
  }) : _client = client;

  static const providerId = 'openai-codex';
  static const baseUrl = 'https://chatgpt.com/backend-api';
  static const relayModelsPath = '/api/llm/openai-codex/models';
  static const relayResponsesPath = '/api/llm/openai-codex/responses';
  static const oauthTokenHeader = 'X-OpenAI-OAuth-Token';
  static const accountIdHeader = 'X-OpenAI-Account-ID';
  static const _clientId = 'app_EMoamEEZ73f0CkXaXp7hrann';
  static const _authorizeUrl = 'https://auth.openai.com/oauth/authorize';
  static const _tokenUrl = 'https://auth.openai.com/oauth/token';
  static const _redirectUri = 'http://localhost:1455/auth/callback';
  static const _scope = 'openid profile email offline_access';
  static const _authClaimPath = 'https://api.openai.com/auth';
  static const _profileClaimPath = 'https://api.openai.com/profile';

  final SecureStorageService _secureStorage;
  final http.Client? _client;

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
    final verifier = _base64UrlEncode(_randomBytes(32));
    final challenge =
        _base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes);
    final state = _base64UrlEncode(_randomBytes(16));
    final url = Uri.parse(_authorizeUrl).replace(
      queryParameters: <String, String>{
        'response_type': 'code',
        'client_id': _clientId,
        'redirect_uri': _redirectUri,
        'scope': _scope,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        'id_token_add_organizations': 'true',
        'codex_cli_simplified_flow': 'true',
        'originator': 'openclaw',
      },
    );
    final callback = await _tryStartCallbackServer(state);
    return OpenAiCodexOAuthLoginAttempt(
      authUrl: url.toString(),
      state: state,
      verifier: verifier,
      waitForCode: callback.waitForCode,
      close: callback.close,
    );
  }

  Future<void> openInBrowser(String url) async {
    openBrowserWindow(url);
  }

  Future<OpenAiCodexOAuthCredentials> exchangeAuthorizationInput({
    required String input,
    required String verifier,
    required String expectedState,
  }) async {
    final parsed = _parseAuthorizationInput(input);
    final state = parsed['state'];
    if (state != null && state != expectedState) {
      throw StateError('OAuth state mismatch.');
    }
    final code = parsed['code']?.trim() ?? '';
    if (code.isEmpty) {
      throw StateError('Missing OAuth authorization code.');
    }
    return _exchangeToken(
      <String, String>{
        'grant_type': 'authorization_code',
        'client_id': _clientId,
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': _redirectUri,
      },
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
        'OpenAI OAuth token exchange failed: HTTP ${response.statusCode}: '
        '${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('OpenAI OAuth response is not a JSON object.');
    }
    final access = (decoded['access_token'] as String?)?.trim() ?? '';
    final refresh = (decoded['refresh_token'] as String?)?.trim() ?? '';
    final expiresIn = decoded['expires_in'];
    final expiresInSeconds =
        expiresIn is num ? expiresIn.toInt() : int.tryParse('$expiresIn');
    if (access.isEmpty || refresh.isEmpty || expiresInSeconds == null) {
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
      expiresAtMs:
          DateTime.now().millisecondsSinceEpoch + expiresInSeconds * 1000,
      accountId: accountId,
      email: email == null || email.isEmpty ? null : email,
    );
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

  Map<String, String?> _parseAuthorizationInput(String input) {
    final value = input.trim();
    if (value.isEmpty) {
      return const <String, String?>{};
    }
    final asUri = Uri.tryParse(value);
    if (asUri != null && asUri.hasScheme) {
      return <String, String?>{
        'code': asUri.queryParameters['code'],
        'state': asUri.queryParameters['state'],
      };
    }
    if (value.contains('#')) {
      final parts = value.split('#');
      return <String, String?>{
        'code': parts.isNotEmpty ? parts.first : null,
        'state': parts.length > 1 ? parts[1] : null,
      };
    }
    if (value.contains('code=')) {
      final params = Uri.splitQueryString(
          value.startsWith('?') ? value.substring(1) : value);
      return <String, String?>{
        'code': params['code'],
        'state': params['state'],
      };
    }
    return <String, String?>{'code': value, 'state': null};
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

  Future<_OAuthCallbackServer> _tryStartCallbackServer(String state) async {
    return const _OAuthCallbackServer(
      waitForCode: _noAutomaticAuthorizationCode,
      close: _closeNoopCallback,
    );
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  String _base64UrlEncode(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

Future<String?> _noAutomaticAuthorizationCode() async => null;

Future<void> _closeNoopCallback() async {}

class _OAuthCallbackServer {
  const _OAuthCallbackServer({
    required this.waitForCode,
    required this.close,
  });

  final Future<String?> Function() waitForCode;
  final Future<void> Function() close;
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
