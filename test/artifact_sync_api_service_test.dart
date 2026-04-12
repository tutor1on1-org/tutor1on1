import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tutor1on1/services/artifact_sync_api_service.dart';
import 'package:tutor1on1/services/secure_storage_service.dart';

class _MemorySecureStorage extends SecureStorageService {
  _MemorySecureStorage({
    String accessToken = 'token',
    String refreshToken = 'refresh-token',
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
  test('getState2 surfaces neutral transport error and keeps raw debug message',
      () async {
    var requestCount = 0;
    final service = ArtifactSyncApiService(
      secureStorage: _MemorySecureStorage(),
      baseUrl: 'https://api.tutor1on1.org',
      client: MockClient((request) async {
        requestCount++;
        throw http.ClientException(
          "ClientException with SocketException: Failed host lookup: 'api.tutor1on1.org' (OS Error: No address associated with hostname, errno = 7)",
          request.url,
        );
      }),
    );

    try {
      await service.getState2(artifactClass: 'course_bundle');
      fail('Expected ArtifactSyncApiException.');
    } on ArtifactSyncApiException catch (error) {
      expect(
        error.message,
        'Could not contact api.tutor1on1.org from this device. Check DNS, proxy, VPN, or firewall settings and retry.',
      );
      expect(error.debugMessage, contains('Failed host lookup'));
      expect(error.debugMessage, contains('/api/artifacts/sync/state2'));
    }
    expect(requestCount, equals(1));
  });

  test('owned client retries transient DNS failure with a fresh client',
      () async {
    var factoryCalls = 0;
    final service = ArtifactSyncApiService(
      secureStorage: _MemorySecureStorage(),
      baseUrl: 'https://api.tutor1on1.org',
      clientFactory: () {
        factoryCalls++;
        if (factoryCalls == 1) {
          return MockClient((request) async {
            throw http.ClientException(
              "SocketException: Failed host lookup: 'api.tutor1on1.org'",
              request.url,
            );
          });
        }
        return MockClient((request) async {
          expect(request.url.path, equals('/api/artifacts/sync/state2'));
          return http.Response(
            jsonEncode(<String, dynamic>{'state2': 'server-state'}),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        });
      },
    );

    final state2 = await service.getState2(artifactClass: 'course_bundle');

    expect(state2, equals('server-state'));
    expect(factoryCalls, equals(2));
  });

  test('refresh retries transient DNS failure with a fresh client', () async {
    final storage = _MemorySecureStorage(
      accessToken: 'expired-token',
      refreshToken: 'refresh-1',
    );
    var factoryCalls = 0;
    var firstStateCalls = 0;
    var refreshCalls = 0;
    var secondStateCalls = 0;
    final service = ArtifactSyncApiService(
      secureStorage: storage,
      baseUrl: 'https://api.tutor1on1.org',
      clientFactory: () {
        factoryCalls++;
        if (factoryCalls == 1) {
          return MockClient((request) async {
            if (request.url.path == '/api/artifacts/sync/state2') {
              firstStateCalls++;
              return http.Response('{"message":"unauthorized"}', 401);
            }
            if (request.url.path == '/api/auth/refresh') {
              throw http.ClientException(
                "SocketException: Failed host lookup: 'api.tutor1on1.org'",
                request.url,
              );
            }
            fail('Unexpected request: ${request.url.path}');
          });
        }
        return MockClient((request) async {
          if (request.url.path == '/api/auth/refresh') {
            refreshCalls++;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['refresh_token'], equals('refresh-1'));
            return http.Response(
              '{"access_token":"fresh-token","refresh_token":"refresh-2"}',
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/api/artifacts/sync/state2') {
            secondStateCalls++;
            expect(
              request.headers['Authorization'],
              equals('Bearer fresh-token'),
            );
            return http.Response(
              '{"state2":"fresh-state"}',
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }
          fail('Unexpected request: ${request.url.path}');
        });
      },
    );

    final state2 = await service.getState2();

    expect(state2, equals('fresh-state'));
    expect(factoryCalls, equals(2));
    expect(firstStateCalls, equals(1));
    expect(refreshCalls, equals(1));
    expect(secondStateCalls, equals(1));
    expect(await storage.readAuthAccessToken(), equals('fresh-token'));
    expect(await storage.readAuthRefreshToken(), equals('refresh-2'));
  });
}
