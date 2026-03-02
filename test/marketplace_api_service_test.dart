import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:family_teacher/services/marketplace_api_service.dart';
import 'package:family_teacher/services/secure_storage_service.dart';

class _TokenSecureStorageService extends SecureStorageService {
  _TokenSecureStorageService({
    required String accessToken,
    this.refreshToken = 'refresh-token',
  }) : _accessToken = accessToken;

  String _accessToken;
  String refreshToken;

  @override
  Future<String?> readAuthAccessToken() async => _accessToken;

  @override
  Future<String?> readAuthRefreshToken() async => refreshToken;

  @override
  Future<void> writeAuthTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessToken = accessToken;
    this.refreshToken = refreshToken;
  }

  @override
  Future<void> deleteAuthTokens() async {
    _accessToken = '';
    refreshToken = '';
  }
}

void main() {
  test(
    'listStudentQuitRequests returns empty when older server responds 404',
    () async {
      final api = MarketplaceApiService(
        secureStorage: _TokenSecureStorageService(accessToken: 'token'),
        baseUrl: 'https://example.com',
        client: MockClient((request) async {
          expect(request.headers['Authorization'], equals('Bearer token'));
          expect(
            request.url.path,
            equals('/api/enrollments/quit-requests'),
          );
          return http.Response('{"message":"not found"}', 404);
        }),
      );

      final result = await api.listStudentQuitRequests();
      expect(result, isEmpty);
    },
  );

  test('listStudentQuitRequests throws for non-404 failures', () async {
    final api = MarketplaceApiService(
      secureStorage: _TokenSecureStorageService(accessToken: 'token'),
      baseUrl: 'https://example.com',
      client: MockClient(
        (_) async => http.Response('{"message":"server error"}', 500),
      ),
    );

    await expectLater(
      api.listStudentQuitRequests(),
      throwsA(
        isA<MarketplaceApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          500,
        ),
      ),
    );
  });

  test('listEnrollments refreshes token and retries once on 401', () async {
    final storage = _TokenSecureStorageService(
      accessToken: 'expired-token',
      refreshToken: 'refresh-1',
    );
    var refreshCalls = 0;
    var enrollmentCalls = 0;
    final api = MarketplaceApiService(
      secureStorage: storage,
      baseUrl: 'https://example.com',
      client: MockClient((request) async {
        if (request.url.path == '/api/auth/refresh') {
          refreshCalls++;
          expect(request.body.contains('refresh-1'), isTrue);
          return http.Response(
            '{"access_token":"fresh-token","refresh_token":"refresh-2"}',
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/enrollments') {
          enrollmentCalls++;
          final auth = request.headers['Authorization'];
          if (auth == 'Bearer expired-token') {
            return http.Response('{"message":"unauthorized"}', 401);
          }
          expect(auth, equals('Bearer fresh-token'));
          return http.Response('[]', 200);
        }
        fail('Unexpected request: ${request.url.path}');
      }),
    );

    final enrollments = await api.listEnrollments();

    expect(enrollments, isEmpty);
    expect(refreshCalls, equals(1));
    expect(enrollmentCalls, equals(2));
    expect(await storage.readAuthAccessToken(), equals('fresh-token'));
    expect(await storage.readAuthRefreshToken(), equals('refresh-2'));
  });
}
