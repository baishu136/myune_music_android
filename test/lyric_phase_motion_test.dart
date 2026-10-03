import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/widgets/lyric_normalized_motion.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';
import 'package:myune_music/widgets/interlude_animation_widget.dart';

void main() {
  test('rest launch has no impulse and reaches a compact exact endpoint', () {
    final motion = LyricNormalizedMotion()..retarget(70);
    expect(motion.velocity, 0);
    motion.advance(1 / 60);
    expect(motion.offset, inExclusiveRange(0, 1.5));
    motion.advance(.38 - 1 / 60);
    expect(motion.offset, greaterThan(70 * .99));
    motion.advance(.04);
    expect(motion.isSettled, isTrue);
    expect(motion.offset, 70);
    expect(motion.velocity, 0);
  });

  testWidgets('incoming and outgoing scale and alpha share default cadence', (
    tester,
  ) async {
    for (final hz in [60, 90, 120]) {
      for (final wrapped in [false, true]) {
        var active = 1;
        late StateSetter update;
        final lines = List.generate(
          7,
          (i) => LyricLine(
            timestamp: Duration(seconds: i * 2),
            texts: [wrapped ? '长句折行 mixed English 自然缓动 歌词 $i' : '歌词 $i'],
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (_, setState) {
                  update = setState;
                  return SizedBox(
                    width: wrapped ? 250 : 600,
                    height: 600,
                    child: MobileLyricsList(
                      lines: lines,
                      active: active,
                      fontSize: 20,
                      karaokeLyricsMode: KaraokeLyricsMode.all,
                      brightForeground: true,
                      lineBlurEnabled: true,
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Finder part(int index, Type type) => find.descendant(
          of: find.byKey(ValueKey('mobile_lyric_$index')),
          matching: find.byWidgetPredicate(
            (widget) => type == AnimatedScale
                ? widget is AnimatedScale
                : widget.runtimeType == type,
          ),
        );
        final row = find.byKey(const ValueKey('mobile_lyric_2'));
        final before = tester.getCenter(row).dy;
        final travel =
            before -
            tester.getCenter(find.byKey(const ValueKey('mobile_lyric_1'))).dy;
        update(() => active = 2);
        await tester.pump();
        final duration = tester
            .widget<AnimatedScale>(part(2, AnimatedScale))
            .duration;
        expect(duration, mobileLyricsDefaultScrollTransitionDuration);
        final startBlur = tester.widget<ImageFiltered>(
          find.descendant(
            of: row,
            matching: find.byKey(const ValueKey('mobile_lyric_blur_filter')),
          ),
        );
        expect(
          startBlur.imageFilter,
          ui.ImageFilter.blur(sigmaX: .9, sigmaY: .9, tileMode: TileMode.decal),
          reason:
              'incoming row retains its preparatory appearance at the boundary',
        );
        final layoutCount = debugKaraokeLayoutBuildCount;
        for (var frame = 1; frame <= (hz * .5).ceil(); frame++) {
          await tester.pump(Duration(microseconds: (1000000 / hz).round()));
          final p = mobileLyricsFocusTransitionCurve.transform(
            (frame * (1000000 / hz).round() / duration.inMicroseconds).clamp(
              0.0,
              1.0,
            ),
          );
          expect(tester.getCenter(row).dy, lessThan(before));
          expect(
            before - tester.getCenter(row).dy,
            lessThanOrEqualTo(travel + .4),
          );
          final incoming = tester.widget<ScaleTransition>(
            part(2, ScaleTransition),
          );
          final outgoing = tester.widget<ScaleTransition>(
            part(1, ScaleTransition),
          );
          final alpha = tester.widget<FadeTransition>(
            part(2, FadeTransition).first,
          );
          expect(incoming.scale.value, closeTo(1 + .1 * p, .0001));
          expect(outgoing.scale.value, closeTo(1.1 - .1 * p, .0001));
          expect(
            alpha.opacity.value,
            1,
            reason:
                'karaoke composes focus alpha only once inside its ink painter',
          );
          final outgoingAlpha = tester.widget<FadeTransition>(
            part(1, FadeTransition).first,
          );
          expect(
            outgoingAlpha.opacity.value,
            1,
            reason: 'exit fades sung ink, not the dim original/translation',
          );
          expect(
            debugKaraokeLayoutBuildCount,
            lessThanOrEqualTo(layoutCount + 1),
            reason: 'one deferred next-line preparation, not per-frame layout',
          );
          final incomingBlur = tester.widget<ImageFiltered>(
            find.descendant(
              of: row,
              matching: find.byKey(const ValueKey('mobile_lyric_blur_filter')),
            ),
          );
          final outgoingBlur = tester.widget<ImageFiltered>(
            find.descendant(
              of: find.byKey(const ValueKey('mobile_lyric_1')),
              matching: find.byKey(const ValueKey('mobile_lyric_blur_filter')),
            ),
          );
          final incomingSigma = ((.9 * (1 - p)) * 20).round() / 20;
          const outgoingSigma = .9;
          expect(
            incomingBlur.imageFilter,
            ui.ImageFilter.blur(
              sigmaX: incomingSigma,
              sigmaY: incomingSigma,
              tileMode: TileMode.decal,
            ),
          );
          expect(
            outgoingBlur.imageFilter,
            ui.ImageFilter.blur(
              sigmaX: outgoingSigma,
              sigmaY: outgoingSigma,
              tileMode: TileMode.decal,
            ),
          );
        }
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets('interlude exit and first text centering start together', (
    tester,
  ) async {
    var active = 0;
    late StateSetter update;
    final lines = [
      LyricLine(
        timestamp: Duration.zero,
        texts: const [],
        isInterlude: true,
        interludeDuration: const Duration(seconds: 10),
      ),
      LyricLine(timestamp: const Duration(seconds: 10), texts: const ['第一句歌词']),
      LyricLine(
        timestamp: const Duration(seconds: 12),
        texts: const ['接下来的歌词'],
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return SizedBox(
                height: 600,
                child: MobileLyricsList(
                  lines: lines,
                  active: active,
                  isPlaying: true,
                  karaokeLyricsMode: KaraokeLyricsMode.all,
                  lineBlurEnabled: false,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    final row = find.byKey(const ValueKey('mobile_lyric_1'));
    final start = tester.getCenter(row).dy;
    update(() => active = 1);
    await tester.pump();
    final duration = tester
        .widget<AnimatedScale>(
          find.descendant(
            of: row,
            matching: find.byWidgetPredicate(
              (widget) => widget is AnimatedScale,
            ),
          ),
        )
        .duration;
    await tester.pump(const Duration(microseconds: 16667));
    expect(tester.getCenter(row).dy, lessThan(start));
    final exit = tester.widget<FadeTransition>(
      find.byKey(const ValueKey('interlude_exit_visibility')),
    );
    expect(exit.opacity.value, inExclusiveRange(0, 1));
    await tester.pump(duration - const Duration(microseconds: 16667));
    await tester.pumpAndSettle();
    expect(tester.getCenter(row).dy, closeTo(240, .01));
    expect(exit.opacity.value, 0);
    expect(
      tester
          .widget<ScaleTransition>(
            find.descendant(of: row, matching: find.byType(ScaleTransition)),
          )
          .scale
          .value,
      1.1,
    );
    expect(find.byType(InterludeAnimationWidget), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dense retarget preserves every visible scale and alpha', (
    tester,
  ) async {
    var active = 1;
    late StateSetter update;
    final lines = List.generate(
      8,
      (i) => LyricLine(
        timestamp: Duration(seconds: i),
        texts: ['歌词 $i'],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return SizedBox(
                height: 600,
                child: MobileLyricsList(
                  lines: lines,
                  active: active,
                  isPlaying: true,
                  karaokeLyricsMode: KaraokeLyricsMode.all,
                  lineBlurEnabled: true,
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
    await tester.pump(const Duration(milliseconds: 80));
    Finder part(int row, Type type) => find.descendant(
      of: find.byKey(ValueKey('mobile_lyric_$row')),
      matching: find.byType(type),
    );
    final scales = [
      for (var i = 1; i <= 3; i++)
        tester.widget<ScaleTransition>(part(i, ScaleTransition)).scale.value,
    ];
    final alphas = [
      for (var i = 1; i <= 3; i++)
        tester
            .widget<FadeTransition>(part(i, FadeTransition).first)
            .opacity
            .value,
    ];
    final row = find.byKey(const ValueKey('mobile_lyric_3'));
    Finder blur(int i) => find.descendant(
      of: find.byKey(ValueKey('mobile_lyric_$i')),
      matching: find.byKey(const ValueKey('mobile_lyric_blur_filter')),
    );
    final before = tester.getCenter(row).dy;
    update(() => active = 3);
    await tester.pump(); // No time elapsed: re-target itself must not jump.
    expect(tester.getCenter(row).dy, closeTo(before, 1e-8));
    expect(
      tester.widget<ImageFiltered>(blur(3)).imageFilter,
      ui.ImageFilter.blur(sigmaX: .9, sigmaY: .9, tileMode: TileMode.decal),
      reason:
          'retarget cannot sharpen the new incoming row in zero elapsed time',
    );
    expect(
      tester.widget<ImageFiltered>(blur(2)).imageFilter,
      ui.ImageFilter.blur(sigmaX: .9, sigmaY: .9, tileMode: TileMode.decal),
    );
    for (var i = 1; i <= 3; i++) {
      expect(
        tester.widget<ScaleTransition>(part(i, ScaleTransition)).scale.value,
        closeTo(scales[i - 1], 1e-8),
        reason: 'row $i scale at retarget',
      );
      expect(
        tester
            .widget<FadeTransition>(part(i, FadeTransition).first)
            .opacity
            .value,
        closeTo(alphas[i - 1], 1e-8),
        reason: 'row $i alpha at retarget',
      );
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
