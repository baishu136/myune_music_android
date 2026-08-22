import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/services/cover_override_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('myune-cover-test-');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('persists song and group overrides and supports reset', () async {
    final bytes = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);
    final service = CoverOverrideService(
      directoryProvider: () async => directory,
    );
    await service.initializationFuture;

    await service.setSongCover('/music/example.mp3', bytes);
    await service.setGroupCover(artist: true, group: 'Artist', bytes: bytes);

    final restored = CoverOverrideService(
      directoryProvider: () async => directory,
    );
    await restored.initializationFuture;
    expect(restored.songCover('/music/example.mp3'), orderedEquals(bytes));
    expect(
      restored.groupCover(artist: true, group: 'Artist'),
      orderedEquals(bytes),
    );

    await restored.setSongCover('/music/example.mp3', null);
    await restored.setGroupCover(artist: true, group: 'Artist');
    expect(restored.songCover('/music/example.mp3'), isNull);
    expect(restored.groupCover(artist: true, group: 'Artist'), isNull);
  });

  test('drops index entries whose image file is missing', () async {
    SharedPreferences.setMockInitialValues({
      'cover_override_song_index_v1':
          '{"/music/missing.mp3":"${directory.path.replaceAll(r'\', r'\\')}\\missing.png"}',
    });
    final service = CoverOverrideService(
      directoryProvider: () async => directory,
    );
    await service.initializationFuture;
    expect(service.songCover('/music/missing.mp3'), isNull);
  });
}
