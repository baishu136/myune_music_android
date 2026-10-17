import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';
import 'package:myune_music/page/playlist/playlist_content_widget.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/services/artist_names.dart';
import 'package:myune_music/services/playback_picker_memory.dart';
import 'package:myune_music/widgets/home_glass_surface.dart';
import 'package:myune_music/widgets/karaoke_motion.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';
import 'package:myune_music/widgets/playing_queue_drawer.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _QueueNotifier extends ChangeNotifier implements PlaylistContentNotifier {
  @override
  List<Playlist> playlists = [
    Playlist(id: 'evening', name: '晚间歌单', songFilePaths: ['a.mp3']),
  ];
  final artistParser = ArtistNameParser(defaultArtistSeparators);
  final songs = [
    Song(title: 'A first', artist: 'A', album: 'One', filePath: 'a.mp3'),
    Song(title: 'A second', artist: 'A/B', album: 'Two', filePath: 'b.mp3'),
    Song(title: 'B only', artist: 'B', album: 'Two', filePath: 'c.mp3'),
  ];
  Song? selected;
  Song? playedSearch;
  List<Song>? playedDynamic;
  final coverChanges = ValueNotifier(0);
  @override
  Song? get currentSong => selected;
  @override
  List<Song> get allSongs => songs;
  @override
  List<String> getIndividualArtists(String artist) =>
      artistParser.split(artist);
  @override
  List<Song> searchSongs(String keyword, Iterable<Song> source) => source
      .where((song) => song.title.toLowerCase().contains(keyword.toLowerCase()))
      .toList();
  @override
  Future<void> playAllSongsSearchResult(Song song) async {
    playedSearch = song;
    changeSong(song);
  }

  @override
  Future<void> playFromDynamicList(List<Song> songs, int index) async {
    playedDynamic = songs;
    changeSong(songs[index]);
  }

  void changeSong(Song? song) {
    selected = song;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #capturePlaybackSource:
        return const PlaybackSourceSnapshot(
          usesQueue: false,
          songs: [],
          currentIndex: -1,
        );
      case #allSongsVirtualPlaylist:
        return Playlist(id: 'library', name: 'library');
      case #playingPlaylist:
        return null;
      case #isMultiSelectMode:
        return false;
      case #selectedSongPaths:
        return <String>{};
      case #coverForSongPath:
        return null;
      case #coverListenableForSongPath:
        return coverChanges;
      case #requestSongCover:
      case #releaseSongCover:
      case #recoverSongCover:
        return null;
      default:
        return super.noSuchMethod(invocation);
    }
  }

  @override
  void dispose() {
    coverChanges.dispose();
    super.dispose();
  }
}

