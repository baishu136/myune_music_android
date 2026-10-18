import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/widgets/song_playlist_sheet.dart';
import 'package:myune_music/widgets/artwork_image.dart';
import 'playback_pages_402_test.dart' as fixture;

class _DelayedLibrary extends fixture.PlaylistWindowFixture408 {
  Completer<void>? pending;
  bool fail = false;
  int removes = 0;
  @override
  Future<int> removeSongsFromPlaylistById(String id, List<String> paths) async {
    removes++;
    await pending?.future;
    if (fail) throw StateError('Storage unavailable');
    return super.removeSongsFromPlaylistById(id, paths);
  }
}

class _ThumbnailLibrary extends _DelayedLibrary {
  late Uint8List thumbnail;
  @override
  Future<Uint8List?> ensureSongThumbnail(
    String path, {
    ArtworkRequestPriority priority = ArtworkRequestPriority.near,
  }) async => thumbnail;
}

void main() {
  testWidgets(
    'empty playlist clears its previous cover after the last song is unchecked',
    (tester) async {
      final model = _ThumbnailLibrary()
        ..thumbnail = (await rootBundle.load(
          'assets/images/icon/logo.png',
        )).buffer.asUint8List();
      model.playlists[1].songFilePaths.add('current.mp3');
      await _mount(tester, model);
      expect(find.byType(ArtworkImage), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('song-playlist-selection-favorite')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ArtworkImage), findsNothing);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
  test(
    'removal normalizes paths, clears duplicate cached songs and preserves other lists and date',
    () {
      Song song(String path) => Song(title: 't', artist: 'a', filePath: path);
      final date = DateTime.utc(2026, 10, 18);
      final list = Playlist(
        name: '目标',
        createdAt: date,
        songFilePaths: const ['/music/A.mp3', '/music/./a.mp3', '/music/B.mp3'],
        songs: [
          song('/music/A.mp3'),
          song('/music/a.mp3'),
          song('/music/B.mp3'),
        ],
      );
      final queue = Playlist(
        name: '播放源',
        songFilePaths: list.songFilePaths,
        songs: list.songs,
      );
      expect(list.containsSongPath('/music/a.mp3'), isTrue);
      expect(list.removeSongPaths(['/music/./A.mp3']), 2);
      expect(list.songFilePaths, ['/music/B.mp3']);
      expect(list.songs!.map((song) => song.filePath), ['/music/B.mp3']);
      expect(list.createdAt, date);
      expect(queue.songFilePaths, hasLength(3));
      expect(queue.songs, hasLength(3));
      expect(list.removeSongPaths(['/music/a.mp3']), 0);
      final root = Playlist(
        id: Playlist.libraryId,
        name: '总歌曲',
        songFilePaths: ['/music/A.mp3'],
      );
      expect(root.removeSongPaths(['/music/a.mp3']), 0);
      expect(root.songFilePaths, ['/music/A.mp3']);
    },
  );

  testWidgets(
    'checkbox starts checked, removes only membership, then row adds it back',
    (tester) async {
      final model = _DelayedLibrary();
      model.playlists[1].songFilePaths.add('current.mp3');
      await _mount(tester, model);
      final selector = find.byKey(
        const ValueKey('song-playlist-selection-favorite'),
      );
      expect(tester.widget<Checkbox>(selector).value, isTrue);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(selector).value, isFalse);
      expect(model.playlists.first.songFilePaths, ['current.mp3']);
      expect(model.playlists[1].songFilePaths, isEmpty);
      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(selector).value, isTrue);
      expect(model.playlists[1].songFilePaths, ['current.mp3']);
      expect(model.playlists[2].songFilePaths, isEmpty);
      expect(find.text('总歌曲'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );

  testWidgets(
    'pending save blocks duplicate toggles, failure unlocks controls for retry',
    (tester) async {
      final model = _DelayedLibrary()
        ..pending = Completer<void>()
        ..fail = true;
      model.playlists[1].songFilePaths.add('current.mp3');
      await _mount(tester, model);
      final selector = find.byKey(
        const ValueKey('song-playlist-selection-favorite'),
      );
      await tester.tap(selector);
      await tester.tap(selector);
      await tester.pump();
      expect(model.removes, 1);
      expect(tester.widget<Checkbox>(selector).onChanged, isNull);
      model.pending!.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(selector).value, isTrue);
      expect(tester.widget<Checkbox>(selector).onChanged, isNotNull);
      expect(find.text('更新歌单失败，请重试'), findsOneWidget);
      model.pending = null;
      model.fail = false;
      await tester.tap(selector);
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(selector).value, isFalse);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'leaving the window during a pending save does not use a disposed context',
    (tester) async {
      final model = _DelayedLibrary()
        ..pending = Completer<void>()
        ..fail = true;
      model.playlists[1].songFilePaths.add('current.mp3');
      await _mount(tester, model);
      await tester.tap(
        find.byKey(const ValueKey('song-playlist-selection-favorite')),
      );
      await tester.pumpWidget(const SizedBox());
      model.pending!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      model.dispose();
    },
  );
}

Future<void> _mount(WidgetTester tester, PlaylistContentNotifier model) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<PlaylistContentNotifier>.value(
      value: model,
      child: MaterialApp(
        home: Scaffold(
          body: SongPlaylistSheet(
            song: Song(title: '当前歌曲', artist: '歌手', filePath: 'current.mp3'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
