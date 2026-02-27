import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:family_teacher/services/marketplace_api_service.dart';
import 'package:family_teacher/services/secure_storage_service.dart';

class _TokenSecureStorageService extends SecureStorageService {
  _TokenSecureStorageService(this._token);

  final String _token;

  @override
  Future<String?> readAuthAccessToken() async => _token;
}

void main() {
  test(
    'listStudentQuitRequests returns empty when older server responds 404',
    () async {
      final api = MarketplaceApiService(
        secureStorage: _TokenSecureStorageService('token'),
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
      secureStorage: _TokenSecureStorageService('token'),
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
}
