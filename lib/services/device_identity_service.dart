import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'secure_storage_service.dart';

class DeviceIdentitySnapshot {
  const DeviceIdentitySnapshot({
    required this.deviceKey,
    required this.deviceName,
    required this.platform,
    required this.timezoneName,
    required this.timezoneOffsetMinutes,
    required this.localWeekday,
    required this.localMinuteOfDay,
    required this.appVersion,
  });

  final String deviceKey;
  final String deviceName;
  final String platform;
  final String timezoneName;
  final int timezoneOffsetMinutes;
  final int localWeekday;
  final int localMinuteOfDay;
  final String appVersion;
}

class DeviceIdentityService {
  DeviceIdentityService(
    this._secureStorage, {
    String Function()? hostnameProvider,
    String Function()? platformProvider,
    Future<File?> Function()? deviceKeyBackupFileProvider,
  })  : _hostnameProvider = hostnameProvider ?? _readLocalHostname,
        _platformProvider = platformProvider ?? _readPlatform,
        _deviceKeyBackupFileProvider =
            deviceKeyBackupFileProvider ?? _defaultDeviceKeyBackupFile;

  final SecureStorageService _secureStorage;
  final String Function() _hostnameProvider;
  final String Function() _platformProvider;
  final Future<File?> Function() _deviceKeyBackupFileProvider;
  static const Uuid _uuid = Uuid();
  static const int _maxDeviceKeyLength = 128;

  Future<String> ensureDeviceKey() async {
    final existing = _normalizeDeviceKey(
      await _secureStorage.readAuthDeviceKey(),
    );
    if (existing.isNotEmpty) {
      await _writeDeviceKeyBackup(existing);
      return existing;
    }
    final backedUp = await _readDeviceKeyBackup();
    if (backedUp.isNotEmpty) {
      await _secureStorage.writeAuthDeviceKey(backedUp);
      return backedUp;
    }
    final generated = _uuid.v4();
    await _secureStorage.writeAuthDeviceKey(generated);
    await _writeDeviceKeyBackup(generated);
    return generated;
  }

  Future<String> readDeviceNameOrDefault() async {
    final existing = (await _secureStorage.readAuthDeviceName())?.trim() ?? '';
    if (existing.isNotEmpty) {
      return existing;
    }
    final fallback = defaultDeviceName(
      hostnameProvider: _hostnameProvider,
      platformProvider: _platformProvider,
    );
    await _secureStorage.writeAuthDeviceName(fallback);
    return fallback;
  }

  Future<void> writeDeviceName(String value) async {
    final normalized = value.trim().isEmpty
        ? defaultDeviceName(
            hostnameProvider: _hostnameProvider,
            platformProvider: _platformProvider,
          )
        : value.trim();
    await _secureStorage.writeAuthDeviceName(normalized);
  }

  Future<DeviceIdentitySnapshot> snapshot() async {
    final now = DateTime.now();
    return DeviceIdentitySnapshot(
      deviceKey: await ensureDeviceKey(),
      deviceName: await readDeviceNameOrDefault(),
      platform: Platform.operatingSystem,
      timezoneName: now.timeZoneName.trim(),
      timezoneOffsetMinutes: now.timeZoneOffset.inMinutes,
      localWeekday: now.weekday,
      localMinuteOfDay: now.hour * 60 + now.minute,
      appVersion: '',
    );
  }

  static String defaultDeviceName({
    String Function()? hostnameProvider,
    String Function()? platformProvider,
  }) {
    final host = _readLocalHostnameSafely(
      hostnameProvider ?? _readLocalHostname,
    );
    if (host.isNotEmpty) {
      return host;
    }
    return (platformProvider ?? _readPlatform)().trim();
  }

  static String _readLocalHostnameSafely(String Function() hostnameProvider) {
    try {
      return hostnameProvider().trim();
    } catch (_) {
      return '';
    }
  }

  static String _readLocalHostname() => Platform.localHostname;

  static String _readPlatform() => Platform.operatingSystem;

  static Future<File?> _defaultDeviceKeyBackupFile() async {
    final support = await getApplicationSupportDirectory();
    return File(
      p.join(support.path, 'device_identity', 'auth_device_key.txt'),
    );
  }

  static String _normalizeDeviceKey(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.length <= _maxDeviceKeyLength) {
      return trimmed;
    }
    return trimmed.substring(0, _maxDeviceKeyLength);
  }

  Future<String> _readDeviceKeyBackup() async {
    final file = await _deviceKeyBackupFileProvider();
    if (file == null || !await file.exists()) {
      return '';
    }
    return _normalizeDeviceKey(await file.readAsString());
  }

  Future<void> _writeDeviceKeyBackup(String deviceKey) async {
    final normalized = _normalizeDeviceKey(deviceKey);
    if (normalized.isEmpty) {
      throw StateError('Device key backup cannot be empty.');
    }
    final file = await _deviceKeyBackupFileProvider();
    if (file == null) {
      return;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString('$normalized\n', flush: true);
  }
}
