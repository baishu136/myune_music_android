import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

enum CustomThemeSurface { home, playback }

class CustomThemeImageService {
  const CustomThemeImageService._();

  static Future<String> save(
    CustomThemeSurface surface,
    Uint8List pngBytes,
  ) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}themes',
    );
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${surface.name}.png',
    );
    await file.writeAsBytes(pngBytes, flush: true);
    return file.path;
  }

  static Future<void> remove(String? path) async {
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
