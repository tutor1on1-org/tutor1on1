import 'dart:async';

import 'package:http/http.dart' as http;

bool isRetryableTransportException(Object error) {
  return error is TimeoutException || error is http.ClientException;
}

bool isRetryableHttpStatus(int statusCode) {
  return statusCode == 429 || (statusCode >= 500 && statusCode < 600);
}
