import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:tutor1on1/services/device_identity_service.dart';
import 'package:tutor1on1/services/secure_storage_service.dart';

class _MemoryDeviceStorage extends SecureStorageService {
  String? _deviceKey;
  String? _deviceName;

  @override
  Future<String?> readAuthDeviceKey() async => _deviceKey;

  @override
  Future<void> writeAuthDeviceKey(String value) async {
    _deviceKey = value.trim();
  }

  @override
  Future<String?> readAuthDeviceName() async => _deviceName;

  @override
  Future<void> writeAuthDeviceName(String value) async {
    _deviceName = value.trim();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('snapshot reuses stored device identity fields', () async {
    final storage = _MemoryDeviceStorage();
    await storage.writeAuthDeviceKey('device-123');
    await storage.writeAuthDeviceName('Study Laptop');
    final backupFile = await _tempBackupFile('reuse-stored');
    final service = DeviceIdentityService(
      storage,
      deviceKeyBackupFileProvider: () async => backupFile,
    );

    final snapshot = await service.snapshot();

    expect(snapshot.deviceKey, equals('device-123'));
    expect((await backupFile.readAsString()).trim(), equals('device-123'));
    expect(snapshot.deviceName, equals('Study Laptop'));
    expect(snapshot.platform, isNotEmpty);
    expect(snapshot.localWeekday, inInclusiveRange(1, 7));
    expect(snapshot.localMinuteOfDay, inInclusiveRange(0, 1439));
  });

  test('writeDeviceName falls back to default on blank input', () async {
    final storage = _MemoryDeviceStorage();
    final service = DeviceIdentityService(
      storage,
      deviceKeyBackupFileProvider: () async => null,
    );

    await service.writeDeviceName('   ');

    expect(
      await storage.readAuthDeviceName(),
      equals(DeviceIdentityService.defaultDeviceName()),
    );
  });

  test('snapshot falls back to platform name when hostname lookup fails',
      () async {
    final storage = _MemoryDeviceStorage();
    final service = DeviceIdentityService(
      storage,
      hostnameProvider: () => throw StateError('hostname unavailable'),
      platformProvider: () => 'android',
      deviceKeyBackupFileProvider: () async => null,
    );

    final snapshot = await service.snapshot();

    expect(snapshot.deviceName, equals('android'));
  });

  test('snapshot restores device key from backup file', () async {
    final storage = _MemoryDeviceStorage();
    final backupFile = await _tempBackupFile('restore');
    await backupFile.parent.create(recursive: true);
    await backupFile.writeAsString('backup-device\n');
    final service = DeviceIdentityService(
      storage,
      deviceKeyBackupFileProvider: () async => backupFile,
    );

    final snapshot = await service.snapshot();

    expect(snapshot.deviceKey, equals('backup-device'));
    expect(await storage.readAuthDeviceKey(), equals('backup-device'));
  });
}

Future<File> _tempBackupFile(String name) async {
  final tempDir = await Directory.systemTemp.createTemp(
    'device-identity-$name-',
  );
  addTearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });
  return File(p.join(tempDir.path, 'identity', 'auth_device_key.txt'));
}
