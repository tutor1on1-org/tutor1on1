import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

bool isRetryableTransportException(Object error) {
  return error is SocketException ||
      error is HandshakeException ||
      error is HttpException ||
      error is TimeoutException ||
      error is http.ClientException;
}

bool isRetryableHttpStatus(int statusCode) {
  return statusCode == 429 || (statusCode >= 500 && statusCode < 600);
}
