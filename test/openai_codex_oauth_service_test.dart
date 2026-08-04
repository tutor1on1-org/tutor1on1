import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
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
  test('creates an OpenAI device login with a bare verification URL', () async {
    final now = DateTime.utc(2026, 8, 4, 1);
    final service = OpenAiCodexOAuthService(
      _MemorySecureStorage(),
      now: () => now,
      client: MockClient((request) async {
        expect(request.method, equals('POST'));
        expect(
          request.url.toString(),
          equals(
            'https://auth.openai.com/api/accounts/deviceauth/usercode',
          ),
        );
        expect(
          jsonDecode(request.body),
          equals(<String, dynamic>{
            'client_id': 'app_EMoamEEZ73f0CkXaXp7hrann',
          }),
        );
        return http.Response(
          jsonEncode(<String, dynamic>{
            'device_auth_id': 'device-auth-id',
            'user_code': 'ABCD-EFGH',
            'interval': '5',
          }),
          200,
        );
      }),
    );

    final attempt = await service.createLoginAttempt();
    final uri = Uri.parse(attempt.authUrl);

    expect(uri.origin, equals('https://auth.openai.com'));
    expect(uri.path, equals('/codex/device'));
    expect(uri.query, isEmpty);
    expect(attempt.userCode, equals('ABCD-EFGH'));
    expect(attempt.expiresAt, equals(now.add(const Duration(minutes: 15))));
    await attempt.close();
    await attempt.close();
  });

  test('polls idempotently and exchanges a validated device authorization',
      () async {
    var now = DateTime.utc(2026, 8, 4, 1);
    const verifier = 'device-code-verifier';
    final challenge = _pkceChallenge(verifier);
    late Map<String, String> posted;
    var pollCalls = 0;
    final delays = <Duration>[];
    final service = OpenAiCodexOAuthService(
      _MemorySecureStorage(),
      now: () => now,
      delay: (duration) async {
        delays.add(duration);
        now = now.add(duration);
      },
      client: MockClient((request) async {
        if (request.url.path.endsWith('/deviceauth/usercode')) {
          return _deviceCodeResponse(
            expiresAt: now.add(const Duration(minutes: 20)),
          );
        }
        if (request.url.path.endsWith('/deviceauth/token')) {
          pollCalls += 1;
          expect(
            jsonDecode(request.body),
            equals(<String, dynamic>{
              'device_auth_id': 'device-auth-id',
              'user_code': 'ABCD-EFGH',
            }),
          );
          if (pollCalls == 1) {
            return http.Response('{"error":"authorization_pending"}', 403);
          }
          if (pollCalls == 2) {
            return http.Response('{"error":"authorization_pending"}', 404);
          }
          return _deviceAuthorizationResponse(
            verifier: verifier,
            challenge: challenge,
          );
        }
        expect(request.url.path, equals('/oauth/token'));
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

    final attempt = await service.createLoginAttempt();
    final firstWait = attempt.waitForCredentials();
    final secondWait = attempt.waitForCredentials();
    expect(identical(firstWait, secondWait), isTrue);
    final credentials = await firstWait;

    expect(posted['grant_type'], equals('authorization_code'));
    expect(posted['client_id'], equals('app_EMoamEEZ73f0CkXaXp7hrann'));
    expect(posted['code'], equals('authorization-code'));
    expect(posted['code_verifier'], equals(verifier));
    expect(
      posted['redirect_uri'],
      equals('https://auth.openai.com/deviceauth/callback'),
    );
    expect(credentials.accountId, equals('acct_123'));
    expect(credentials.email, equals('user@example.com'));
    expect(credentials.refreshToken, equals('refresh-token'));
    expect(pollCalls, equals(3));
    expect(
      delays,
      equals(<Duration>[
        const Duration(seconds: 5),
        const Duration(seconds: 5),
      ]),
    );
    expect(
      attempt.expiresAt,
      equals(DateTime.utc(2026, 8, 4, 1, 15)),
    );
    await attempt.close();
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

  test('rejects a device authorization with a mismatched PKCE challenge',
      () async {
    final now = DateTime.utc(2026, 8, 4, 1);
    var tokenExchangeCalled = false;
    final service = OpenAiCodexOAuthService(
      _MemorySecureStorage(),
      now: () => now,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/deviceauth/usercode')) {
          return _deviceCodeResponse(
              expiresAt: now.add(const Duration(minutes: 5)));
        }
        if (request.url.path.endsWith('/deviceauth/token')) {
          return _deviceAuthorizationResponse(
            verifier: 'device-code-verifier',
            challenge: _pkceChallenge('different-verifier'),
          );
        }
        tokenExchangeCalled = true;
        return http.Response('{}', 500);
      }),
    );

    final attempt = await service.createLoginAttempt();

    await expectLater(
      attempt.waitForCredentials(),
      throwsA(
        isA<StateError>().having(
          (error) => '$error',
          'message',
          contains('PKCE validation'),
        ),
      ),
    );
    expect(tokenExchangeCalled, isFalse);
    await attempt.close();
  });

  test('cancels a pending device login promptly and idempotently', () async {
    final now = DateTime.utc(2026, 8, 4, 1);
    final delayStarted = Completer<void>();
    final delayRelease = Completer<void>();
    final service = OpenAiCodexOAuthService(
      _MemorySecureStorage(),
      now: () => now,
      delay: (_) {
        delayStarted.complete();
        return delayRelease.future;
      },
      client: MockClient((request) async {
        if (request.url.path.endsWith('/deviceauth/usercode')) {
          return _deviceCodeResponse(
              expiresAt: now.add(const Duration(minutes: 5)));
        }
        return http.Response('{"error":"authorization_pending"}', 403);
      }),
    );

    final attempt = await service.createLoginAttempt();
    final waiting = attempt.waitForCredentials();
    await delayStarted.future;
    final cancellationExpected = expectLater(
      waiting,
      throwsA(
        isA<StateError>().having(
          (error) => '$error',
          'message',
          contains('cancelled'),
        ),
      ),
    );
    await attempt.close();
    await attempt.close();
    await cancellationExpected;
    delayRelease.complete();
  });

  test('expires at the server deadline without polling again', () async {
    var now = DateTime.utc(2026, 8, 4, 1);
    var pollCalls = 0;
    final delays = <Duration>[];
    final service = OpenAiCodexOAuthService(
      _MemorySecureStorage(),
      now: () => now,
      delay: (duration) async {
        delays.add(duration);
        now = now.add(duration);
      },
      client: MockClient((request) async {
        if (request.url.path.endsWith('/deviceauth/usercode')) {
          return _deviceCodeResponse(
            expiresAt: now.add(const Duration(seconds: 2)),
          );
        }
        pollCalls += 1;
        return http.Response('{"error":"authorization_pending"}', 403);
      }),
    );

    final attempt = await service.createLoginAttempt();

    await expectLater(
      attempt.waitForCredentials(),
      throwsA(
        isA<StateError>().having(
          (error) => '$error',
          'message',
          contains('expired'),
        ),
      ),
    );
    expect(pollCalls, equals(1));
    expect(delays, equals(<Duration>[const Duration(seconds: 2)]));
    await attempt.close();
  });

  test('bounds Retry-After while polling a rate-limited device login',
      () async {
    var now = DateTime.utc(2026, 8, 4, 1);
    const verifier = 'device-code-verifier';
    var pollCalls = 0;
    final delays = <Duration>[];
    final service = OpenAiCodexOAuthService(
      _MemorySecureStorage(),
      now: () => now,
      delay: (duration) async {
        delays.add(duration);
        now = now.add(duration);
      },
      client: MockClient((request) async {
        if (request.url.path.endsWith('/deviceauth/usercode')) {
          return _deviceCodeResponse(
              expiresAt: now.add(const Duration(minutes: 5)));
        }
        if (request.url.path.endsWith('/deviceauth/token')) {
          pollCalls += 1;
          if (pollCalls == 1) {
            return http.Response('', 429, headers: <String, String>{
              'Retry-After': '999',
            });
          }
          return _deviceAuthorizationResponse(
            verifier: verifier,
            challenge: _pkceChallenge(verifier),
          );
        }
        return _tokenResponse();
      }),
    );

    final attempt = await service.createLoginAttempt();
    final credentials = await attempt.waitForCredentials();

    expect(credentials.accountId, equals('acct_123'));
    expect(pollCalls, equals(2));
    expect(delays, equals(<Duration>[const Duration(seconds: 60)]));
    await attempt.close();
  });

  test('sanitizes OAuth token exchange failures', () async {
    final now = DateTime.utc(2026, 8, 4, 1);
    const verifier = 'device-code-verifier';
    final service = OpenAiCodexOAuthService(
      _MemorySecureStorage(),
      now: () => now,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/deviceauth/usercode')) {
          return _deviceCodeResponse(
              expiresAt: now.add(const Duration(minutes: 5)));
        }
        if (request.url.path.endsWith('/deviceauth/token')) {
          return _deviceAuthorizationResponse(
            verifier: verifier,
            challenge: _pkceChallenge(verifier),
          );
        }
        return http.Response(
          '{"error":"authorization-code-and-token-must-not-leak"}',
          400,
        );
      }),
    );

    final attempt = await service.createLoginAttempt();
    Object? failure;
    try {
      await attempt.waitForCredentials();
    } catch (error) {
      failure = error;
    }

    expect(failure, isA<http.ClientException>());
    expect('$failure', contains('HTTP 400'));
    expect('$failure', isNot(contains('authorization-code-and-token')));
    await attempt.close();
  });

  test('rejects invalid device polling bounds', () async {
    final now = DateTime.utc(2026, 8, 4, 1);
    for (final interval in <Object>['0', '61', 'invalid']) {
      final service = OpenAiCodexOAuthService(
        _MemorySecureStorage(),
        now: () => now,
        client: MockClient((_) async {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'device_auth_id': 'device-auth-id',
              'user_code': 'ABCD-EFGH',
              'interval': interval,
              'expires_at':
                  now.add(const Duration(minutes: 5)).toIso8601String(),
            }),
            200,
          );
        }),
      );

      await expectLater(
        service.createLoginAttempt(),
        throwsA(isA<StateError>()),
      );
    }
  });

  test('falls back when an optional device expiry is unrecognized', () async {
    final now = DateTime.utc(2026, 8, 4, 1);
    final service = OpenAiCodexOAuthService(
      _MemorySecureStorage(),
      now: () => now,
      client: MockClient((_) async {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'device_auth_id': 'device-auth-id',
            'user_code': 'ABCD-EFGH',
            'interval': '5',
            'expires_at': 'not-an-expiry',
          }),
          200,
        );
      }),
    );

    final attempt = await service.createLoginAttempt();

    expect(attempt.expiresAt, equals(now.add(const Duration(minutes: 15))));
    await attempt.close();
  });
}

http.Response _deviceCodeResponse({required DateTime expiresAt}) {
  return http.Response(
    jsonEncode(<String, dynamic>{
      'device_auth_id': 'device-auth-id',
      'user_code': 'ABCD-EFGH',
      'interval': '5',
      'expires_at': expiresAt.toIso8601String(),
    }),
    200,
  );
}

http.Response _deviceAuthorizationResponse({
  required String verifier,
  required String challenge,
}) {
  return http.Response(
    jsonEncode(<String, dynamic>{
      'authorization_code': 'authorization-code',
      'code_challenge': challenge,
      'code_verifier': verifier,
    }),
    200,
  );
}

http.Response _tokenResponse() {
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
}

String _pkceChallenge(String verifier) {
  return base64Url
      .encode(sha256.convert(utf8.encode(verifier)).bytes)
      .replaceAll('=', '');
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
