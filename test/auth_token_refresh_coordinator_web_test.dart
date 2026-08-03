@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tutor1on1/services/auth_token_refresh_coordinator.dart';
import 'package:tutor1on1/services/secure_storage_service.dart';

class _BrowserSharedTokenStorage extends SecureStorageService {
  _BrowserSharedTokenStorage({
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
}

String _accessTokenForUser(int remoteUserId) {
  String encodePart(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

  return '${encodePart(<String, dynamic>{'alg': 'none'})}.'
      '${encodePart(<String, dynamic>{'sub': '$remoteUserId'})}.signature';
}

void main() {
  test('browser lock serializes refreshes across independent callers',
      () async {
    final storage = _BrowserSharedTokenStorage(
      accessToken: _accessTokenForUser(3001),
      refreshToken: 'refresh-1',
    )..bindAuthRemoteUser(3001);
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    var firstCalls = 0;
    var secondCalls = 0;
    final firstClient = MockClient((request) async {
      firstCalls += 1;
      firstStarted.complete();
      await releaseFirst.future;
      return http.Response(
        jsonEncode(<String, String>{
          'access_token': _accessTokenForUser(3001),
          'refresh_token': 'refresh-2',
        }),
        200,
      );
    });
    final secondClient = MockClient((request) async {
      secondCalls += 1;
      return http.Response('unexpected second refresh', 500);
    });

    final first = AuthTokenRefreshCoordinator.refresh(
      client: firstClient,
      secureStorage: storage,
      baseUrl: 'https://first-lock.example.com',
      browserAuthUserReader: () => 3001,
    );
    await firstStarted.future;
    final second = AuthTokenRefreshCoordinator.refresh(
      client: secondClient,
      secureStorage: storage,
      baseUrl: 'https://second-lock.example.com',
      browserAuthUserReader: () => 3001,
    );
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(secondCalls, isZero);
    releaseFirst.complete();

    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(firstCalls, equals(1));
    expect(secondCalls, isZero);
    expect(
      await storage.readAuthAccessToken(),
      equals(_accessTokenForUser(3001)),
    );
    expect(await storage.readAuthRefreshToken(), equals('refresh-2'));
  });
}
