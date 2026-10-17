import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myune_music/page/playlist/playlist_manager.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory temp;
  late Directory data;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('myune-root-402-');
    data = Directory('${temp.path}/myune_music/list_data');
    SharedPreferences.setMockInitialValues({
      'data_migrated_to_app_support': true,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? temp.path
              : null,
        );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await temp.delete(recursive: true);
  });

  test(
    'fresh installation stores separate empty library and favorites; import persists only in root',
    () async {
      final manager = PlaylistManager();
      final playlists = await manager.loadPlaylists();
      expect(playlists.map((p) => p.name), ['总歌曲', '收藏']);
      expect(
        await File('${data.path}/playlists_metadata.json').exists(),
        isTrue,
      );
      playlists.first.songFilePaths.add('/music/imported.mp3');
      await manager.savePlaylists(playlists);
      final restored = await manager.loadPlaylists();
      expect(restored.first.isLibrary, isTrue);
      expect(restored.first.songFilePaths, ['/music/imported.mp3']);
      expect(restored.last.songFilePaths, isEmpty);
    },
  );

  test(
    'legacy favorites remain intact and removing a playlist never removes root ownership',
    () async {
      final manager = PlaylistManager();
      final favorites = Playlist(
        id: 'legacy-favorites',
        name: '收藏',
        isDefault: true,
        songFilePaths: ['old', 'hidden'],
      );
      final custom = Playlist(
        id: 'legacy-custom',
        name: '自建',
        songFilePaths: ['custom-only'],
      );
      await manager.savePlaylists([favorites, custom]);
      final restored = await manager.loadPlaylists();
      expect(restored.map((p) => p.id), [
        Playlist.libraryId,
        favorites.id,
        custom.id,
      ]);
      expect(restored.first.songFilePaths, ['old', 'hidden', 'custom-only']);
      restored[1].songFilePaths.remove('old');
      restored.removeLast();
      await manager.savePlaylists(restored);
      final again = await manager.loadPlaylists();
      expect(again.first.songFilePaths, ['old', 'hidden', 'custom-only']);
      expect(again[1].songFilePaths, ['hidden']);
    },
  );

  test(
    'corrupt metadata read does not rewrite or erase existing song files',
    () async {
      final manager = PlaylistManager();
      await manager.savePlaylists([
        Playlist(id: 'legacy', name: '旧歌单', songFilePaths: ['recoverable']),
      ]);
      final metadata = File('${data.path}/playlists_metadata.json');
      final songFile = File('${data.path}/playlist_songs/legacy.json');
      final bytes = await songFile.readAsBytes();
      await metadata.writeAsString('{corrupt');
      expect((await manager.loadPlaylists()).first.isLibrary, isTrue);
      expect(await metadata.readAsString(), '{corrupt');
      expect(await songFile.readAsBytes(), bytes);
      expect(jsonDecode(await songFile.readAsString()), ['recoverable']);
    },
  );
}