void main() {
  Future<_QueueNotifier> mount(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.initializationFuture;
    final notifier = _QueueNotifier()..selected = null;
    notifier.selected = notifier.songs.first;
    addTearDown(settings.dispose);
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlaylistContentNotifier>.value(
            value: notifier,
          ),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PlayingQueueDrawer(syncHomeBackground: false)),
        ),
      ),
    );
    return notifier;
  }

  List<String> visibleSongs(WidgetTester tester) => tester
      .widgetList<SongTileWidget>(find.byType(SongTileWidget))
      .map((tile) => tile.song.title)
      .toList();

  testWidgets(
    'picker restores search after remount without changing playback source',
    (tester) async {
      final notifier = await mount(tester);
      final context = tester.element(find.byType(PlayingQueueDrawer));
      final settings = context.read<SettingsProvider>();
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('queue-library-search')),
        'second',
      );
      await tester.pumpAndSettle();
      expect(visibleSongs(tester), ['A second']);
      Widget host(Widget body) => MultiProvider(
        providers: [
          ChangeNotifierProvider<PlaylistContentNotifier>.value(
            value: notifier,
          ),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ],
        child: MaterialApp(home: Scaffold(body: body)),
      );
      await tester.pumpWidget(host(const SizedBox()));
      await tester.pumpAndSettle();
      expect(settings.playbackPickerMemory.page, PlaybackPickerPage.search);
      await tester.pumpWidget(
        host(const PlayingQueueDrawer(syncHomeBackground: false)),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('queue-library-search')),
            )
            .controller!
            .text,
        'second',
      );
      expect(visibleSongs(tester), ['A second']);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('removed remembered playlist falls back to live playlist list', (
    tester,
  ) async {
    final notifier = await mount(tester);
    final settings = tester
        .element(find.byType(PlayingQueueDrawer))
        .read<SettingsProvider>();
    await tester.tap(find.byTooltip('歌单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('晚间歌单'));
    await tester.pumpAndSettle();
    expect(visibleSongs(tester), ['A first']);
    expect(settings.playbackPickerMemory.playlistId, 'evening');
    notifier.playlists.clear();
    notifier.changeSong(notifier.songs.first);
    await tester.pumpAndSettle();
    expect(find.text('暂无已创建的歌单'), findsOneWidget);
    expect(visibleSongs(tester), isEmpty);
    await tester.pumpWidget(const SizedBox());
    expect(settings.playbackPickerMemory.page, PlaybackPickerPage.playlists);
    expect(settings.playbackPickerMemory.playlistId, isNull);
  });

  test('retained lift is seven percent at small and scaled text heights', () {
    final config = KaraokeMotionConfig();
    for (final height in [12.0, 40.0, 48.0, 120.0]) {
      expect(
        karaokeLiftPixels(1, height, config),
        closeTo(-height * .07, 1e-9),
      );
    }
  });
  test('ordinary rows only highlight the playback focus', () {
    expect(mobileLyricWholeLineHighlight(0), 1);
    for (final distance in [1, 2, 4]) {
      expect(mobileLyricWholeLineHighlight(distance), 0);
    }
    expect(mobileLyricWholeLineHighlight(0, hasFocus: false), 0);
  });
  testWidgets('both home footer roles have no active blur in either theme', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: const Scaffold(
            body: Column(
              children: [
                HomeGlassSurface(child: SizedBox(height: 60)),
                HomeGlassMaterial(child: SizedBox(height: 72)),
              ],
            ),
          ),
        ),
      );
      expect(
        tester
            .widgetList<BackdropFilter>(find.byType(BackdropFilter))
            .where((filter) => filter.enabled),
        isEmpty,
      );
    }
  });
  testWidgets('drawer exposes four icon scopes and retains playlist access', (
    tester,
  ) async {
    await mount(tester);
    for (final label in ['音乐库', '歌手', '专辑', '搜索', '歌单']) {
      expect(find.byTooltip(label), findsOneWidget);
      expect(find.text(label), findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('artist scope refreshes after a song change without remount', (
    tester,
  ) async {
    final notifier = await mount(tester);
    // Existing icon is shared by the old/new artist scope button.
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(visibleSongs(tester), ['A first', 'A second']);
    final state = tester.state(find.byType(PlayingQueueDrawer));
    notifier.changeSong(notifier.songs.last);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(PlayingQueueDrawer)), same(state));
    expect(visibleSongs(tester), ['A second', 'B only']);
    notifier.changeSong(null);
    await tester.pumpAndSettle();
    expect(visibleSongs(tester), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('album scope follows current album and plays its filtered list', (
    tester,
  ) async {
    final notifier = await mount(tester);
    await tester.tap(find.byTooltip('专辑'));
    await tester.pumpAndSettle();
    expect(visibleSongs(tester), ['A first']);
    notifier.changeSong(notifier.songs.last);
    await tester.pumpAndSettle();
    expect(visibleSongs(tester), ['A second', 'B only']);
    await tester.tap(find.text('A second'));
    await tester.pumpAndSettle();
    expect(notifier.playedDynamic?.map((s) => s.title), ['A second', 'B only']);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'solo artist includes slash collaborations regardless of case or spacing',
    (tester) async {
      final notifier = await mount(tester);
      notifier.songs
        ..clear()
        ..addAll([
          Song(title: 'Solo', artist: 'The Weeknd', filePath: 'solo.mp3'),
          Song(
            title: 'Shared',
            artist: 'Future/the WEEKND',
            filePath: 'shared.mp3',
          ),
          Song(
            title: 'Full width',
            artist: 'Future／THE   WEEKND',
            filePath: 'wide.mp3',
          ),
          Song(
            title: 'Different name',
            artist: 'The Weekend',
            filePath: 'other.mp3',
          ),
          Song(title: 'Future solo', artist: 'Future', filePath: 'future.mp3'),
        ]);
      notifier.changeSong(notifier.songs.first);
      await tester.pump();
      await tester.tap(find.byTooltip('歌手'));
      await tester.pumpAndSettle();
      expect(visibleSongs(tester), ['Solo', 'Shared', 'Full width']);
      notifier.changeSong(notifier.songs[1]);
      await tester.pumpAndSettle();
      expect(visibleSongs(tester), [
        'Solo',
        'Shared',
        'Full width',
        'Future solo',
      ]);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'multi-artist scope includes every collaborator once in library order',
    (tester) async {
      final notifier = await mount(tester);
      final unrelated = Song(
        title: 'Unrelated',
        artist: 'AA',
        filePath: 'unrelated.mp3',
      );
      final secondCollaboration = Song(
        title: 'A second',
        artist: 'B/C',
        filePath: 'other-collaboration.mp3',
      );
      notifier.songs.addAll([unrelated, secondCollaboration]);
      notifier.changeSong(notifier.songs[1]);
      await tester.pump();
      await tester.tap(find.byTooltip('歌手'));
      await tester.pumpAndSettle();
      final tiles = tester
          .widgetList<SongTileWidget>(find.byType(SongTileWidget))
          .toList();
      expect(tiles.map((tile) => tile.song.filePath), [
        'a.mp3',
        'b.mp3',
        'c.mp3',
        'other-collaboration.mp3',
      ]);
      await tester.tap(find.text('B only'));
      await tester.pumpAndSettle();
      expect(notifier.playedDynamic?.map((song) => song.filePath), [
        'a.mp3',
        'b.mp3',
        'c.mp3',
        'other-collaboration.mp3',
      ]);
      expect(visibleSongs(tester), ['A second', 'B only', 'A second']);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'search filters library, survives song updates and plays exact result',
    (tester) async {
      final notifier = await mount(tester);
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'B only');
      await tester.pumpAndSettle();
      expect(visibleSongs(tester), ['B only']);
      notifier.changeSong(notifier.songs[1]);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'B only',
      );
      expect(visibleSongs(tester), ['B only']);
      await tester.tap(find.text('B only').last);
      await tester.pumpAndSettle();
      expect(notifier.playedSearch, same(notifier.songs.last));
      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pumpAndSettle();
      expect(visibleSongs(tester), hasLength(3));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
