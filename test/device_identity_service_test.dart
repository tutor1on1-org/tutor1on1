import 'package:flutter_test/flutter_test.dart';

import 'package:family_teacher/services/device_identity_service.dart';
import 'package:family_teacher/services/secure_storage_service.dart';

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
    final service = DeviceIdentityService(storage);

    final snapshot = await service.snapshot();

    expect(snapshot.deviceKey, equals('device-123'));
    expect(snapshot.deviceName, equals('Study Laptop'));
    expect(snapshot.platform, isNotEmpty);
    expect(snapshot.localWeekday, inInclusiveRange(1, 7));
    expect(snapshot.localMinuteOfDay, inInclusiveRange(0, 1439));
  });

  test('writeDeviceName falls back to default on blank input', () async {
    final storage = _MemoryDeviceStorage();
    final service = DeviceIdentityService(storage);

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
    );

    final snapshot = await service.snapshot();

    expect(snapshot.deviceName, equals('android'));
  });
}
