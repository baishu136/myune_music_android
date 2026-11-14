import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/landscape_playback_surface.dart';
import 'package:myune_music/widgets/compact_playback_lyrics.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';
import 'package:myune_music/page/setting/settings_provider.dart';

void main() {
  testWidgets(
    'center tap toggles information, left swipe duet then fullscreen',
    (tester) async {
      var mode = LandscapeCoverMode.centered;
      var fullscreen = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, update) => LandscapePlaybackSurface(
                landscape: true,
                mode: mode,
                showLyrics: false,
                title: 'Title',
                artist: 'Artist',
                cover: const ColoredBox(
                  key: ValueKey('cover'),
                  color: Colors.blue,
                ),
                lyrics: const Text('Lyrics'),
                information: const Text('Information'),
                onFullscreenLyrics: () => fullscreen++,
                onModeChanged: (value) => update(() => mode = value),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('cover')));
      await tester.pumpAndSettle();
      expect(mode, LandscapeCoverMode.info);
      expect(find.text('Information'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cover')));
      await tester.pumpAndSettle();
      expect(mode, LandscapeCoverMode.centered);
      await tester.drag(
        find.byKey(const ValueKey('cover')),
        const Offset(-140, 0),
      );
      await tester.pumpAndSettle();
      expect(mode, LandscapeCoverMode.duet);
      await tester.tap(find.byKey(const ValueKey('cover')));
      await tester.pumpAndSettle();
      expect(mode, LandscapeCoverMode.duet);
      expect(fullscreen, 0);
      await tester.drag(
        find.byKey(const ValueKey('cover')),
        const Offset(-140, 0),
      );
      await tester.pumpAndSettle();
      expect(fullscreen, 1);
    },
  );

  testWidgets(
    'portrait uses original unconstrained stack, retains lyric State on rotation',
    (tester) async {
      var landscape = true;
      late StateSetter update;
      final lyric = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, set) {
                update = set;
                return LandscapePlaybackSurface(
                  landscape: landscape,
                  mode: LandscapeCoverMode.standard,
                  showLyrics: true,
                  cover: const SizedBox(),
                  lyrics: SizedBox.expand(key: lyric),
                  title: '',
                  artist: '',
                  onModeChanged: (_) {},
                );
              },
            ),
          ),
        ),
      );
      final element = lyric.currentContext;
      update(() => landscape = false);
      await tester.pumpAndSettle();
      expect(lyric.currentContext, same(element));
      expect(
        tester.getRect(find.byKey(lyric)),
        const Rect.fromLTWH(0, 0, 800, 600),
      );
      expect(find.byType(TweenAnimationBuilder<Rect?>), findsNothing);
      expect(find.byType(OverflowBox), findsNothing);
    },
  );

  testWidgets('three line preview follows line changes without karaoke', (
    tester,
  ) async {
    final lines = List.generate(
      5,
      (i) => LyricLine(
        timestamp: Duration(seconds: i),
        texts: ['Line $i'],
      ),
    );
    Future<void> show(int active) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompactPlaybackLyrics(lines: lines, active: active),
        ),
      ),
    );
    await show(0);
    await tester.pumpAndSettle();
    expect(find.text('Line 0'), findsOneWidget);
    expect(find.text('Line 1'), findsOneWidget);
    expect(find.text('Line 2'), findsOneWidget);
    await show(3);
    await tester.pumpAndSettle();
    expect(find.text('Line 0'), findsNothing);
    expect(find.text('Line 3'), findsOneWidget);
    expect(find.text('Line 4'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CompactPlaybackLyrics),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'portrait right alignment positions glyphs at the viewport right',
    (tester) async {
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileLyricsList(
              lines: [
                LyricLine(timestamp: Duration.zero, texts: const ['Hi']),
              ],
              active: 0,
              textAlign: TextAlign.right,
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
      final bounds = painter.cache.tokens.first.bounds as Rect;
      // Ink bounds include padding, so their left edge can be negative.
      // The legacy paragraph stays at its intrinsic origin rather than being
      // shifted hundreds of pixels to the viewport's right edge.
      expect(bounds.left, greaterThan(100));
      expect(bounds.center.dx, greaterThan(100));
    },
  );
}
