import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tutor1on1/services/artifact_sync_api_service.dart';
import 'package:tutor1on1/services/secure_storage_service.dart';

class _MemorySecureStorage extends SecureStorageService {
  @override
  Future<String?> readAuthAccessToken() async => 'token';
}

void main() {
  test('getState2 surfaces neutral transport error and keeps raw debug message',
      () async {
    final service = ArtifactSyncApiService(
      secureStorage: _MemorySecureStorage(),
      baseUrl: 'https://api.tutor1on1.org',
      client: MockClient((request) async {
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
  });
}
