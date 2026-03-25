import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tutor1on1/services/marketplace_api_service.dart';
import 'package:tutor1on1/services/secure_storage_service.dart';

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

  test('listAccountDevices decodes current-device flags', () async {
    final api = MarketplaceApiService(
      secureStorage: _TokenSecureStorageService(accessToken: 'token'),
      baseUrl: 'https://example.com',
      client: MockClient((request) async {
        expect(request.headers['Authorization'], equals('Bearer token'));
        expect(request.url.path, equals('/api/account/devices'));
        return http.Response(
          '''
[
  {
    "device_key":"device-a",
    "device_name":"Laptop",
    "platform":"windows",
    "timezone_name":"UTC",
    "timezone_offset_minutes":0,
    "app_version":"1.0.0",
    "last_seen_at":"2026-03-19T10:00:00Z",
    "online":true,
    "is_current":true
  }
]
''',
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final devices = await api.listAccountDevices();

    expect(devices, hasLength(1));
    expect(devices.first.deviceName, equals('Laptop'));
    expect(devices.first.isCurrent, isTrue);
    expect(devices.first.online, isTrue);
  });

  test('getAccountProfile decodes recovery email payload', () async {
    final api = MarketplaceApiService(
      secureStorage: _TokenSecureStorageService(accessToken: 'token'),
      baseUrl: 'https://example.com',
      client: MockClient((request) async {
        expect(request.headers['Authorization'], equals('Bearer token'));
        expect(request.url.path, equals('/api/account/profile'));
        return http.Response(
          '''
{
  "user_id": 9,
  "username": "student1",
  "email": "student@example.com",
  "role": "student",
  "has_email": true
}
''',
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final profile = await api.getAccountProfile();

    expect(profile.userId, equals(9));
    expect(profile.username, equals('student1'));
    expect(profile.email, equals('student@example.com'));
    expect(profile.hasEmail, isTrue);
  });

  test('updateRecoveryEmail posts current password and new email', () async {
    final api = MarketplaceApiService(
      secureStorage: _TokenSecureStorageService(accessToken: 'token'),
      baseUrl: 'https://example.com',
      client: MockClient((request) async {
        expect(request.method, equals('POST'));
        expect(request.url.path, equals('/api/account/recovery-email'));
        expect(request.headers['Authorization'], equals('Bearer token'));
        expect(
          request.body,
          contains('"current_password":"secret123"'),
        );
        expect(
          request.body,
          contains('"email":"student@example.com"'),
        );
        return http.Response(
          '{"status":"ok"}',
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    await api.updateRecoveryEmail(
      currentPassword: 'secret123',
      email: 'student@example.com',
    );
  });

  test('deleteAccountDevice returns current-device flag', () async {
    final api = MarketplaceApiService(
      secureStorage: _TokenSecureStorageService(accessToken: 'token'),
      baseUrl: 'https://example.com',
      client: MockClient((request) async {
        expect(request.method, equals('POST'));
        expect(
          request.url.path,
          equals('/api/account/devices/device-a/delete'),
        );
        return http.Response(
          '{"deleted_current_device":true}',
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final result = await api.deleteAccountDevice('device-a');

    expect(result.deletedCurrentDevice, isTrue);
  });
}
