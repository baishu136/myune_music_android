import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/widgets/fullscreen_lyrics_double_tap.dart';
import 'package:myune_music/widgets/lyric_seek_guide.dart';
import 'package:myune_music/widgets/lyrics_song_swipe_transition.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';

Finder row(int i) => find.byKey(ValueKey('mobile_lyric_$i'));
double spread(WidgetTester tester, int i) => tester
    .widget<SlideTransition>(
      find.descendant(of: row(i), matching: find.byType(SlideTransition)).first,
    )
    .position
    .value
    .dy;
double scale(WidgetTester tester, int i) => tester
    .widget<ScaleTransition>(
      find.descendant(of: row(i), matching: find.byType(ScaleTransition)).first,
    )
    .scale
    .value;

void main() {
  testWidgets('pre-roll remains unfocused through entry and backward seek', (
    tester,
  ) async {
    final source = ValueNotifier(const Duration(seconds: 2));
    final seek = ValueNotifier<Duration?>(null);
    addTearDown(source.dispose);
    addTearDown(seek.dispose);
    var preparing = false;
    late StateSetter update;
    final lines = List.generate(
      6,
      (i) => LyricLine(
        timestamp: Duration(seconds: 10 + i * 3),
        texts: ['原文 $i', 'translation $i'],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return SizedBox(
              height: 600,
              child: MobileLyricsList(
                lines: lines,
                active: -1,
                entryPreparing: preparing,
                positionListenable: source,
                seekPositionListenable: seek,
                isPlaying: false,
                karaokeLyricsEnabled: false,
                lineBlurEnabled: false,
                scrollEffect: LyricScrollEffect.dynamic,
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(scale(tester, 0), 1, reason: '-1 is absence of focus, not row zero');
    final inactive = DefaultTextStyle.of(
      tester.element(
        find.descendant(of: row(0), matching: find.byType(Text)).first,
      ),
    ).style.color;
    expect(inactive, isNot(Colors.white));
    update(() => preparing = true);
    await tester.pump();
    update(() => preparing = false);
    await tester.pump();
    seek.value = const Duration(seconds: 1);
    await tester.pump();
    expect(
      scale(tester, 0),
      1,
      reason: 'seek before the first timestamp cannot invent focus',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'hidden entry discards browse chrome rather than replaying its fade',
    (tester) async {
      final controller = MobileLyricsListController();
      final lines = List.generate(
        16,
        (i) => LyricLine(
          timestamp: Duration(seconds: 10 + i * 3),
          texts: ['line $i'],
        ),
      );
      var active = 3, preparing = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return SizedBox(
                height: 600,
                child: MobileLyricsList(
                  controller: controller,
                  lines: lines,
                  active: active,
                  entryPreparing: preparing,
                  isPlaying: false,
                  karaokeLyricsEnabled: false,
                  scrollEffect: LyricScrollEffect.dynamic,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('mobile_lyrics_scroll_view')),
        const Offset(0, -160),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mobile_lyrics_browse_time_visible')),
        findsOneWidget,
      );
      update(() {
        preparing = true;
        active = -1;
      });
      await tester.pump();
      await tester.pump();
      expect(find.byType(LyricSeekGuide), findsNothing);
      update(() => preparing = false);
      await tester.pump();
      expect(find.byType(LyricSeekGuide), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final karaoke in [false, true]) {
    testWidgets(
      'dynamic double tap and horizontal song gesture preserve pose: karaoke=$karaoke',
      (tester) async {
        var playing = false, identity = 'a';
        var toggles = 0, songs = 0;
        late StateSetter update;
        final lines = List.generate(
          8,
          (i) => LyricLine(
            timestamp: Duration(seconds: i * 3),
            texts: ['line $i', 'translation $i'],
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return SizedBox(
                  height: 600,
                  child: FullscreenLyricsDoubleTap(
                    enabled: true,
                    onTogglePlayback: () => update(() {
                      playing = !playing;
                      toggles++;
                    }),
                    child: LyricsSongSwipeTransition(
                      enabled: true,
                      songIdentity: identity,
                      onNext: () async => update(() {
                        identity = 'b';
                        songs++;
                      }),
                      onPrevious: () async {},
                      child: MobileLyricsList(
                        lines: lines,
                        active: 2,
                        contentIdentity: identity,
                        isPlaying: playing,
                        karaokeLyricsEnabled: karaoke,
                        karaokeLyricsMode: KaraokeLyricsMode.all,
                        lineBlurEnabled: false,
                        scrollEffect: LyricScrollEffect.dynamic,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final before = [
          spread(tester, 1),
          spread(tester, 2),
          spread(tester, 3),
        ];
        final area = find.byKey(const ValueKey('mobile_lyrics_scroll_view'));
        final point = tester.getCenter(area);
        final tap = await tester.startGesture(point);
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          [spread(tester, 1), spread(tester, 2), spread(tester, 3)],
          before,
          reason: 'pointer down is not vertical browse',
        );
        await tap.up();
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(point);
        await tester.pump();
        expect(toggles, 1);
        await tester.pump(const Duration(milliseconds: 80));
        expect([
          spread(tester, 1),
          spread(tester, 2),
          spread(tester, 3),
        ], before);
        expect(find.byType(LyricSeekGuide), findsNothing);
        final swipe = await tester.startGesture(point);
        await swipe.moveBy(const Offset(-30, 0));
        await swipe.moveBy(const Offset(-130, 0));
        await tester.pump(const Duration(milliseconds: 40));
        expect(
          [spread(tester, 1), spread(tester, 2), spread(tester, 3)],
          before,
          reason: 'horizontal gesture must not collapse focus spread',
        );
        await swipe.up();
        await tester.pumpAndSettle();
        expect(songs, 1);
        expect([
          spread(tester, 1),
          spread(tester, 2),
          spread(tester, 3),
        ], before);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
