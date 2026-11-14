import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/landscape_playback_surface.dart';
import 'package:myune_music/widgets/now_playing_immersive_layout.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';

void main() {
  testWidgets('cover swipes center then duet without remounting lyrics', (
    tester,
  ) async {
    var mode = LandscapeCoverMode.standard;
    final lyricKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, update) => SizedBox(
            width: 1000,
            height: 600,
            child: LandscapePlaybackSurface(
              landscape: true,
              mode: mode,
              showLyrics: false,
              cover: const ColoredBox(
                key: ValueKey('cover'),
                color: Colors.blue,
              ),
              lyrics: SizedBox.expand(key: lyricKey),
              title: 'Title',
              artist: 'Artist',
              onModeChanged: (m) => update(() => mode = m),
            ),
          ),
        ),
      ),
    );
    final element = lyricKey.currentContext;
    await tester.fling(
      find.byKey(const ValueKey('cover')),
      const Offset(-180, 0),
      700,
    );
    await tester.pumpAndSettle();
    expect(mode, LandscapeCoverMode.centered);
    final centered = tester.getRect(find.byKey(const ValueKey('cover')));
    expect(centered.center.dx, closeTo(400, .1));
    expect(centered.width, lessThan(600));
    expect(find.text('Title'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('cover')),
      const Offset(-160, 0),
    );
    await tester.pumpAndSettle();
    expect(mode, LandscapeCoverMode.duet);
    expect(
      tester.getRect(find.byKey(const ValueKey('cover'))).right,
      lessThan(tester.getRect(find.byKey(lyricKey)).left),
    );
    expect(lyricKey.currentContext, same(element));
    expect(tester.takeException(), isNull);
  });

  testWidgets('fullscreen transition changes lyric layout width only once', (
    tester,
  ) async {
    var full = true;
    late StateSetter update;
    final widths = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, set) {
            update = set;
            return NowPlayingImmersiveLayout(
              immersive: full,
              split: true,
              header: const SizedBox(),
              controls: const Text('controls'),
              visual: LayoutBuilder(
                builder: (_, box) {
                  widths.add(box.maxWidth);
                  return const SizedBox.expand();
                },
              ),
            );
          },
        ),
      ),
    );
    widths.clear();
    update(() => full = false);
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(widths.toSet().length, 1);
  });

  testWidgets('karaoke ink positions honor left center right alignment', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final lefts = <double>[];
    final line = LyricLine(timestamp: Duration.zero, texts: const ['Hi']);
    for (final align in [TextAlign.left, TextAlign.center, TextAlign.right]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileLyricsList(
              lines: [line],
              active: 0,
              textAlign: align,
              karaokeLyricsMode: KaraokeLyricsMode.all,
              fontSize: 30,
              lineBlurEnabled: false,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      final dynamic painter = tester
          .widget<CustomPaint>(
            find.byKey(const ValueKey('mobile_karaoke_single_pass_paint')),
          )
          .painter;
      lefts.add((painter.cache.tokens.first.bounds as Rect).left);
    }
    expect(lefts[1], greaterThan(lefts[0] + 100));
    expect(lefts[2], greaterThan(lefts[1] + 100));
  });
}
