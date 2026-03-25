import 'dart:io';

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
  })  : _hostnameProvider = hostnameProvider ?? _readLocalHostname,
        _platformProvider = platformProvider ?? _readPlatform;

  final SecureStorageService _secureStorage;
  final String Function() _hostnameProvider;
  final String Function() _platformProvider;
  static const Uuid _uuid = Uuid();

  Future<String> ensureDeviceKey() async {
    final existing = (await _secureStorage.readAuthDeviceKey())?.trim() ?? '';
    if (existing.isNotEmpty) {
      return existing;
    }
    final generated = _uuid.v4();
    await _secureStorage.writeAuthDeviceKey(generated);
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
}
