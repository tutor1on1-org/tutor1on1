import 'dart:convert';

import 'package:crypto/crypto.dart';

class PinHasher {
  static String hash(String pin) {
    return sha256.convert(utf8.encode(pin)).toString();
  }
}
