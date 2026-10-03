import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';
import 'package:myune_music/services/lyric_seek_notifier.dart';

void main() {
  for (final effect in [LyricScrollEffect.dynamic, LyricScrollEffect.elastic]) {
    testWidgets('first phrase seek/replay has no delayed row pose: $effect', (
      tester,
    ) async {
      final controller = MobileLyricsListController();
      final source = ValueNotifier(const Duration(milliseconds: 12090));
      final seek = LyricSeekNotifier();
      addTearDown(source.dispose);
      addTearDown(seek.dispose);
      final lines = List.generate(
        9,
        (i) => LyricLine(
          timestamp: Duration(seconds: i * 3),
          texts: ['中文 y g p $i', 'translation $i'],
        ),
      );
      var active = 3;
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
                  isPlaying: false,
                  positionListenable: source,
                  seekPositionListenable: seek,
                  scrollEffect: effect,
                  karaokeLyricsMode: KaraokeLyricsMode.all,
                  karaokeLyricsEnabled: true,
                  lineBlurEnabled: true,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      update(() => active = 4);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      // Seek into an in-flight focus transition, before the decoder updates.
      controller.settleOn(const Duration(milliseconds: 12400));
      await tester.pump();
      Finder row(int i) => find.byKey(ValueKey('mobile_lyric_$i'));
      double scale(int i) => tester
          .widget<ScaleTransition>(
            find
                .descendant(of: row(i), matching: find.byType(ScaleTransition))
                .first,
          )
          .scale
          .value;
      dynamic painter(int i) => tester
          .widget<CustomPaint>(
            find.descendant(
              of: row(i),
              matching: find.byKey(
                const ValueKey('mobile_karaoke_single_pass_paint'),
              ),
            ),
          )
          .painter;
      expect(scale(4), 1.1);
      expect(
        painter(4).positionListenable.value,
        const Duration(milliseconds: 12400),
      );
      final layouts = controller.fullTextLayoutCount;
      for (var replay = 0; replay < 2; replay++) {
        // The same zero seek target on consecutive replays is still an event.
        seek.publish(Duration.zero);
        update(() => active = 0);
        await tester.pump();
        expect(scale(0), 1.1, reason: 'no first-line focus catch-up');
        expect(painter(0).positionListenable.value, Duration.zero);
        expect(painter(0).highlightStrength, 1);
        final y = tester.getCenter(row(0)).dy;
        for (final hz in [60, 90, 120]) {
          await tester.pump(Duration(microseconds: (1000000 / hz).round()));
          expect(scale(0), 1.1);
          expect(tester.getCenter(row(0)).dy, closeTo(y, .01));
          expect(
            painter(0).positionListenable.value,
            Duration.zero,
            reason: 'late old decoder position cannot resurrect last phrase',
          );
        }
        source.value = Duration.zero;
        await tester.pump();
        expect(controller.fullTextLayoutCount, layouts);
        source.value = const Duration(milliseconds: 12090);
        update(() => active = 4);
        await tester.pump();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.binding.transientCallbackCount, 0);
    });
    for (final karaoke in [false, true]) {
      testWidgets('entry poses settle while hidden: $effect karaoke=$karaoke', (
        tester,
      ) async {
        final controller = MobileLyricsListController();
        final lines = List.generate(
          16,
          (i) => LyricLine(
            timestamp: Duration(seconds: i * 3),
            texts: ['中文 with y g p $i', 'translation $i'],
          ),
        );
        var active = 3;
        var ticking = true;
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return SizedBox(
                  height: 600,
                  child: TickerMode(
                    enabled: ticking,
                    child: MobileLyricsList(
                      controller: controller,
                      lines: lines,
                      active: active,
                      position: Duration(seconds: active * 3 + 1),
                      isPlaying: false,
                      entryPreparing: !ticking,
                      scrollEffect: effect,
                      karaokeLyricsEnabled: karaoke,
                      karaokeLyricsMode: KaraokeLyricsMode.all,
                      lineBlurEnabled: true,
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        update(() => active = 4);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        // Leaving mid-motion retains implicit tweens and row springs. The
        // next entry must resolve them BEFORE any lyric pixels become visible.
        update(() {
          ticking = false;
          active = 5;
        });
        controller.recenter();
        await tester.pump();
        await tester.pump();
        Finder row(int i) => find.byKey(ValueKey('mobile_lyric_$i'));
        double scale(int i) => tester
            .widget<ScaleTransition>(
              find
                  .descendant(
                    of: row(i),
                    matching: find.byType(ScaleTransition),
                  )
                  .first,
            )
            .scale
            .value;
        double spread(int i) => tester
            .widget<SlideTransition>(
              find
                  .descendant(
                    of: row(i),
                    matching: find.byType(SlideTransition),
                  )
                  .first,
            )
            .position
            .value
            .dy;
        double elastic(int i) => tester
            .widget<Transform>(
              find.byKey(ValueKey('mobile_lyric_elastic_transform_$i')),
            )
            .transform
            .storage[13];
        expect(scale(5), 1.1, reason: 'no delayed focus growth after reveal');
        expect(scale(4), 1);
        if (effect == LyricScrollEffect.dynamic) {
          expect([spread(4), spread(5), spread(6)], [-.16, 0, .22]);
        } else {
          expect(elastic(5), 0, reason: 'old muted spring must be cancelled');
        }
        update(() => ticking = true);
        await tester.pump();
        final visibleY = tester.getCenter(row(5)).dy;
        for (final hz in [60, 90, 120]) {
          for (var f = 0; f < (hz * .3).ceil(); f++) {
            await tester.pump(Duration(microseconds: (1000000 / hz).round()));
            expect(scale(5), 1.1);
            expect(tester.getCenter(row(5)).dy, closeTo(visibleY, .01));
          }
        }
        expect(controller.fullTextLayoutCount, 1);
        // Preparation must not turn the selected preset into a permanent snap.
        update(() => active = 6);
        await tester.pump();
        expect(scale(6), 1);
        await tester.pump(const Duration(milliseconds: 90));
        expect(scale(6), inExclusiveRange(1, 1.1));
        if (effect == LyricScrollEffect.elastic) {
          expect(elastic(6).abs(), greaterThan(1));
        }
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.binding.transientCallbackCount, 0);
      });
    }
  }
}
