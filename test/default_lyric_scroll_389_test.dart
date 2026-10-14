import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';
import 'package:myune_music/widgets/lyric_scroll_motion.dart';

void main() {
  testWidgets('default follow uses one scrolling activity at 60/90/120Hz', (
    tester,
  ) async {
    for (final hz in [60, 90, 120]) {
      var active = 1, starts = 0, ends = 0, updates = 0;
      late StateSetter update;
      final lines = List.generate(
        12,
        (i) => LyricLine(
          timestamp: Duration(seconds: i * 3),
          texts: ['歌词第$i行', 'Translation $i'],
        ),
      );
      final controller = MobileLyricsListController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n is ScrollStartNotification) starts++;
                if (n is ScrollEndNotification) ends++;
                if (n is ScrollUpdateNotification) updates++;
                return false;
              },
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return SizedBox(
                    height: 500,
                    child: MobileLyricsList(
                      lines: lines,
                      active: active,
                      fontSize: 24,
                      karaokeLyricsEnabled: false,
                      controller: controller,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final layouts = controller.fullTextLayoutCount;
      starts = ends = updates = 0;
      update(() => active = 2);
      await tester.pump();
      for (var frame = 0; frame < hz * 2; frame++) {
        await tester.pump(Duration(microseconds: (1000000 / hz).round()));
      }
      expect(updates, greaterThan(10));
      expect(
        starts,
        1,
        reason: 'one follow run, not a new jump per frame ($hz Hz)',
      );
      expect(ends, 1);
      expect(controller.fullTextLayoutCount, layouts);
      final scroll = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const ValueKey('mobile_lyrics_scroll_view')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scroll.position.isScrollingNotifier.value, isFalse);
      await tester.pumpWidget(const SizedBox());
    }
  });
  testWidgets(
    'dense default targets keep the analytic trajectory through delayed frames',
    (tester) async {
      var active = 1;
      late StateSetter update;
      final lines = List.generate(
        10,
        (i) => LyricLine(
          timestamp: Duration(seconds: i),
          texts: ['Line $i'],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return SizedBox(
                height: 500,
                child: MobileLyricsList(
                  lines: lines,
                  active: active,
                  fontSize: 24,
                  karaokeLyricsEnabled: false,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const ValueKey('mobile_lyrics_scroll_view')),
          matching: find.byType(Scrollable),
        ),
      );
      final start = scroll.position.pixels;
      final travel =
          tester.getCenter(find.byKey(const ValueKey('mobile_lyric_2'))).dy -
          tester.getCenter(find.byKey(const ValueKey('mobile_lyric_1'))).dy;
      final motion =
          LyricScrollMotion(
              frequency: mobileLyricsScrollFrequencyForFontSize(24),
              dampingRatio: .90,
            )
            ..sync(start)
            ..retarget(start + travel);
      update(() => active = 2);
      await tester.pump();
      for (final gap in [16, 120, 16, 240]) {
        await tester.pump(Duration(milliseconds: gap));
        expect(
          scroll.position.pixels,
          closeTo(motion.advance(gap / 1000), .0001),
        );
      }
      update(() => active = 3);
      motion.retarget(start + 2 * travel);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(scroll.position.pixels, closeTo(motion.advance(.016), .0001));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('mobile_lyrics_scroll_view')),
        const Offset(0, -80),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const ValueKey('mobile_lyrics_progress_guide')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
