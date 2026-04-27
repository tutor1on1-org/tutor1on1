import 'dart:convert';

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

  test('public requests retry transient DNS failure with a fresh client',
      () async {
    var factoryCalls = 0;
    final api = MarketplaceApiService(
      secureStorage: _TokenSecureStorageService(accessToken: 'token'),
      baseUrl: 'https://example.com',
      clientFactory: () {
        factoryCalls++;
        if (factoryCalls == 1) {
          return MockClient((request) async {
            throw http.ClientException(
              "SocketException: Failed host lookup: 'example.com'",
              request.url,
            );
          });
        }
        return MockClient((request) async {
          expect(request.url.path, equals('/api/subject-labels'));
          return http.Response('[]', 200);
        });
      },
    );

    final labels = await api.listSubjectLabels();

    expect(labels, isEmpty);
    expect(factoryCalls, equals(2));
  });

  test('updateCourseSubjectLabels does not refresh full course list', () async {
    final api = MarketplaceApiService(
      secureStorage: _TokenSecureStorageService(accessToken: 'token'),
      baseUrl: 'https://example.com',
      client: MockClient((request) async {
        expect(request.headers['Authorization'], equals('Bearer token'));
        expect(
          request.url.path,
          equals('/api/teacher/courses/42/subject-labels'),
        );
        expect(
          jsonDecode(request.body),
          equals(<String, dynamic>{
            'subject_label_ids': <int>[1, 2],
          }),
        );
        return http.Response(
          '''
{
  "course_id": 42,
  "status": "updated",
  "subject_labels": [
    {"subject_label_id": 1, "slug": "math", "name": "Math", "is_active": true},
    {"subject_label_id": 2, "slug": "science", "name": "Science", "is_active": true}
  ]
}
''',
          200,
        );
      }),
    );

    final updated = await api.updateCourseSubjectLabels(
      courseId: 42,
      subjectLabelIds: const <int>[1, 2],
    );

    expect(updated.courseId, equals(42));
    expect(updated.status, equals('updated'));
    expect(
      updated.subjectLabels.map((label) => label.subjectLabelId),
      equals(<int>[1, 2]),
    );
  });

  test('token refresh retries transient DNS failure with a fresh client',
      () async {
    final storage = _TokenSecureStorageService(
      accessToken: 'expired-token',
      refreshToken: 'refresh-1',
    );
    var factoryCalls = 0;
    var firstEnrollmentCalls = 0;
    var refreshCalls = 0;
    var secondEnrollmentCalls = 0;
    final api = MarketplaceApiService(
      secureStorage: storage,
      baseUrl: 'https://example.com',
      clientFactory: () {
        factoryCalls++;
        if (factoryCalls == 1) {
          return MockClient((request) async {
            if (request.url.path == '/api/enrollments') {
              firstEnrollmentCalls++;
              return http.Response('{"message":"unauthorized"}', 401);
            }
            if (request.url.path == '/api/auth/refresh') {
              throw http.ClientException(
                "SocketException: Failed host lookup: 'example.com'",
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
          if (request.url.path == '/api/enrollments') {
            secondEnrollmentCalls++;
            expect(
              request.headers['Authorization'],
              equals('Bearer fresh-token'),
            );
            return http.Response('[]', 200);
          }
          fail('Unexpected request: ${request.url.path}');
        });
      },
    );

    final enrollments = await api.listEnrollments();

    expect(enrollments, isEmpty);
    expect(factoryCalls, equals(2));
    expect(firstEnrollmentCalls, equals(1));
    expect(refreshCalls, equals(1));
    expect(secondEnrollmentCalls, equals(1));
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
