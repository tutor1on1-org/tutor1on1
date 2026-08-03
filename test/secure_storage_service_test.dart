import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/security/hash_utils.dart';
import 'package:tutor1on1/services/secure_storage_service.dart';

void main() {
  test('sync run identity is stable and browser scoped', () {
    expect(
      SecureStorageService.syncRunDeviceHash,
      equals(sha256Hex('tutor1on1:web')),
    );
  });
}
