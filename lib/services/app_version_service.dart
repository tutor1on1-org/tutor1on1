import 'package:package_info_plus/package_info_plus.dart';

class AppVersionInfo {
  const AppVersionInfo({
    required this.appVersion,
  });

  final String appVersion;
}

class AppVersionService {
  static Future<AppVersionInfo> load() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final version = packageInfo.version.trim();
    if (version.isEmpty) {
      throw StateError('Package version is blank.');
    }
    return AppVersionInfo(
      appVersion: version,
    );
  }
}
