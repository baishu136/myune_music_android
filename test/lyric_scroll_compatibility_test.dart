import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';

void main() {
  testWidgets(
    'empty lyrics and before-first-line index never retarget missing geometry',
    (tester) async {
      final active = ValueNotifier(0);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<int>(
            valueListenable: active,
            builder: (_, index, _) =>
                MobileLyricsList(lines: const [], active: index),
          ),
        ),
      );
      active.value = -1;
      await tester.pump();
      expect(tester.takeException(), isNull);
      active.value = 0;
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      active.dispose();
    },
  );
  testWidgets('karaoke toggle does not stop or reset an in-flight spring', (
    tester,
  ) async {
    var active = 1;
    var karaoke = false;
    late StateSetter update;
    final lines = List.generate(
      12,
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
                karaokeLyricsMode: KaraokeLyricsMode.all,
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    double y() =>
        tester.getCenter(find.byKey(const ValueKey('mobile_lyric_3'))).dy;
    update(() => active = 3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final before = y();
    update(() => karaoke = true);
    await tester.pump();
    expect(y(), closeTo(before, .01));
    await tester.pump(const Duration(microseconds: 16667));
    expect(y(), lessThan(before));
    final enabled = y();
    update(() => karaoke = false);
    await tester.pump();
    expect(y(), closeTo(enabled, .01));
    await tester.pump(const Duration(microseconds: 16667));
    expect(y(), lessThan(enabled));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'new next-row masks are deferred and invalidation cancels pending work',
    (tester) async {
      final pictures = debugKaraokeLivePictureCount;
      var active = 1;
      late StateSetter update;
      final lines = List.generate(
        25,
        (i) => LyricLine(
          timestamp: Duration(seconds: i),
          texts: ['字形排版 mixed English $i', '多行翻译 Translation $i'],
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
                  karaokeLyricsMode: KaraokeLyricsMode.all,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final layouts = debugKaraokeLayoutBuildCount;
      update(() => active = 2);
      await tester.pump();
      expect(
        debugKaraokeLayoutBuildCount,
        layouts,
        reason:
            'active cache retained; next cache must not be built at the boundary',
      );
      await tester.pump(const Duration(milliseconds: 1));
      expect(debugKaraokeLayoutBuildCount, layouts + 1);
      for (var f = 0; f < 60; f++) {
        await tester.pump(const Duration(microseconds: 16667));
      }
      expect(debugKaraokeLayoutBuildCount, layouts + 1);
      update(() => active = 3);
      await tester.pump();
      // Dispose before the macrotask, including its timer and native Pictures.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
      expect(debugKaraokeLivePictureCount, pictures);
    },
  );
  for (final hz in [60, 90, 120]) {
    for (final elastic in [false, true]) {
      testWidgets('same translated multi-row trajectory with karaoke on/off '
          'at $hz Hz (elastic=$elastic)', (tester) async {
        final lines = List.generate(
          30,
          (i) => LyricLine(
            timestamp: Duration(milliseconds: i * 200),
            texts: ['快速中文 mixed English $i', '翻译折行 natural translation $i'],
          ),
        );
        Future<List<double>> sample(bool karaoke) async {
          var active = 1;
          late StateSetter update;
          await tester.pumpWidget(
            MaterialApp(
              home: StatefulBuilder(
                builder: (_, setState) {
                  update = setState;
                  return SizedBox(
                    width: 300,
                    height: 600,
                    child: MobileLyricsList(
                      lines: lines,
                      active: active,
                      fontSize: 24,
                      karaokeLyricsEnabled: karaoke,
                      karaokeLyricsMode: KaraokeLyricsMode.all,
                      elasticScrollEnabled: elastic,
                    ),
                  );
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          double y() => tester
              .getCenter(
                find.descendant(
                  of: find.byKey(const ValueKey('mobile_lyric_4')),
                  matching: find.byKey(
                    const ValueKey('mobile_lyric_scaled_paint'),
                  ),
                ),
              )
              .dy;
          final result = <double>[y()];
          update(() => active = 3); // Decoder catch-up, not an explicit seek.
          await tester.pump();
          result.add(y());
          expect(
            result.last,
            closeTo(result.first, .01),
            reason: 'no prefix snap',
          );
          for (var f = 0; f < hz; f++) {
            if (f == (hz * .15).round()) {
              update(() => active = 4);
              await tester.pump();
              expect(y(), closeTo(result.last, .01), reason: 'retarget pose');
            }
            await tester.pump(Duration(microseconds: (1000000 / hz).round()));
            result.add(y());
          }
          await tester.pumpWidget(const SizedBox());
          return result;
        }

        final ordinary = await sample(false);
        final karaoke = await sample(true);
        for (var i = 0; i < ordinary.length; i++) {
          expect(karaoke[i], closeTo(ordinary[i], .01), reason: 'frame $i');
        }
      });
    }
  }

  testWidgets('distant translated rows do not allocate per-glyph masks', (
    tester,
  ) async {
    final lines = List.generate(
      60,
      (i) => LyricLine(
        timestamp: Duration(seconds: i),
        texts: ['字素缓存 mixed English $i', '翻译内容 Translation $i'],
      ),
    );
    final before = debugKaraokeLayoutBuildCount;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 600,
          child: MobileLyricsList(
            lines: lines,
            active: 3,
            karaokeLyricsMode: KaraokeLyricsMode.all,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(debugKaraokeLayoutBuildCount - before, lessThanOrEqualTo(2));
    expect(
      find.byKey(const ValueKey('mobile_karaoke_single_pass_paint')),
      findsNWidgets(2),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'blur-result boundary is below animated distance opacity and scale',
    (tester) async {
      final lines = List.generate(
        8,
        (i) => LyricLine(
          timestamp: Duration(seconds: i),
          texts: ['歌词 English $i', '翻译 $i'],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 600,
            child: MobileLyricsList(
              lines: lines,
              active: 1,
              lineBlurEnabled: true,
              karaokeLyricsMode: KaraokeLyricsMode.all,
            ),
          ),
        ),
      );
      final row = find.byKey(const ValueKey('mobile_lyric_2'));
      final cache = find.descendant(
        of: row,
        matching: find.byKey(const ValueKey('mobile_lyric_cached_blur')),
      );
      expect(cache, findsOneWidget);
      expect(
        find.ancestor(
          of: cache,
          matching: find.descendant(
            of: row,
            matching: find.byType(FadeTransition),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: cache,
          matching: find.descendant(
            of: row,
            matching: find.byType(ScaleTransition),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: cache,
          matching: find.byWidgetPredicate((widget) => widget is ImageFiltered),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
