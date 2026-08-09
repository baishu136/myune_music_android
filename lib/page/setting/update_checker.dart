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
    String currentVersion,
  ) async {
    try {
      final response = await http
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

      final releases = json.decode(response.body);
      if (releases is! List) {
        return UpdateCheckResult.error('GitHub 返回了无效数据');
      }

      final published = releases.whereType<Map<String, dynamic>>().where(
        (release) => release['draft'] != true,
      );
      if (published.isEmpty) {
        return UpdateCheckResult.successNoUpdate();
      }

      final release = published.first;
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

  UpdateInfo({
    required this.latestVersion,
    required this.releaseNotes,
    required this.downloadUrl,
  });
}
