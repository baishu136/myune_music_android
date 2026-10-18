import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/widgets/song_playlist_sheet.dart';
import 'package:myune_music/widgets/playback_mode_page.dart';
import 'package:myune_music/widgets/long_press_icon_button.dart';
import 'package:myune_music/widgets/playback_control_sheet_surface.dart';

class _Library extends ChangeNotifier implements PlaylistContentNotifier {
  @override
  Future<Uint8List?> ensureSongThumbnail(
    String filePath, {
    ArtworkRequestPriority priority = ArtworkRequestPriority.near,
  }) async => null;
  final items = [
    Playlist(
      id: Playlist.libraryId,
      name: '总歌曲',
      isDefault: true,
      songFilePaths: ['current.mp3'],
    ),
    Playlist(id: 'favorite', name: '收藏', isDefault: true),
    Playlist(id: 'other', name: '晚间歌单'),
  ];
  @override
  List<Playlist> get playlists => items;
  @override
  PlayMode get playMode => mode;
  PlayMode mode = PlayMode.sequence;
  @override
  PlaybackSkipRules get skipRules => rules;
  PlaybackSkipRules rules = const PlaybackSkipRules();
  @override
  void setPlayMode(PlayMode value) {
    mode = value;
    notifyListeners();
  }

  @override
  Future<void> setSkipRules(PlaybackSkipRules value) async {
    rules = value;
    notifyListeners();
  }

  @override
  Future<int> addSongsToPlaylistById(String id, List<String> paths) async {
    items.singleWhere((p) => p.id == id).songFilePaths.addAll(paths);
    notifyListeners();
    return paths.length;
  }

  @override
  Future<int> removeSongsFromPlaylistById(String id, List<String> paths) async {
    final removed = items
        .singleWhere((item) => item.id == id)
        .removeSongPaths(paths);
    notifyListeners();
    return removed;
  }

  @override
  Future<bool> saveQueueAsPlaylist(String name, List<Song> songs) async {
    items.add(
      Playlist(
        name: name,
        songFilePaths: songs.map((s) => s.filePath).toList(),
      ),
    );
    notifyListeners();
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PlaylistWindowFixture408 extends _Library {}

void main() {
  testWidgets(
    'mode sheet uses bottom entrance and transparent shared surface',
    (tester) async {
      final model = _Library();
      await tester.pumpWidget(
        ChangeNotifierProvider<PlaylistContentNotifier>.value(
          value: model,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const FractionallySizedBox(
                      heightFactor: .82,
                      child: PlaybackControlSheetSurface(
                        fluid: true,
                        child: PlaybackModePage(asSheet: true),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final start = tester.getTopLeft(find.byType(PlaybackModePage)).dy;
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byType(PlaybackModePage)).dy,
        lessThan(start),
      );
      expect(
        find.descendant(
          of: find.byType(PlaybackModePage),
          matching: find.byType(Scaffold),
        ),
        findsNothing,
      );
      expect(find.byType(AppBar), findsNothing);
      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).backgroundColor,
        Colors.transparent,
      );
      await tester.tap(find.text('循环播放，随机切歌'));
      await tester.pump();
      expect(model.mode, PlayMode.repeatShuffle);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(PlaybackModePage), findsNothing);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
  const preview = String.fromEnvironment('MYUNE_402_PREVIEW_DIR');
  Future<void> preparePreview(WidgetTester tester) async {
    if (preview.isEmpty) return;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await (FontLoader(
        'MiSans402',
      )..addFont(rootBundle.load('assets/fonts/MiSansVF.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    if (preview.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(preview).create(recursive: true);
      await File('$preview/$name.png').writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'mode page updates all filters and threshold, with four selectable modes',
    (tester) async {
      final model = _Library();
      await preparePreview(tester);
      final key = GlobalKey();
      await tester.pumpWidget(
        ChangeNotifierProvider<PlaylistContentNotifier>.value(
          value: model,
          child: MaterialApp(
            theme: ThemeData(
              brightness: Brightness.dark,
              fontFamily: 'MiSans402',
            ),
            home: RepaintBoundary(key: key, child: const PlaybackModePage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('循环播放，随机切歌'));
      await tester.pump();
      expect(model.mode, PlayMode.repeatShuffle);
      final switches = find.byType(SwitchListTile);
      expect(switches, findsNWidgets(4));
      await tester.tap(switches.at(0));
      await tester.enterText(find.byType(TextField), '17');
      await tester.pump();
      expect(model.rules.lowPlayCount, isTrue);
      expect(model.rules.minimumPlayCount, 17);
      for (var i = 1; i < 4; i++) {
        await tester.ensureVisible(switches.at(i));
        await tester.tap(switches.at(i));
        await tester.pump();
      }
      expect(
        model.rules.english && model.rules.japanese && model.rules.chinese,
        isTrue,
      );
      await capture(tester, key, 'playback-mode');
      await tester.pumpWidget(const SizedBox());
      model.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'playlist sheet toggles membership, excludes the root and creates a named playlist containing the captured song',
    (tester) async {
      final model = _Library();
      await preparePreview(tester);
      final key = GlobalKey();
      final song = Song(title: '当前歌曲', artist: '歌手', filePath: 'current.mp3');
      await tester.pumpWidget(
        ChangeNotifierProvider<PlaylistContentNotifier>.value(
          value: model,
          child: MaterialApp(
            theme: ThemeData(
              brightness: Brightness.dark,
              fontFamily: 'MiSans402',
            ),
            home: Scaffold(
              body: RepaintBoundary(
                key: key,
                child: SongPlaylistSheet(song: song),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('总歌曲'), findsNothing);
      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();
      expect(model.items[1].songFilePaths, ['current.mp3']);
      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();
      expect(model.items[1].songFilePaths, isEmpty);
      await tester.tap(find.text('新建歌单'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '新歌单');
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();
      expect(model.items.last.name, '新歌单');
      expect(model.items.last.songFilePaths, ['current.mp3']);
      await capture(tester, key, 'add-to-playlist');
      await tester.pumpWidget(const SizedBox());
      model.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'favorite and mode long press are not consumed by their tooltip and do not invoke tap',
    (tester) async {
      var taps = 0, holds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LongPressIconButton(
              tooltip: '收藏',
              icon: const Icon(Icons.favorite),
              onPressed: () => taps++,
              onLongPress: () => holds++,
            ),
          ),
        ),
      );
      final hold = await tester.startGesture(
        tester.getCenter(find.byType(IconButton)),
      );
      await tester.pump(const Duration(milliseconds: 499));
      expect(holds, 0);
      await tester.pump(const Duration(milliseconds: 1));
      await hold.up();
      await tester.pumpAndSettle();
      expect(holds, 1);
      expect(taps, 0);
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(taps, 1);
      final cancelled = await tester.startGesture(
        tester.getCenter(find.byType(IconButton)),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await cancelled.moveBy(const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 500));
      await cancelled.up();
      expect(holds, 1);
    },
  );
}
