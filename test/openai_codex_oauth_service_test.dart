import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tutor1on1/services/openai_codex_oauth_service.dart';
import 'package:tutor1on1/services/secure_storage_service.dart';

class _MemorySecureStorage implements SecureStorageService {
  final Map<String, String> values = <String, String>{};

  @override
  int? get boundAuthRemoteUserId => null;

  @override
  Future<String?> readOAuthCredentials(String providerId) async {
    return values['oauth:$providerId'];
  }

  @override
  Future<void> writeOAuthCredentials(String providerId, String value) async {
    values['oauth:$providerId'] = value;
  }

  @override
  Future<void> deleteOAuthCredentials(String providerId) async {
    values.remove('oauth:$providerId');
  }

  @override
  Future<String?> readAuthAccessToken() async => values['auth:access'];

  @override
  Future<String?> readAuthRefreshToken() async => values['auth:refresh'];

  @override
  Future<void> writeAuthTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    values['auth:access'] = accessToken;
    values['auth:refresh'] = refreshToken;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('creates direct OpenAI PKCE login for manual browser completion',
      () async {
    final attempt = await OpenAiCodexOAuthService(_MemorySecureStorage())
        .createLoginAttempt();
    final uri = Uri.parse(attempt.authUrl);

    expect(uri.origin, equals('https://auth.openai.com'));
    expect(uri.path, equals('/oauth/authorize'));
    expect(uri.queryParameters['response_type'], equals('code'));
    expect(
      uri.queryParameters['redirect_uri'],
      equals('http://localhost:1455/auth/callback'),
    );
    expect(uri.queryParameters['code_challenge_method'], equals('S256'));
    expect(uri.queryParameters['code_challenge'], isNotEmpty);
    expect(uri.queryParameters['state'], equals(attempt.state));
    expect(attempt.verifier, isNotEmpty);
    expect(await attempt.waitForCode(), isNull);
    await attempt.close();
  });

  test('exchanges authorization code directly with OpenAI', () async {
    late Map<String, String> posted;
    final service = OpenAiCodexOAuthService(
      _MemorySecureStorage(),
      client: MockClient((request) async {
        expect(request.method, equals('POST'));
        expect(
          request.url.toString(),
          equals('https://auth.openai.com/oauth/token'),
        );
        posted = Uri.splitQueryString(request.body);
        return http.Response(
          jsonEncode(<String, dynamic>{
            'access_token': _jwt(
              accountId: 'acct_123',
              email: 'user@example.com',
            ),
            'refresh_token': 'refresh-token',
            'expires_in': 3600,
          }),
          200,
        );
      }),
    );

    final credentials = await service.exchangeAuthorizationInput(
      input: 'http://localhost:1455/auth/callback?code=auth-code&state=state-1',
      verifier: 'verifier-1',
      expectedState: 'state-1',
    );

    expect(posted['grant_type'], equals('authorization_code'));
    expect(posted['client_id'], equals('app_EMoamEEZ73f0CkXaXp7hrann'));
    expect(posted['code'], equals('auth-code'));
    expect(posted['code_verifier'], equals('verifier-1'));
    expect(
      posted['redirect_uri'],
      equals('http://localhost:1455/auth/callback'),
    );
    expect(credentials.accountId, equals('acct_123'));
    expect(credentials.email, equals('user@example.com'));
    expect(credentials.refreshToken, equals('refresh-token'));
  });

  test('refreshes expired credentials directly and persists replacement',
      () async {
    final storage = _MemorySecureStorage();
    final expired = OpenAiCodexOAuthCredentials(
      accessToken: _jwt(accountId: 'acct_123'),
      refreshToken: 'old-refresh',
      expiresAtMs: DateTime.now().millisecondsSinceEpoch - 1000,
      accountId: 'acct_123',
    );
    await storage.writeOAuthCredentials(
      OpenAiCodexOAuthService.providerId,
      jsonEncode(expired.toJson()),
    );
    final service = OpenAiCodexOAuthService(
      storage,
      client: MockClient((request) async {
        final posted = Uri.splitQueryString(request.body);
        expect(request.url.host, equals('auth.openai.com'));
        expect(posted['grant_type'], equals('refresh_token'));
        expect(posted['refresh_token'], equals('old-refresh'));
        return http.Response(
          jsonEncode(<String, dynamic>{
            'access_token': _jwt(
              accountId: 'acct_123',
              email: 'fresh@example.com',
            ),
            'refresh_token': 'new-refresh',
            'expires_in': 3600,
          }),
          200,
        );
      }),
    );

    final credentials = await service.resolveValidCredentials();
    final stored = OpenAiCodexOAuthCredentials.fromJsonString(
      await storage.readOAuthCredentials(OpenAiCodexOAuthService.providerId),
    );

    expect(credentials.refreshToken, equals('new-refresh'));
    expect(credentials.email, equals('fresh@example.com'));
    expect(stored!.refreshToken, equals('new-refresh'));
  });

