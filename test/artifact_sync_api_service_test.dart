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
  test('agent_tutor requests server-only course scaffolds', () async {
    final service = ArtifactSyncApiService(
      secureStorage: _MemorySecureStorage(),
      baseUrl: 'https://api.tutor1on1.org',
      appLabel: 'agent_tutor',
      client: MockClient((request) async {
        expect(request.url.path, '/api/artifacts/download');
        expect(request.headers['X-Tutor-Client-Mode'], 'agent_tutor');
        return http.Response.bytes(
          <int>[1, 2, 3],
          200,
          headers: <String, String>{
            'x-artifact-id': 'course_bundle:200',
            'x-artifact-class': 'course_bundle',
            'x-artifact-sha256': 'scaffold-sha',
          },
        );
      }),
    );

    final artifact = await service.downloadArtifact('course_bundle:200');

    expect(artifact.sha256, 'scaffold-sha');
  });

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

  test('teacher session delete sends exact server mutation identity', () async {
    final service = ArtifactSyncApiService(
      secureStorage: _MemorySecureStorage(),
      baseUrl: 'https://api.tutor1on1.org',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/api/teacher/student-sessions/delete',
        );
        expect(request.headers['Authorization'], 'Bearer token');
        expect(
          jsonDecode(request.body),
          <String, dynamic>{
            'artifact_id': 'student_kp:3001:200:1.1',
            'session_sync_id': 'session-a',
            'base_sha256': 'base-sha',
          },
        );
        return http.Response(
          '{"status":"deleted"}',
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    await service.deleteStudentSessionAsTeacher(
      artifactId: ' student_kp:3001:200:1.1 ',
      sessionSyncId: ' session-a ',
      baseSha256: ' base-sha ',
    );
  });

  test('teacher session delete maps stale base to artifact conflict', () async {
    final service = ArtifactSyncApiService(
      secureStorage: _MemorySecureStorage(),
      baseUrl: 'https://api.tutor1on1.org',
      client: MockClient((request) async {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'status': 'conflict',
            'conflict_type': 'server_changed',
            'server_sha256': 'server-v2',
            'expected_base': 'server-v1',
          }),
          409,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    await expectLater(
      service.deleteStudentSessionAsTeacher(
        artifactId: 'student_kp:3001:200:1.1',
        sessionSyncId: 'session-a',
        baseSha256: 'server-v1',
      ),
      throwsA(
        isA<ArtifactConflictException>()
            .having(
              (error) => error.message,
              'message',
              'Artifact conflict: server_changed',
            )
            .having(
              (error) => error.serverSha256,
              'serverSha256',
              'server-v2',
            )
            .having(
              (error) => error.expectedBaseSha256,
              'expectedBaseSha256',
              'server-v1',
            ),
      ),
    );
  });
}
