import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/services/cover_disk_cache.dart';

void main() {
  test('cover cache hits only the matching file revision', () async {
    final root = await Directory.systemTemp.createTemp('myune_cover_cache_');
    addTearDown(() => root.delete(recursive: true));
    final cache = CoverDiskCache(rootDirectory: root);
    final bytes = Uint8List.fromList([1, 2, 3, 4]);

    await cache.write('/music/song.flac', 100, bytes);

    expect(await cache.read('/music/song.flac', 100), bytes);
    expect(await cache.read('/music/song.flac', 101), isNull);
  });

  test('identical thumbnails are stored once for different tracks', () async {
    final root = await Directory.systemTemp.createTemp('myune_cover_cache_');
    addTearDown(() => root.delete(recursive: true));
    final cache = CoverDiskCache(rootDirectory: root);
    final bytes = Uint8List.fromList([9, 8, 7, 6]);

    await cache.write('/music/one.flac', 1, bytes);
    await cache.write('/music/two.flac', 2, bytes);

    final directory = Directory('${root.path}/artwork_thumbnails_v3');
    final thumbnails = await directory
        .list()
        .where((entity) => entity.path.endsWith('.thumb'))
        .toList();
    expect(thumbnails, hasLength(1));
    expect(await cache.read('/music/one.flac', 1), bytes);
    expect(await cache.read('/music/two.flac', 2), bytes);
  });

  test('cache reads do not touch thumbnail metadata', () async {
    final root = await Directory.systemTemp.createTemp('myune_cover_cache_');
    addTearDown(() => root.delete(recursive: true));
    final cache = CoverDiskCache(rootDirectory: root);

    await cache.write('/music/song.flac', 100, Uint8List.fromList([1, 2, 3]));
    final directory = Directory('${root.path}/artwork_thumbnails_v3');
    final thumbnail = await directory
        .list()
        .where((entity) => entity.path.endsWith('.thumb'))
        .cast<File>()
        .single;
    final oldTime = DateTime.utc(2020, 1, 1);
    await thumbnail.setLastModified(oldTime);
    final storedTime = (await thumbnail.stat()).modified;

    expect(await cache.read('/music/song.flac', 100), isNotNull);
    expect((await thumbnail.stat()).modified, storedTime);
  });

  test(
    'cover cache evicts old entries when its entry limit is exceeded',
    () async {
      final root = await Directory.systemTemp.createTemp('myune_cover_cache_');
      addTearDown(() => root.delete(recursive: true));
      final cache = CoverDiskCache(
        rootDirectory: root,
        maximumBytes: 1024,
        maximumEntries: 1,
        cleanupInterval: 1,
      );

      await cache.write('/music/first.flac', 1, Uint8List.fromList([1]));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await cache.write('/music/second.flac', 1, Uint8List.fromList([2]));

      expect(await cache.read('/music/first.flac', 1), isNull);
      expect(
        await cache.read('/music/second.flac', 1),
        Uint8List.fromList([2]),
      );
    },
  );
}
