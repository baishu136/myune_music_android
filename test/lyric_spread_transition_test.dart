import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';

void main() {
  for (final karaoke in [false, true]) {
    testWidgets(
      'explicit seeks snap spread; resumed focus change animates (karaoke=$karaoke)',
      (tester) async {
        final position = ValueNotifier(Duration.zero);
        final seek = ValueNotifier<Duration?>(null);
        final intent = ValueNotifier(0);
        var active = 0;
        late StateSetter update;
        final lines = List.generate(
          18,
          (i) => LyricLine(
            timestamp: Duration(seconds: i),
            texts: ['歌词 $i', 'translation $i'],
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
                    active: active,
                    positionListenable: position,
                    seekPositionListenable: seek,
                    seekIntentListenable: intent,
                    karaokeLyricsEnabled: karaoke,
                    scrollEffect: LyricScrollEffect.dynamic,
                    karaokeLyricsMode: KaraokeLyricsMode.all,
                  ),
                );
              },
            ),
          ),
        );
        // A playing karaoke clock intentionally stays active between source
        // callbacks; don't wait for its ticker to settle.
        await tester.pump(const Duration(milliseconds: 50));
        double offset(int i) => tester
            .widget<SlideTransition>(
              find.descendant(
                of: find.byKey(ValueKey('mobile_lyric_$i')),
                matching: find.byType(SlideTransition),
              ),
            )
            .position
            .value
            .dy;
        Future<void> jump(int target) async {
          intent.value++;
          position.value = Duration(seconds: target);
          seek.value = position.value;
          update(() => active = target);
          await tester.pump();
          expect(offset(target - 1), -.16);
          expect(offset(target), 0);
          expect(offset(target + 1), .22);
        }

        await jump(9);
        // Source and wall time advance together, not a disguised 1s seek.
        // This also lets the seek confirmation lock clear normally.
        for (var f = 0; f < 10; f++) {
          // The real playback page paints its progress/time each source tick.
          tester.binding.scheduleFrame();
          await tester.pump(const Duration(milliseconds: 100));
          position.value += const Duration(milliseconds: 100);
        }
        update(() => active = 10);
        await tester.pump();
        expect(
          offset(9),
          0,
          reason: 'normal update must not snap the local slide',
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(offset(9), inExclusiveRange(-.16, 0));
        await jump(2);
        await tester.pumpWidget(const SizedBox());
        position.dispose();
        seek.dispose();
        intent.dispose();
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
    testWidgets('original spread survives focus retarget (karaoke=$karaoke)', (
      tester,
    ) async {
      var active = 2;
      late StateSetter update;
      final lines = List.generate(
        10,
        (i) => LyricLine(
          timestamp: Duration(seconds: i),
          texts: ['歌词 English $i', '翻译 $i'],
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
                  active: active,
                  karaokeLyricsEnabled: karaoke,
                  scrollEffect: LyricScrollEffect.dynamic,
                  karaokeLyricsMode: KaraokeLyricsMode.all,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      Finder row(int i) => find.byKey(ValueKey('mobile_lyric_$i'));
      Finder slide(int i) => find.descendant(
        of: row(i),
        matching: find.byWidgetPredicate((w) => w is AnimatedSlide),
      );
      double offset(int i) => tester
          .widget<SlideTransition>(
            find.descendant(
              of: slide(i),
              matching: find.byType(SlideTransition),
            ),
          )
          .position
          .value
          .dy;
      expect(offset(1), -.16);
      expect(offset(2), 0);
      expect(offset(3), .22);
      update(() => active = 3);
      await tester.pump();
      expect(offset(2), 0, reason: 'retarget starts from displayed pose');
      expect(offset(3), .22);
      await tester.pump(const Duration(milliseconds: 100));
      final before = offset(3);
      expect(before, inExclusiveRange(0, .22));
      update(() => active = 4);
      await tester.pump();
      expect(offset(3), closeTo(before, .00001));
      await tester.pumpAndSettle();
      expect(offset(3), -.16);
      expect(offset(4), 0);
      expect(offset(5), .22);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('default, dynamic and elastic select distinct row trajectories', (
    tester,
  ) async {
    var effect = LyricScrollEffect.standard;
    late StateSetter update;
    final lines = List.generate(
      10,
      (i) => LyricLine(
        timestamp: Duration(seconds: i * 2),
        texts: ['中文 English $i', '翻译 $i'],
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
                active: 3,
                scrollEffect: effect,
                karaokeLyricsMode: KaraokeLyricsMode.all,
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    double offset(int i) => tester
        .widget<SlideTransition>(
          find.descendant(
            of: find.byKey(ValueKey('mobile_lyric_$i')),
            matching: find.byType(SlideTransition),
          ),
        )
        .position
        .value
        .dy;
    expect([offset(2), offset(3), offset(4)], [0, 0, 0]);

    update(() => effect = LyricScrollEffect.dynamic);
    await tester.pump();
    await tester.pumpAndSettle();
    expect([offset(2), offset(3), offset(4)], [-.16, 0, .22]);

    update(() => effect = LyricScrollEffect.elastic);
    await tester.pump();
    await tester.pumpAndSettle();
    expect([offset(2), offset(3), offset(4)], [0, 0, 0]);
    expect(
      find.byKey(const ValueKey('mobile_lyric_elastic_transform_3')),
      findsOneWidget,
    );
  });

  testWidgets(
    'inactive karaoke originals share typography and visual targets',
    (tester) async {
      final lines = List.generate(
        12,
        (i) => LyricLine(
          timestamp: Duration(seconds: i),
          texts: ['中文 English $i', '翻译 $i'],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: SizedBox(
            height: 700,
            child: MobileLyricsList(
              lines: lines,
              active: 3,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              fontFamily: 'MiSans',
              karaokeLyricsMode: KaraokeLyricsMode.all,
              lineBlurEnabled: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      TextStyle? reference;
      double? alpha;
      Object? blur;
      for (final i in [0, 1, 2, 4, 5, 6]) {
        final row = find.byKey(ValueKey('mobile_lyric_$i'));
        final style = tester
            .widget<AnimatedDefaultTextStyle>(
              find.descendant(
                of: row,
                matching: find.byWidgetPredicate(
                  (w) => w is AnimatedDefaultTextStyle,
                ),
              ),
            )
            .style;
        reference ??= style;
        expect(style, reference, reason: 'inactive row $i typography');
        final opacity = tester
            .widget<AnimatedOpacity>(
              find.descendant(
                of: row,
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is AnimatedOpacity &&
                      w.key == const ValueKey('mobile_lyric_distance_opacity'),
                ),
              ),
            )
            .opacity;
        alpha ??= opacity;
        expect(opacity, alpha, reason: 'inactive row $i alpha');
        final filter = tester
            .widget<ImageFiltered>(
              find.descendant(
                of: row,
                matching: find.byWidgetPredicate(
                  (widget) => widget is ImageFiltered,
                ),
              ),
            )
            .imageFilter;
        blur ??= filter;
        expect(filter, blur, reason: 'inactive row $i blur');
        expect(
          tester
              .widget<AnimatedScale>(
                find.descendant(
                  of: row,
                  matching: find.byWidgetPredicate((w) => w is AnimatedScale),
                ),
              )
              .scale,
          1,
        );
      }
      expect(reference!.fontSize, 26);
      expect(reference.fontWeight, FontWeight.w800);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
