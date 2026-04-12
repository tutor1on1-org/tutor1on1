import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

typedef FirstPartyApiHttpClientFactory = http.Client Function();

http.Client buildFirstPartyApiHttpClient({
  required bool allowInsecureTls,
}) {
  final httpClient = HttpClient()
    ..findProxy = ((_) => 'DIRECT')
    ..connectionTimeout = const Duration(seconds: 15);
  if (allowInsecureTls) {
    httpClient.badCertificateCallback = (cert, host, port) => true;
  }
  return IOClient(httpClient);
}

bool isFreshFirstPartyApiClientRetryableError(Object error) {
  final message = error.toString();
  if (error is TimeoutException ||
      error is SocketException ||
      error is HttpException ||
      error is HandshakeException ||
      error is http.ClientException) {
    return true;
  }
  return message.contains('Failed host lookup') ||
      message.contains('No address associated with hostname') ||
      message.contains('Connection reset') ||
      message.contains('Connection closed') ||
      message.contains('Software caused connection abort') ||
      message.contains('errno = 7') ||
      message.contains('errno = 11001');
}
