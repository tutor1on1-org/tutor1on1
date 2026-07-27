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

void main() {
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
}
