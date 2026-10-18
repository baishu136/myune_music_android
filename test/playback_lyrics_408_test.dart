import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';
import 'package:myune_music/widgets/lyric_staggered_spring.dart';
import 'package:myune_music/widgets/playback_mode_glyph.dart';
import 'package:myune_music/widgets/playback_control_sheet_surface.dart';
import 'package:myune_music/widgets/playlist_created_label.dart';
import 'package:myune_music/widgets/song_playlist_sheet.dart';
import 'playback_pages_402_test.dart' as fixture;

void main() {
  test(
    'creation time survives JSON, rename and songs; legacy time stays unknown',
    () {
      final date = DateTime.utc(2026, 10, 18, 2, 30);
      final playlist = Playlist(name: '晚间', createdAt: date);
      final restored = Playlist.fromJson(
        jsonDecode(jsonEncode(playlist.toJson())),
      );
      restored.name = '新名称';
      restored.songFilePaths.add('song');
      expect(restored.createdAt, date);
      expect(Playlist.fromJson({'id': 'old', 'name': '旧歌单'}).createdAt, isNull);
      expect(
        Playlist.fromJson({
          'id': 'broken',
          'name': '坏日期',
          'createdAt': 'invalid',
        }).createdAt,
        isNull,
      );
      expect(playlistCreatedDate(null), isNull);
      expect(Playlist(name: '新建').createdAt, isNotNull);
    },
  );

  for (final hz in [60, 90, 120]) {
    test(
      'staggered springs at $hz Hz hold then move, redirect continuously and settle',
      () {
        final first = LyricStaggeredSpring()
          ..retarget(displacement: 100, step: 0, position: 0);
        final last = LyricStaggeredSpring()
          ..retarget(displacement: 100, step: 5, position: 1);
        last.tick(.129);
        expect(last.offset(0), 100);
        first.tick(.129);
        expect(first.offset(0), lessThan(100));
        last.tick(.3);
        final value = last.offset(0), velocity = last.velocity;
        last.retarget(displacement: 70, step: 3, position: .7);
        expect(last.offset(0) - 70, closeTo(value, 1e-9));
        expect(last.velocity, velocity);
        last.tick(.001);
        expect(
          last.offset(0),
          lessThan(value + 70),
          reason: 'redirect must not restart the stagger delay',
        );
        for (var i = 0; i <= hz * 3; i++) {
          last.tick(i / hz);
        }
        expect(last.settled, isTrue);
        expect(last.offset(0), 0);
        expect(last.velocity, 0);
        last.clear();
        first.dispose();
        last.dispose();
      },
    );
  }

  test('spring samples share absolute time and have only a mild rebound', () {
    final a = LyricStaggeredSpring()
      ..retarget(displacement: 200, step: 0, position: .5);
    final b = LyricStaggeredSpring()
      ..retarget(displacement: 200, step: 0, position: .5);
    a.tick(.4);
    for (var i = 0; i <= 40; i++) {
      b.tick(i / 100);
    }
    expect(a.offset(0), closeTo(b.offset(0), 1e-10));
    var minimum = 0.0;
    for (var i = 0; i <= 300; i++) {
      a.tick(i / 100);
      if (a.offset(0) < minimum) minimum = a.offset(0);
    }
    expect(minimum, inExclusiveRange(-5, 0));
    a.dispose();
    b.dispose();
  });

  testWidgets(
    'floating playlist window stays inset, toggles selection and creates a dated entry',
    (tester) async {
      final model = fixture.PlaylistWindowFixture408();
      final song = Song(title: '当前歌曲', artist: '歌手', filePath: 'current.mp3');
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await (FontLoader(
          'Preview408',
        )..addFont(rootBundle.load('assets/fonts/MiSansVF.ttf'))).load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
      final capture = GlobalKey();
      await tester.pumpWidget(
        ChangeNotifierProvider<PlaylistContentNotifier>.value(
          value: model,
          child: MaterialApp(
            theme: ThemeData(
              brightness: Brightness.dark,
              fontFamily: 'Preview408',
            ),
            builder: (_, child) => RepaintBoundary(key: capture, child: child!),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      showSongPlaylistWindow(context, song, fluid: true),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final fade = tester.widget<FadeTransition>(
        find.byKey(const ValueKey('song-playlist-window-fade')),
      );
      final scale = tester.widget<ScaleTransition>(
        find.byKey(const ValueKey('song-playlist-window-scale')),
      );
      final earlyOpacity = fade.opacity.value, earlyScale = scale.scale.value;
      expect(earlyOpacity, inExclusiveRange(0, 1));
      expect(earlyScale, inExclusiveRange(.92, 1));
      await tester.pump(const Duration(milliseconds: 80));
      expect(fade.opacity.value, greaterThan(earlyOpacity));
      expect(scale.scale.value, greaterThan(earlyScale));
      await tester.pumpAndSettle();
      expect(fade.opacity.value, 1);
      expect(scale.scale.value, 1);
      final window = find.byKey(
        const ValueKey('song-playlist-floating-window'),
      );
      final rect = tester.getRect(
        find.descendant(
          of: window,
          matching: find.byType(PlaybackControlSheetSurface),
        ),
      );
      expect(rect.left, greaterThan(0));
      expect(rect.right, lessThan(390));
      expect(rect.top, greaterThan(0));
      expect(rect.bottom, lessThan(844));
      expect(find.byType(BottomSheet), findsNothing);
      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();
      final included = tester.widget<ListTile>(
        find.byKey(const ValueKey('song-playlist-favorite')),
      );
      expect(included.enabled, isTrue);
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(const ValueKey('song-playlist-selection-favorite')),
            )
            .value,
        isTrue,
      );
      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();
      expect(model.playlists[1].songFilePaths, isEmpty);
      await tester.tap(find.text('新建歌单'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '创建日期测试');
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();
      expect(model.playlists.last.createdAt, isNotNull);
      expect(find.text('创建日期测试'), findsOneWidget);
      const output = String.fromEnvironment('PREVIEW408');
      if (output.isNotEmpty) {
        await tester.runAsync(() async {
          final image =
              await (capture.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory(output).createSync(recursive: true);
          File(
            '$output/playlist-window.png',
          ).writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tapAt(const Offset(8, 20));
      await tester.pumpAndSettle();
      expect(window, findsNothing);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('new repeat-shuffle glyph fits small and large sizes', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: const SizedBox(
              width: 240,
              height: 72,
              child: ColoredBox(
                color: Color(0xff202020),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    PlaybackModeGlyph(
                      mode: PlayMode.sequence,
                      color: Colors.white,
                    ),
                    PlaybackModeGlyph(
                      mode: PlayMode.shuffle,
                      color: Colors.white,
                    ),
                    PlaybackModeGlyph(
                      mode: PlayMode.repeatOne,
                      color: Colors.white,
                    ),
                    PlaybackModeGlyph(
                      mode: PlayMode.repeatShuffle,
                      size: 24,
                      color: Colors.white,
                    ),
                    PlaybackModeGlyph(
                      mode: PlayMode.repeatShuffle,
                      size: 48,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('repeat-shuffle-glyph')),
      findsNWidgets(2),
    );
    expect(tester.takeException(), isNull);
    const output = String.fromEnvironment('PREVIEW408');
    if (output.isNotEmpty) {
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 3);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          '$output/repeat-shuffle.png',
        ).writeAsBytesSync(png!.buffer.asUint8List());
        image.dispose();
      });
    }
  });

  for (final size in [const Size(320, 568), const Size(844, 390)]) {
    testWidgets('floating playlist window supports large text in $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final model = fixture.PlaylistWindowFixture408();
      final song = Song(title: '当前歌曲', artist: '歌手', filePath: 'current.mp3');
      await tester.pumpWidget(
        ChangeNotifierProvider<PlaylistContentNotifier>.value(
          value: model,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      showSongPlaylistWindow(context, song, fluid: false),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('晚间歌单'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });
  }
}
