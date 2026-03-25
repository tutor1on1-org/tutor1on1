import 'package:package_info_plus/package_info_plus.dart';

class AppVersionInfo {
  const AppVersionInfo({
    required this.appVersion,
    required this.releaseTag,
  });

  final String appVersion;
  final String releaseTag;
}

class AppVersionService {
  static Future<AppVersionInfo> load() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final version = packageInfo.version.trim();
    if (version.isEmpty) {
      throw StateError('Package version is blank.');
    }

    final buildNumber = packageInfo.buildNumber.trim();
    final appVersion = buildNumber.isEmpty ? version : '$version+$buildNumber';
    return AppVersionInfo(
      appVersion: appVersion,
      releaseTag: 'v$version',
    );
  }
}
