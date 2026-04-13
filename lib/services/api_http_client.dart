import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'transport_retry_policy.dart';

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
  if (isRetryableTransportException(error)) {
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
