import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';
import 'package:myune_music/widgets/lyric_scroll_motion.dart';

void main() {
  testWidgets(
    'karaoke paint anchors preserve the original focus spread at 60/90/120 Hz',
    (tester) async {
      for (final hz in [60, 90, 120]) {
        for (final mode in [
          KaraokeLyricsMode.all,
          KaraokeLyricsMode.timedOnly,
        ]) {
          var active = 1;
          late StateSetter update;
          final lines = List.generate(8, (i) {
            final original = i.isEven ? '快速中文 mixed English' : '长句歌词折行自然显示';
            return LyricLine(
              timestamp: Duration(seconds: i * 2),
              texts: [original, '静态翻译 $i'],
              tokens: mode == KaraokeLyricsMode.timedOnly
                  ? [
                      [
                        LyricToken(
                          text: original,
                          start: Duration(seconds: i * 2),
                          end: Duration(seconds: i * 2 + 2),
                        ),
                      ],
                      [],
                    ]
                  : null,
            );
          });
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return SizedBox(
                      width: 280,
                      height: 600,
                      child: MobileLyricsList(
                        lines: lines,
                        active: active,
                        fontSize: 24,
                        karaokeLyricsMode: mode,
                        scrollEffect: LyricScrollEffect.dynamic,
                        elasticScrollEnabled: false,
                      ),
                    );
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          Finder paint(int index) => find.descendant(
            of: find.byKey(ValueKey('mobile_lyric_$index')),
            matching: find.byKey(const ValueKey('mobile_lyric_scaled_paint')),
          );
          double spacing(int a, int b) =>
              tester.getCenter(paint(b)).dy - tester.getCenter(paint(a)).dy;
          final firstGap = spacing(1, 2);
          final secondGap = spacing(2, 3);
          final startY = tester.getCenter(paint(2)).dy;
          final height1 = tester
              .getSize(find.byKey(const ValueKey('mobile_lyric_1')))
              .height;
          final height2 = tester
              .getSize(find.byKey(const ValueKey('mobile_lyric_2')))
              .height;
          final travel =
              tester
                  .getCenter(find.byKey(const ValueKey('mobile_lyric_2')))
                  .dy -
              tester.getCenter(find.byKey(const ValueKey('mobile_lyric_1'))).dy;
          final motion = LyricScrollMotion(
            frequency: mobileLyricsScrollFrequencyForFontSize(24),
            dampingRatio: .90,
          )..retarget(travel);
          update(() => active = 2);
          await tester.pump();
          for (var frame = 0; frame < hz * .6; frame++) {
            await tester.pump(Duration(microseconds: (1000000 / hz).round()));
            final p = mobileLyricsFocusTransitionCurve.transform(
              (((frame + 1) * (1000000 / hz).round()) /
                      mobileLyricsKaraokeLineShiftDuration.inMicroseconds)
                  .clamp(0.0, 1.0),
            );
            expect(
              spacing(1, 2),
              closeTo(firstGap + (.16 * height1 - .22 * height2) * p, .01),
              reason: '$mode $hz Hz frame $frame',
            );
            motion.advance((1000000 / hz).round() / 1000000);
            final expected = startY - motion.offset - .22 * height2 * p;
            expect(tester.getCenter(paint(2)).dy, closeTo(expected, .01));
            expect(
              spacing(2, 3),
              closeTo(secondGap + .22 * height2 * p, .01),
              reason: '$mode $hz Hz frame $frame',
            );
          }
          expect(
            find.byWidgetPredicate((w) => w is AnimatedSlide),
            findsWidgets,
          );
          expect(
            find.byWidgetPredicate(
              (w) => w.key.toString().contains('mobile_lyric_elastic_'),
            ),
            findsNothing,
          );
          await tester.pumpWidget(const SizedBox());
        }
      }
    },
  );

  testWidgets('enabling karaoke preserves an in-flight shared trajectory', (
    tester,
  ) async {
    var enabled = false;
    var active = 1;
    late StateSetter update;
    final lines = List.generate(
      8,
      (i) => LyricLine(
        timestamp: Duration(seconds: i * 2),
        texts: ['歌词 $i', '翻译 $i'],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return SizedBox(
                height: 600,
                child: MobileLyricsList(
                  lines: lines,
                  active: active,
                  karaokeLyricsEnabled: enabled,
                  karaokeLyricsMode: KaraokeLyricsMode.all,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    update(() => active = 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final slides = find.byWidgetPredicate((w) => w is AnimatedSlide);
    expect(slides, findsWidgets);
    final elements = tester.elementList(slides).toList();
    double y(int index) => tester
        .getCenter(
          find.descendant(
            of: find.byKey(ValueKey('mobile_lyric_$index')),
            matching: find.byKey(const ValueKey('mobile_lyric_scaled_paint')),
          ),
        )
        .dy;
    final before = [
      for (final i in [1, 2, 3]) y(i),
    ];
    update(() => enabled = true);
    await tester.pump();
    expect(tester.elementList(slides).toList(), elements);
    for (var i = 1; i <= 3; i++) {
      expect(y(i), closeTo(before[i - 1], .01));
    }
    for (var frame = 0; frame < 36; frame++) {
      for (final index in [1, 2, 3]) {
        final row = find.byKey(ValueKey('mobile_lyric_$index'));
        final paint = find.descendant(
          of: row,
          matching: find.byKey(const ValueKey('mobile_lyric_scaled_paint')),
        );
        expect(tester.getCenter(paint).dy.isFinite, isTrue);
      }
      await tester.pump(const Duration(microseconds: 16667));
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'offscreen next line warms before activation and transfers ownership',
    (tester) async {
      final picturesBefore = debugKaraokeLivePictureCount;
      final position = ValueNotifier(Duration.zero);
      final lines = [
        LyricLine(
          timestamp: Duration.zero,
          texts: [List.filled(160, 'longEnglishWord ').join()],
        ),
        LyricLine(
          timestamp: const Duration(seconds: 2),
          texts: const ['下一行中文 mixed English', '静态翻译'],
        ),
      ];
      Widget host(int active, {double width = 180}) => MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: 120,
            child: MobileLyricsList(
              lines: lines,
              active: active,
              positionListenable: position,
              fontSize: 28,
              karaokeLyricsMode: KaraokeLyricsMode.all,
            ),
          ),
        ),
      );
      await tester.pumpWidget(host(0));
      await tester.pump();
      expect(find.byKey(const ValueKey('mobile_lyric_1')), findsNothing);
      final layouts = debugKaraokeLayoutBuildCount;
      for (var frame = 1; frame <= 100; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        position.value = Duration(milliseconds: frame * 16);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(debugKaraokeLayoutBuildCount, layouts + 1);
      final warmed = debugKaraokeLayoutBuildCount;
      await tester.pumpWidget(host(1));
      await tester.pump();
      expect(find.byKey(const ValueKey('mobile_lyric_1')), findsOneWidget);
      expect(debugKaraokeLayoutBuildCount, warmed);
      await tester.pumpWidget(host(1, width: 220));
      expect(debugKaraokeLayoutBuildCount, greaterThan(warmed));
      await tester.pumpWidget(const SizedBox());
      expect(debugKaraokeLivePictureCount, picturesBefore);
      position.dispose();
    },
  );

  testWidgets('moving karaoke rows use stable discrete blur filters', (
    tester,
  ) async {
    final active = ValueNotifier(0);
    final lines = List.generate(
      12,
      (i) => LyricLine(
        timestamp: Duration(seconds: i * 2),
        texts: ['歌词 line $i', '翻译 $i'],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: active,
            builder: (_, index, _) => MobileLyricsList(
              lines: lines,
              active: index,
              karaokeLyricsMode: KaraokeLyricsMode.all,
              lineBlurEnabled: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    active.value = 1;
    await tester.pump();
    ui.ImageFilter filter() => tester
        .widget<ImageFiltered>(
          find.descendant(
            of: find.byKey(const ValueKey('mobile_lyric_2')),
            matching: find.byWidgetPredicate(
              (widget) => widget is ImageFiltered,
            ),
          ),
        )
        .imageFilter;
    final target = filter();
    expect(
      target,
      ui.ImageFilter.blur(sigmaX: .9, sigmaY: .9, tileMode: TileMode.decal),
    );
    for (var frame = 0; frame < 25; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(filter(), same(target));
    }
    await tester.pumpWidget(const SizedBox());
    active.dispose();
  });
}
