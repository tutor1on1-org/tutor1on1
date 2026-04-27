import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tutor1on1/services/openai_codex_oauth_service.dart';
import 'package:tutor1on1/services/secure_storage_service.dart';

class _MemorySecureStorage implements SecureStorageService {
  final Map<String, String> values = <String, String>{};

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('exchanges authorization code for ChatGPT OAuth credentials', () async {
    late Map<String, String> posted;
    final storage = _MemorySecureStorage();
    final service = OpenAiCodexOAuthService(
      storage,
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

  test('refreshes expired stored credentials and persists replacement',
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
