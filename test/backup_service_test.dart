import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tutor1on1/db/app_database.dart';
import 'package:tutor1on1/security/pin_hasher.dart';
import 'package:tutor1on1/services/backup_service.dart';

void main() {
  test('incomplete browser backup is rejected before local data is cleared',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = BackupService(db);

    final userId = await db.createUser(
      username: 'backup-guard',
      pinHash: PinHasher.hash('backup-guard-pin'),
      role: 'student',
      remoteUserId: 71001,
    );
    final payload = jsonDecode(utf8.decode(await service.exportBytes()))
        as Map<String, dynamic>;
    final tables = payload['tables'] as Map<String, dynamic>;
    final omittedTable = tables.keys.firstWhere((name) => name != 'users');
    tables.remove(omittedTable);

    await expectLater(
      service.restoreFromBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('missing tables'),
        ),
      ),
    );

    expect((await db.getUserById(userId))?.username, 'backup-guard');
  });
}
