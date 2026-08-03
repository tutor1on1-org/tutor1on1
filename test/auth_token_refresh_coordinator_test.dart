import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tutor1on1/services/auth_token_refresh_coordinator.dart';
import 'package:tutor1on1/services/secure_storage_service.dart';

class _SharedTokenSecureStorage extends SecureStorageService {
  _SharedTokenSecureStorage({
    required String accessToken,
    required String refreshToken,
  })  : _accessToken = accessToken,
        _refreshToken = refreshToken;

  String _accessToken;
  String _refreshToken;

  @override
  Future<String?> readAuthAccessToken() async => _accessToken;

  @override
  Future<String?> readAuthRefreshToken() async => _refreshToken;

  @override
  Future<void> writeAuthTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  @override
  Future<void> deleteAuthTokens() async {
    _accessToken = '';
    _refreshToken = '';
  }
}

String _accessTokenForUser(int remoteUserId) {
  String encodePart(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

  return '${encodePart(<String, dynamic>{'alg': 'none'})}.'
      '${encodePart(<String, dynamic>{'sub': '$remoteUserId'})}.signature';
}

void main() {
  test('does not refresh another account token before the marker changes',
      () async {
    const localUserId = 3001;
    final storage = _SharedTokenSecureStorage(
      accessToken: _accessTokenForUser(4002),
      refreshToken: 'other-account-refresh',
    )..bindAuthRemoteUser(localUserId);
    var refreshCalls = 0;
    final client = MockClient((request) async {
      refreshCalls++;
      return http.Response('{}', 200);
    });

    final refreshed = await AuthTokenRefreshCoordinator.refresh(
      client: client,
      secureStorage: storage,
      baseUrl: 'https://refresh-identity-race.example.com',
      browserAuthUserReader: () => localUserId,
    );

    expect(refreshed, isFalse);
    expect(refreshCalls, isZero);
    expect(
      await storage.readAuthRefreshToken(),
      equals('other-account-refresh'),
    );
  });

  test('rejects a refresh response for another account', () async {
    const localUserId = 3001;
    final originalAccessToken = _accessTokenForUser(localUserId);
    final storage = _SharedTokenSecureStorage(
      accessToken: originalAccessToken,
      refreshToken: 'refresh-1',
    )..bindAuthRemoteUser(localUserId);
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode(<String, String>{
          'access_token': _accessTokenForUser(4002),
          'refresh_token': 'other-account-refresh',
        }),
        200,
      );
    });

    await expectLater(
      AuthTokenRefreshCoordinator.refresh(
        client: client,
        secureStorage: storage,
        baseUrl: 'https://refresh-response-identity.example.com',
        browserAuthUserReader: () => localUserId,
      ),
      throwsA(
        isA<AuthTokenRefreshException>().having(
          (error) => error.message,
          'message',
          'Token refresh response belongs to another account.',
        ),
      ),
    );
    expect(await storage.readAuthAccessToken(), equals(originalAccessToken));
    expect(await storage.readAuthRefreshToken(), equals('refresh-1'));
  });

  test(
    'coalesces concurrent refresh requests and preserves rotated auth tokens',
    () async {
      final storage = _SharedTokenSecureStorage(
        accessToken: 'expired-token',
        refreshToken: 'refresh-1',
      );
      final refreshStarted = Completer<void>();
      final releaseRefresh = Completer<void>();
      var refreshCalls = 0;

      Future<http.Response> handler(http.Request request) async {
        if (request.url.path == '/api/auth/refresh') {
          refreshCalls++;
          if (refreshCalls > 1) {
            return http.Response('{"message":"stale refresh"}', 401);
          }
          if (!refreshStarted.isCompleted) {
            refreshStarted.complete();
          }
          await releaseRefresh.future;
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['refresh_token'], equals('refresh-1'));
          return http.Response(
            '{"access_token":"fresh-token","refresh_token":"refresh-2"}',
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }
        fail('Unexpected request: ${request.url.path}');
      }

      final clientA = MockClient(handler);
      final clientB = MockClient(handler);

      final refreshA = AuthTokenRefreshCoordinator.refresh(
        client: clientA,
        secureStorage: storage,
        baseUrl: 'https://refresh-race.example.com',
      );
      await refreshStarted.future;
      final refreshB = AuthTokenRefreshCoordinator.refresh(
        client: clientB,
        secureStorage: storage,
        baseUrl: 'https://refresh-race.example.com',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      releaseRefresh.complete();

      final refreshed = await Future.wait<bool>(<Future<bool>>[
        refreshA,
        refreshB,
      ]);

      expect(refreshed, everyElement(isTrue));
      expect(refreshCalls, equals(1));
      expect(await storage.readAuthAccessToken(), equals('fresh-token'));
      expect(await storage.readAuthRefreshToken(), equals('refresh-2'));
    },
  );

  test('rejected refresh token invalidates the local auth session', () async {
    final storage = _SharedTokenSecureStorage(
      accessToken: 'expired-token',
      refreshToken: 'revoked-refresh',
    );
    final invalidated = storage.authSessionInvalidated.first;
    final client = MockClient((request) async {
      expect(request.url.path, '/api/auth/refresh');
      return http.Response('{"error":"invalid refresh token"}', 401);
    });

    final refreshed = await AuthTokenRefreshCoordinator.refresh(
      client: client,
      secureStorage: storage,
      baseUrl: 'https://revoked.example.com',
    );

    expect(refreshed, isFalse);
    await expectLater(invalidated, completes);
    expect(await storage.readAuthAccessToken(), isEmpty);
    expect(await storage.readAuthRefreshToken(), isEmpty);
  });

  test('does not overwrite tokens rotated while refresh was in flight',
      () async {
    final storage = _SharedTokenSecureStorage(
      accessToken: 'expired-token',
      refreshToken: 'refresh-1',
    );
    final refreshStarted = Completer<void>();
    final releaseRefresh = Completer<void>();
    final client = MockClient((request) async {
      refreshStarted.complete();
      await releaseRefresh.future;
      return http.Response(
        '{"access_token":"stale-access","refresh_token":"stale-refresh"}',
        200,
      );
    });

    final refresh = AuthTokenRefreshCoordinator.refresh(
      client: client,
      secureStorage: storage,
      baseUrl: 'https://rotated.example.com',
    );
    await refreshStarted.future;
    await storage.writeAuthTokens(
      accessToken: 'other-tab-access',
      refreshToken: 'refresh-2',
    );
    releaseRefresh.complete();

    expect(await refresh, isTrue);
    expect(await storage.readAuthAccessToken(), equals('other-tab-access'));
    expect(await storage.readAuthRefreshToken(), equals('refresh-2'));
  });

  test('does not apply a refresh after the browser account changes', () async {
    final storage = _SharedTokenSecureStorage(
      accessToken: _accessTokenForUser(3001),
      refreshToken: 'refresh-1',
    )..bindAuthRemoteUser(3001);
    final refreshStarted = Completer<void>();
    final releaseRefresh = Completer<void>();
    var browserAuthUserId = 3001;
    final client = MockClient((request) async {
      refreshStarted.complete();
      await releaseRefresh.future;
      return http.Response(
        '{"access_token":"stale-access","refresh_token":"stale-refresh"}',
        200,
      );
    });

    final refresh = AuthTokenRefreshCoordinator.refresh(
      client: client,
      secureStorage: storage,
      baseUrl: 'https://account-change.example.com',
      browserAuthUserReader: () => browserAuthUserId,
    );
    await refreshStarted.future;
    browserAuthUserId = 4002;
    await storage.writeAuthTokens(
      accessToken: _accessTokenForUser(4002),
      refreshToken: 'other-account-refresh',
    );
    releaseRefresh.complete();

    expect(await refresh, isFalse);
    expect(
      await storage.readAuthAccessToken(),
      equals(_accessTokenForUser(4002)),
    );
    expect(
      await storage.readAuthRefreshToken(),
      equals('other-account-refresh'),
    );
  });
}
