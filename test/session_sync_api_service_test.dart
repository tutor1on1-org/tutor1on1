import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:family_teacher/services/secure_storage_service.dart';
import 'package:family_teacher/services/session_sync_api_service.dart';

class _TokenSecureStorage extends SecureStorageService {
  @override
  Future<String?> readAuthAccessToken() async => 'token';
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
}
