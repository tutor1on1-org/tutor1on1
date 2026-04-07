import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client buildFirstPartyApiHttpClient({
  required bool allowInsecureTls,
}) {
  final httpClient = HttpClient()..findProxy = (_) => 'DIRECT';
  if (allowInsecureTls) {
    httpClient.badCertificateCallback = (cert, host, port) => true;
  }
  return IOClient(httpClient);
}
