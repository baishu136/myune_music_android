import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class GalleryImageSaver {
  GalleryImageSaver._();

  static const _channel = MethodChannel('com.myune.music/gallery');

  static Future<void> saveAsset({
    required String assetPath,
    required String fileName,
  }) async {
    if (!Platform.isAndroid) {
      throw const GallerySaveException('当前平台暂不支持保存到系统相册');
    }
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    try {
      await _save(bytes, fileName);
    } on PlatformException catch (error) {
      if (error.code != 'permission_required') {
        throw GallerySaveException(error.message ?? '保存图片失败');
      }
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        throw const GallerySaveException('请授予存储权限后重试');
      }
      try {
        await _save(bytes, fileName);
      } on PlatformException catch (retryError) {
        throw GallerySaveException(retryError.message ?? '保存图片失败');
      }
    }
  }

  static Future<void> _save(Uint8List bytes, String fileName) => _channel
      .invokeMethod<void>('saveImage', {'bytes': bytes, 'fileName': fileName});
}

class GallerySaveException implements Exception {
  const GallerySaveException(this.message);

  final String message;

  @override
  String toString() => message;
}
