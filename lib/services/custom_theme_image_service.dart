import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

enum CustomThemeSurface { home, playback }

class CustomThemeImageService {
  const CustomThemeImageService._();

  static const int maxHistoryCount = 8;

  static Future<Directory> _themeDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}themes',
    );
    await directory.create(recursive: true);
    return directory;
  }

  static Future<String> save(
    CustomThemeSurface surface,
    Uint8List pngBytes, {
    Directory? targetDirectory,
  }) async {
    final directory = targetDirectory ?? await _themeDirectory();
    await directory.create(recursive: true);
    final revision = DateTime.now().microsecondsSinceEpoch;
    final file = File(
      '${directory.path}${Platform.pathSeparator}${surface.name}_$revision.png',
    );
    await file.writeAsBytes(pngBytes, flush: true);
    await _trimHistory(surface, directory: directory);
    return file.path;
  }

  static Future<List<String>> history(
    CustomThemeSurface surface, {
    Directory? targetDirectory,
  }) async {
    final directory = targetDirectory ?? await _themeDirectory();
    await directory.create(recursive: true);
    final prefix = '${surface.name}_';
    final entries = await directory
        .list()
        .where((entry) {
          if (entry is! File) return false;
          final name = entry.uri.pathSegments.last;
          return name.startsWith(prefix) && name.endsWith('.png');
        })
        .cast<File>()
        .toList();
    entries.sort((a, b) => b.path.compareTo(a.path));
    return entries.map((file) => file.path).toList(growable: false);
  }

  static Future<void> _trimHistory(
    CustomThemeSurface surface, {
    required Directory directory,
  }) async {
    final paths = await history(surface, targetDirectory: directory);
    for (final path in paths.skip(maxHistoryCount)) {
      await remove(path);
    }
  }

  static Future<void> remove(String? path) async {
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
