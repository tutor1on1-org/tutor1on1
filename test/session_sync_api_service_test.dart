import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:family_teacher/services/secure_storage_service.dart';
import 'package:family_teacher/services/session_sync_api_service.dart';

class _TokenSecureStorage extends SecureStorageService {
  _TokenSecureStorage({
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
  test('listSessionsDelta sends since_id and parses cursor_id', () async {
    late Uri capturedUri;
    final client = MockClient((request) async {
      capturedUri = request.url;
      return http.Response(
        jsonEncode(
          <Map<String, Object?>>[
            <String, Object?>{
              'cursor_id': 11,
              'session_sync_id': 's1',
              'course_id': 44,
              'teacher_user_id': 901,
              'student_user_id': 3001,
              'sender_user_id': 3001,
              'updated_at': '2026-02-27T09:00:00Z',
              'envelope': 'ZW52',
              'envelope_hash': 'hash',
            },
          ],
        ),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final api = SessionSyncApiService(
      secureStorage: _TokenSecureStorage(),
      baseUrl: 'https://example.com',
      client: client,
    );

    final result = await api.listSessionsDelta(
      since: '2026-02-27T09:00:00Z',
      sinceId: 10,
      limit: 5,
    );

    expect(capturedUri.path, equals('/api/sessions/sync/list'));
    expect(
        capturedUri.queryParameters['since'], equals('2026-02-27T09:00:00Z'));
    expect(capturedUri.queryParameters['since_id'], equals('10'));
    expect(capturedUri.queryParameters['limit'], equals('5'));
    expect(result.items, hasLength(1));
    expect(result.items.single.cursorId, equals(11));
  });

  test('listProgressDelta sends since_id and parses cursor_id', () async {
    late Uri capturedUri;
    final client = MockClient((request) async {
      capturedUri = request.url;
      return http.Response(
        jsonEncode(
          <Map<String, Object?>>[
            <String, Object?>{
              'cursor_id': 22,
              'course_id': 55,
              'course_subject': 'Biology',
              'teacher_user_id': 901,
              'student_user_id': 3002,
              'kp_key': '1.1',
              'lit': true,
              'lit_percent': 80,
              'updated_at': '2026-02-27T09:10:00Z',
              'envelope': 'ZW52',
              'envelope_hash': 'hash',
            },
          ],
        ),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final api = SessionSyncApiService(
      secureStorage: _TokenSecureStorage(),
      baseUrl: 'https://example.com',
      client: client,
    );

    final result = await api.listProgressDelta(
      since: '2026-02-27T09:10:00Z',
      sinceId: 21,
      limit: 5,
    );

    expect(capturedUri.path, equals('/api/progress/sync/list'));
    expect(
        capturedUri.queryParameters['since'], equals('2026-02-27T09:10:00Z'));
    expect(capturedUri.queryParameters['since_id'], equals('21'));
    expect(capturedUri.queryParameters['limit'], equals('5'));
    expect(result.items, hasLength(1));
    expect(result.items.single.cursorId, equals(22));
  });

  test('listSessionsDelta rejects since_id when since is missing', () async {
    final api = SessionSyncApiService(
      secureStorage: _TokenSecureStorage(),
      baseUrl: 'https://example.com',
      client: MockClient(
        (_) async => http.Response('[]', 200),
      ),
    );

    await expectLater(
      () => api.listSessionsDelta(sinceId: 10),
      throwsA(isA<SessionSyncApiException>()),
    );
  });

  test('listProgressDelta refreshes token and retries once on 401', () async {
    final storage = _TokenSecureStorage(
      accessToken: 'expired-token',
      refreshToken: 'refresh-1',
    );
    var refreshCalls = 0;
    var listCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/auth/refresh') {
        refreshCalls++;
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['refresh_token'], equals('refresh-1'));
        return http.Response(
          jsonEncode(<String, Object?>{
            'access_token': 'fresh-token',
            'refresh_token': 'refresh-2',
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/api/progress/sync/list') {
        listCalls++;
        final auth = request.headers['Authorization'];
        if (auth == 'Bearer expired-token') {
          return http.Response('{"message":"unauthorized"}', 401);
        }
        expect(auth, equals('Bearer fresh-token'));
        return http.Response('[]', 200);
      }
      fail('Unexpected request: ${request.url.path}');
    });
    final api = SessionSyncApiService(
      secureStorage: storage,
      baseUrl: 'https://example.com',
      client: client,
    );

    final result = await api.listProgressDelta();

    expect(result.items, isEmpty);
    expect(refreshCalls, equals(1));
    expect(listCalls, equals(2));
    expect(await storage.readAuthAccessToken(), equals('fresh-token'));
    expect(await storage.readAuthRefreshToken(), equals('refresh-2'));
  });
}
