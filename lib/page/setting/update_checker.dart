import 'dart:convert';

import 'package:http/http.dart' as http;

enum UpdateCheckResultType { successUpdateAvailable, successNoUpdate, error }

class UpdateCheckResult {
  final UpdateCheckResultType type;
  final UpdateInfo? updateInfo;
  final String? errorMessage;

  UpdateCheckResult.successUpdateAvailable(this.updateInfo)
    : type = UpdateCheckResultType.successUpdateAvailable,
      errorMessage = null;

  UpdateCheckResult.successNoUpdate()
    : type = UpdateCheckResultType.successNoUpdate,
      updateInfo = null,
      errorMessage = null;

  UpdateCheckResult.error(this.errorMessage)
    : type = UpdateCheckResultType.error,
      updateInfo = null;
}

class UpdateChecker {
  static const String projectUrl =
      'https://github.com/baishu136/myune_music_android';
  static const String _apiUrl =
      'https://api.github.com/repos/baishu136/myune_music_android/releases?per_page=20';

  static Future<UpdateCheckResult> checkForUpdates(
    String currentVersion, {
    http.Client? client,
  }) async {
    final transport = client ?? http.Client();
    try {
      final response = await transport
          .get(
            Uri.parse(_apiUrl),
            headers: const {
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return UpdateCheckResult.error('GitHub 返回 ${response.statusCode}');
      }

      return parseReleases(json.decode(response.body), currentVersion);
    } catch (error) {
      return UpdateCheckResult.error(error.toString());
    } finally {
      if (client == null) transport.close();
    }
  }

  static UpdateCheckResult parseReleases(
    dynamic releases,
    String currentVersion,
  ) {
    try {
      if (releases is! List) {
        return UpdateCheckResult.error('GitHub 返回了无效数据');
      }

      final published = releases.whereType<Map<String, dynamic>>().where(
        (release) =>
            release['draft'] != true &&
            release['prerelease'] != true &&
            RegExp(
              r'^[vV]?\d+\.\d+\.\d+-android\.\d+$',
            ).hasMatch(release['tag_name']?.toString() ?? ''),
      );
      if (published.isEmpty) {
        return UpdateCheckResult.successNoUpdate();
      }

      final ordered = published.toList()
        ..sort(
          (a, b) =>
              isVersionNewer(a['tag_name'] as String, b['tag_name'] as String)
              ? -1
              : isVersionNewer(b['tag_name'] as String, a['tag_name'] as String)
              ? 1
              : 0,
        );
      final release = ordered.first;
      final latestVersion = _normalizeVersion(
        release['tag_name']?.toString() ?? '',
      );
      if (latestVersion.isEmpty) {
        return UpdateCheckResult.error('GitHub 版本号无效');
      }

      if (!isVersionNewer(latestVersion, currentVersion)) {
        return UpdateCheckResult.successNoUpdate();
      }

      return UpdateCheckResult.successUpdateAvailable(
        UpdateInfo(
          latestVersion: latestVersion,
          releaseNotes: release['body'] as String? ?? '',
          downloadUrl: release['html_url'] as String? ?? projectUrl,
          apk: UpdateApk.fromAssets(release['assets']),
        ),
      );
    } catch (error) {
      return UpdateCheckResult.error(error.toString());
    }
  }

  /// 比较包括 `0.9.3-android.2` 在内的项目版本号。
  static bool isVersionNewer(String latest, String current) {
    final latestParts = _versionNumbers(latest);
    final currentParts = _versionNumbers(current);
    final length = latestParts.length > currentParts.length
        ? latestParts.length
        : currentParts.length;

    for (var index = 0; index < length; index++) {
      final latestNumber = index < latestParts.length ? latestParts[index] : 0;
      final currentNumber = index < currentParts.length
          ? currentParts[index]
          : 0;
      if (latestNumber != currentNumber) {
        return latestNumber > currentNumber;
      }
    }
    return false;
  }

  static String _normalizeVersion(String version) =>
      version.trim().replaceFirst(RegExp(r'^[vV]'), '');

  static List<int> _versionNumbers(String version) =>
      RegExp(r'\d+').allMatches(_normalizeVersion(version)).map((match) {
        return int.tryParse(match.group(0) ?? '') ?? 0;
      }).toList();
}

class UpdateInfo {
  final String latestVersion;
  final String releaseNotes;
  final String downloadUrl;
  final UpdateApk? apk;

  UpdateInfo({
    required this.latestVersion,
    required this.releaseNotes,
    required this.downloadUrl,
    this.apk,
  });
}

class UpdateApk {
  const UpdateApk({
    required this.url,
    required this.name,
    required this.size,
    this.sha256,
  });
  final String url, name;
  final int size;
  final String? sha256;

  static UpdateApk? fromAssets(dynamic assets) {
    if (assets is! List) return null;
    for (final a in assets.whereType<Map>()) {
      final name = a['name'];
      final url = a['browser_download_url'];
      final size = a['size'];
      if (name is! String ||
          url is! String ||
          size is! int ||
          size <= 0 ||
          size > 300 * 1024 * 1024) {
        continue;
      }
      final uri = Uri.tryParse(url);
      if (!name.endsWith('-arm64-v8a.apk') ||
          uri?.scheme != 'https' ||
          uri?.host != 'github.com' ||
          !uri!.path.startsWith(
            '/baishu136/myune_music_android/releases/download/',
          )) {
        continue;
      }
      final digest = a['digest'];
      return UpdateApk(
        url: url,
        name: name,
        size: size,
        sha256:
            digest is String &&
                RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)
            ? digest.substring(7).toLowerCase()
            : null,
      );
    }
    return null;
  }
}
