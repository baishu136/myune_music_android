import 'dart:io';

import 'package:flutter/services.dart';

class AudioCoverEditorService {
  static const _channel = MethodChannel('com.myune.music/cover_editor');

  /// Opens Android's image collection/photo picker rather than the document
  /// provider used for generic file imports. The selected URI is copied to the
  /// app cache so the existing crop editor can continue to work with a path.
  static Future<String?> pickImageFromGallery() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('系统相册选择目前仅支持 Android');
    }
    return _channel.invokeMethod<String>('pickImageFromGallery');
  }

  static Future<void> replaceEmbeddedCover(
    String filePath,
    Uint8List imageBytes,
  ) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('替换文件封面目前仅支持 Android');
    }
    await _channel.invokeMethod<void>('replaceEmbeddedCover', {
      'path': filePath,
      'imageBytes': imageBytes,
    });
  }
}
