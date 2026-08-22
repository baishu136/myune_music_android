import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

class AppVersion {
  AppVersion._();

  static Future<String>? _cached;

  static Future<String> current() => _cached ??= _load();

  static Future<String> _load() async {
    final info = await PackageInfo.fromPlatform();
    return format(
      version: info.version,
      buildNumber: info.buildNumber,
      android: Platform.isAndroid,
    );
  }

  static String format({
    required String version,
    required String buildNumber,
    required bool android,
  }) {
    if (buildNumber.isEmpty) return version;
    final displayBuild = android
        ? normalizeAndroidBuildNumber(buildNumber)
        : buildNumber;
    return android
        ? '$version-android.$displayBuild'
        : '$version+$displayBuild';
  }

  /// Flutter adds an ABI prefix to split APK version codes (arm64 uses 2000).
  /// The user-facing build number remains the value declared in pubspec.yaml.
  static String normalizeAndroidBuildNumber(String buildNumber) {
    final value = int.tryParse(buildNumber);
    if (value == null || value < 1000) return buildNumber;
    return (value % 1000).toString();
  }
}