  test('fetches models through authenticated Tutor relay with transient token',
      () async {
    final storage = _MemorySecureStorage()
      ..values['auth:access'] = 'tutor-access-token';
    final credentials = OpenAiCodexOAuthCredentials(
      accessToken: 'openai-access-token',
      refreshToken: 'openai-refresh-token',
      expiresAtMs: 4102444800000,
      accountId: 'acct_123',
      email: 'user@example.com',
    );
    final service = OpenAiCodexOAuthService(
      storage,
      client: MockClient((request) async {
        expect(request.method, equals('GET'));
        expect(
          request.url.toString(),
          equals(
            'https://api.tutor1on1.org'
            '/api/llm/openai-codex/models?client_version=1.0.61',
          ),
        );
        expect(
          request.headers['authorization'],
          equals('Bearer tutor-access-token'),
        );
        expect(
          request.headers['x-openai-oauth-token'],
          equals('openai-access-token'),
        );
        expect(request.headers['x-openai-account-id'], equals('acct_123'));
        expect(request.headers.values, isNot(contains('openai-refresh-token')));
        expect(request.headers, isNot(contains('chatgpt-account-id')));
        return http.Response(
          jsonEncode(<String, dynamic>{
            'models': <Map<String, dynamic>>[
              <String, dynamic>{
                'slug': 'gpt-later',
                'visibility': 'list',
                'supported_in_api': true,
                'priority': 2,
              },
              <String, dynamic>{
                'slug': 'gpt-hidden',
                'visibility': 'hide',
                'supported_in_api': true,
                'priority': 0,
              },
              <String, dynamic>{
                'slug': 'gpt-first',
                'visibility': 'list',
                'supported_in_api': true,
                'priority': 1,
              },
              <String, dynamic>{
                'slug': 'gpt-cli-only',
                'visibility': 'list',
                'supported_in_api': false,
                'priority': 0,
              },
            ],
          }),
          200,
        );
      }),
    );

    final models = await service.fetchAvailableModelIds(
      credentials: credentials,
      clientVersion: '1.0.61',
    );

    expect(models, equals(<String>['gpt-first', 'gpt-later']));
  });

  test('refreshes expired Tutor auth once before retrying model relay',
      () async {
    final storage = _MemorySecureStorage()
      ..values['auth:access'] = 'expired-tutor-token'
      ..values['auth:refresh'] = 'tutor-refresh-token';
    var modelCalls = 0;
    var refreshCalls = 0;
    final service = OpenAiCodexOAuthService(
      storage,
      client: MockClient((request) async {
        if (request.url.path == '/api/auth/refresh') {
          refreshCalls += 1;
          expect(request.method, equals('POST'));
          expect(
            jsonDecode(request.body),
            equals(<String, dynamic>{
              'refresh_token': 'tutor-refresh-token',
            }),
          );
          return http.Response(
            jsonEncode(<String, dynamic>{
              'access_token': 'fresh-tutor-token',
              'refresh_token': 'fresh-tutor-refresh-token',
            }),
            200,
          );
        }
        modelCalls += 1;
        expect(
          request.url.path,
          equals('/api/llm/openai-codex/models'),
        );
        if (modelCalls == 1) {
          expect(
            request.headers['authorization'],
            equals('Bearer expired-tutor-token'),
          );
          return http.Response('{"error":"expired"}', 401);
        }
        expect(
          request.headers['authorization'],
          equals('Bearer fresh-tutor-token'),
        );
        return http.Response(
          jsonEncode(<String, dynamic>{
            'models': <Map<String, dynamic>>[
              <String, dynamic>{
                'slug': 'gpt-refreshed',
                'visibility': 'list',
                'supported_in_api': true,
                'priority': 1,
              },
            ],
          }),
          200,
        );
      }),
    );

    final models = await service.fetchAvailableModelIds(
      credentials: const OpenAiCodexOAuthCredentials(
        accessToken: 'openai-access-token',
        refreshToken: 'openai-refresh-token',
        expiresAtMs: 4102444800000,
        accountId: 'acct_123',
      ),
      clientVersion: '1.0.61',
    );

    expect(models, equals(<String>['gpt-refreshed']));
    expect(modelCalls, equals(2));
    expect(refreshCalls, equals(1));
    expect(storage.values['auth:access'], equals('fresh-tutor-token'));
  });

  test('rejects mismatched OAuth state', () async {
    final service = OpenAiCodexOAuthService(_MemorySecureStorage());

    expect(
      () => service.exchangeAuthorizationInput(
        input: 'http://localhost:1455/auth/callback?code=auth-code&state=bad',
        verifier: 'verifier-1',
        expectedState: 'good',
      ),
      throwsStateError,
    );
  });
}

String _jwt({required String accountId, String? email}) {
  final header = _base64UrlJson(<String, dynamic>{'alg': 'none'});
  final payload = _base64UrlJson(<String, dynamic>{
    'https://api.openai.com/auth': <String, dynamic>{
      'chatgpt_account_id': accountId,
    },
    if (email != null)
      'https://api.openai.com/profile': <String, dynamic>{
        'email': email,
      },
  });
  return '$header.$payload.signature';
}

String _base64UrlJson(Map<String, dynamic> value) {
  return base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
}
