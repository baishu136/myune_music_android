import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/karaoke_motion.dart';

KaraokeGlyphTiming timing(int start, [int span = 120000]) => KaraokeGlyphTiming(
  sourceTokenStartUs: start,
  sourceTokenEndUs: start + span,
  visualTokenStartUs: start,
  highlightStartUs: start,
  highlightEndUs: start + span,
  liftStartUs: start,
);

void main() {
  final config = KaraokeMotionConfig(fastOvershootFraction: 0);
  test(
    'fast lift gently crosses its retained height then settles, deterministically',
    () {
      final config = KaraokeMotionConfig();
      final fast = timing(0, 80000), slow = timing(0, 600000);
      final wave = KaraokeFollowerTimeline([
        KaraokeFollowerGlyph(timing: fast, chain: 0),
      ], config);
      expect(wave.ownAt(0, 700000), greaterThan(1));
      expect(wave.ownAt(0, 1200000), 1);
      expect(karaokeGlyphLiftAt(700000, slow, config), lessThanOrEqualTo(1));
      for (final hz in [60, 90, 120]) {
        double previous = 0, velocity = 0, peak = 0;
        for (var frame = 0; frame <= hz * 2; frame++) {
          final time = (frame * 1000000 / hz).round();
          final next = wave.ownAt(0, time);
          final speed = (next - previous) * hz;
          expect((next - previous).abs(), lessThan(.06));
          expect((speed - velocity).abs(), lessThan(1.1));
          expect(next, karaokeGlyphLiftAt(time, fast, config));
          if (next > peak) peak = next;
          previous = next;
          velocity = speed;
        }
        expect(peak, inExclusiveRange(1, 1.15));
        expect(previous, 1);
      }
    },
  );

  test(
    'follower pre-lift grows modestly without reaching the fourth neighbour',
    () {
      final motion = KaraokeFollowerTimeline([
        for (var i = 0; i < 5; i++)
          KaraokeFollowerGlyph(timing: timing(i * 2000000, 600000), chain: 0),
      ], config);
      final old = KaraokeFollowerTimeline([
        for (var i = 0; i < 5; i++)
          KaraokeFollowerGlyph(timing: timing(i * 2000000, 600000), chain: 0),
      ], KaraokeMotionConfig(followerWeights: const [.24, .12, .05]));
      for (var i = 1; i <= 3; i++) {
        expect(motion.liftAt(i, 500000), greaterThan(old.liftAt(i, 500000)));
        expect(motion.liftAt(i, 500000), lessThan(old.liftAt(i, 500000) * 1.5));
      }
      expect(motion.liftAt(4, 500000), 0);
    },
  );
  test('complete Han and kana graphemes use compact-script continuity', () {
    for (final text in ['中文', 'かなカナ', 'か\u3099', '\u{20000}\u{E0100}']) {
      expect(karaokeHasCompactFollowerScript(text), isTrue, reason: text);
    }
    for (final text in ['', '中文 歌', 'Follow', '中a', '한글', '👨‍👩‍👧']) {
      expect(karaokeHasCompactFollowerScript(text), isFalse, reason: text);
    }
  });

  test(
    'fast recoil and three followers stay bounded at all rates with seek equivalence',
    () {
      final config = KaraokeMotionConfig();
      final glyphs = [
        for (var i = 0; i < 8; i++)
          KaraokeFollowerGlyph(timing: timing(i * 80000, 80000), chain: 0),
      ];
      final wave = KaraokeFollowerTimeline(glyphs, config);
      final direct = KaraokeFollowerTimeline(glyphs, config);
      final output = Float64List(8), target = Float64List(8);
      const retainedHeight = 40 * .07;
      const heightScale = .07 / .055;
      for (final hz in [60, 90, 120]) {
        for (final rate in [.75, 1.0, 1.5, 2.0]) {
          final previous = Float64List(8), velocities = Float64List(8);
          var peak = 0.0;
          for (var frame = 0; frame <= hz * 3; frame++) {
            final us = (frame * 1000000 / hz * rate).round();
            wave.writeOffsets(us, 40, output);
            for (var i = 0; i < 8; i++) {
              final velocity = (output[i] - previous[i]) * hz;
              expect(output[i], inInclusiveRange(-retainedHeight * 1.1, 0));
              expect(
                (output[i] - previous[i]).abs(),
                lessThan(.35 * heightScale),
              );
              expect(
                (velocity - velocities[i]).abs(),
                lessThan(5 * heightScale),
              );
              previous[i] = output[i];
              velocities[i] = velocity;
              if (-output[i] > peak) peak = -output[i];
            }
          }
          expect(peak, greaterThan(retainedHeight));
          expect(output, everyElement(closeTo(-retainedHeight, 1e-12)));
        }
      }
      for (final us in [700000, 100000, 1300000, 700000]) {
        wave.writeOffsets(us, 40, output);
        direct.writeOffsets(us, 40, target);
        expect(output, target);
        for (var i = 0; i < 60; i++) {
          wave.writeOffsets(us, 40, output);
          expect(
            output,
            target,
            reason: 'a paused media clock cannot integrate recoil',
          );
        }
      }
    },
  );

  test(
    'word bridge respects local gaps and backwards time, independently of highlight',
    () {
      final previous = timing(0, 200000);
      expect(
        karaokeFollowerTimingConnected(
          previous,
          timing(230000, 100000),
          config,
          wordBoundary: true,
        ),
        isTrue,
      );
      expect(
        karaokeFollowerTimingConnected(
          previous,
          timing(236000, 100000),
          config,
          wordBoundary: true,
        ),
        isFalse,
      );
      expect(
        karaokeFollowerTimingConnected(
          previous,
          timing(600000),
          config,
          wordBoundary: true,
        ),
        isFalse,
      );
      expect(
        karaokeFollowerTimingConnected(
          timing(600000),
          previous,
          config,
          wordBoundary: true,
        ),
        isFalse,
      );
      for (final value in [-.1, .16, double.nan]) {
        expect(
          () => KaraokeMotionConfig(fastOvershootFraction: value),
          throwsRangeError,
        );
      }
      expect(
        () => KaraokeMotionConfig(
          maxWordFollowerGap: const Duration(milliseconds: 121),
        ),
        throwsRangeError,
      );
    },
  );

  test('short gaps connect motion only, never the real highlight gap', () {
    final before = timing(0, 190000), next = timing(220000, 190000);
    expect(karaokeFollowerTimingConnected(before, next, config), isFalse);
    expect(
      karaokeFollowerTimingConnected(before, next, config, compactScript: true),
      isTrue,
    );
    final motion = KaraokeFollowerTimeline([
      KaraokeFollowerGlyph(timing: before, chain: 0),
      KaraokeFollowerGlyph(timing: next, chain: 0),
    ], config);
    for (var us = 190000; us < 220000; us += 8333) {
      expect(karaokeGlyphHighlightAt(us, before), 1);
      expect(karaokeGlyphHighlightAt(us, next), 0);
      expect(motion.ownAt(1, us), 0);
      expect(motion.liftAt(1, us), greaterThan(0));
    }
  });

  test(
    'compact gaps are capped and a long tail cannot slow short neighbours',
    () {
      bool connects(int previousSpan, int nextSpan, int gap) =>
          karaokeFollowerTimingConnected(
            timing(0, previousSpan),
            timing(previousSpan + gap, nextSpan),
            config,
            compactScript: true,
          );
      expect(connects(1000000, 1000000, 80000), isTrue);
      expect(connects(1000000, 1000000, 80001), isFalse);
      expect(connects(1000000, 100000, 35000), isTrue);
      expect(connects(1000000, 100000, 35001), isFalse);
      expect(connects(100000, 1000000, 35001), isFalse);
      expect(connects(100000, 100000, 900000), isFalse);
      expect(connects(1000, 1000, 2000), isTrue);
      expect(connects(1000, 1000, 2001), isFalse);
    },
  );

  test(
    'compact continuity can revert without weakening backwards-time guards',
    () {
      final baseline = KaraokeMotionConfig(
        maxCompactFollowerGap: Duration.zero,
      );
      expect(
        karaokeFollowerTimingConnected(
          timing(0, 190000),
          timing(220000),
          baseline,
          compactScript: true,
        ),
        isFalse,
      );
      expect(
        karaokeFollowerTimingConnected(
          timing(100000),
          timing(0),
          config,
          compactScript: true,
        ),
        isFalse,
      );
      expect(
        karaokeFollowerTimingConnected(
          timing(0),
          timing(0),
          config,
          compactScript: true,
        ),
        isTrue,
      );
      for (final duration in [
        const Duration(microseconds: -1),
        const Duration(milliseconds: 121),
      ]) {
        expect(
          () => KaraokeMotionConfig(maxCompactFollowerGap: duration),
          throwsRangeError,
        );
      }
    },
  );

  test('seven percent height retains direction and slow autonomous timing', () {
    expect(config.liftHeightFraction, .07);
    expect(config.liftDuration, const Duration(milliseconds: 760));
    final glyph = timing(0);
    final motion = KaraokeFollowerTimeline([
      KaraokeFollowerGlyph(timing: glyph, chain: 0),
    ], config);
    final output = Float64List(1);
    for (var time = -100000; time <= 2000000; time += 16667) {
      motion.writeOffsets(time, 40, output);
      expect(
        output[0],
        closeTo(
          karaokeLiftPixels(
            karaokeGlyphLiftAt(time, glyph, config),
            40,
            config,
          ),
          1e-12,
        ),
      );
    }
    expect(karaokeLiftPixels(0, 40, config), 0);
    expect(karaokeLiftPixels(1, 40, config), closeTo(-2.8, 1e-12));
    expect(motion.ownAt(0, 120000), lessThan(.15));
    expect(motion.ownAt(0, 760000), 1);
  });

  test(
    'only three next characters receive decreasing non-recursive traction',
    () {
      final motion = KaraokeFollowerTimeline([
        for (var i = 0; i < 8; i++)
          KaraokeFollowerGlyph(
            timing: timing(i == 0 ? 0 : 10000000 + i * 100000),
            chain: 0,
          ),
      ], config);
      for (var us = 0; us <= 1200000; us += 16667) {
        final leader = motion.ownAt(0, us);
        for (var hop = 1; hop <= 3; hop++) {
          expect(motion.ownAt(hop, us), 0);
          expect(
            motion.liftAt(hop, us),
            closeTo(leader * config.followerWeights[hop - 1], 1e-12),
          );
        }
        for (var i = 4; i < 8; i++) {
          expect(motion.liftAt(i, us), 0);
        }
      }
    },
  );

  test('remaining-travel blend is smooth, bounded and retains completion', () {
    final glyphs = [
      for (var i = 0; i < 4; i++)
        KaraokeFollowerGlyph(timing: timing(i * 80000), chain: 0),
    ];
    final motion = KaraokeFollowerTimeline(glyphs, config);
    final output = Float64List(4);
    for (var us = -100000; us <= 1600000; us += 8333) {
      motion.writeOffsets(us, 40, output);
      for (var i = 0; i < 4; i++) {
        var remaining = 1.0;
        for (var hop = 1; hop <= 3 && i - hop >= 0; hop++) {
          remaining *=
              1 - config.followerWeights[hop - 1] * motion.ownAt(i - hop, us);
        }
        final own = motion.ownAt(i, us);
        final expected = 1 - (1 - own) * remaining;
        expect(motion.liftAt(i, us), expected);
        expect(expected, inInclusiveRange(own - 1e-12, 1));
        expect(output[i], closeTo(-2.8 * expected, 1e-12));
      }
    }
    expect(output, everyElement(closeTo(-2.8, 1e-12)));
  });

  test('breaks disconnect pre-lift while preserving own time', () {
    final motion = KaraokeFollowerTimeline([
      KaraokeFollowerGlyph(timing: timing(0), chain: 0),
      KaraokeFollowerGlyph(timing: timing(3000000), chain: 1),
      KaraokeFollowerGlyph(timing: timing(3100000), chain: 1),
    ], config);
    for (var us = 0; us < 3000000; us += 8333) {
      expect(motion.liftAt(1, us), 0);
      expect(motion.liftAt(2, us), 0);
    }
    expect(motion.ownAt(1, 3500000), greaterThan(0));
  });

  test(
    '60/90/120 Hz at all rates have bounded displacement and velocity change',
    () {
      final motion = KaraokeFollowerTimeline([
        for (var i = 0; i < 12; i++)
          KaraokeFollowerGlyph(
            timing: timing(i * 80000, i.isEven ? 60000 : 1000000),
            chain: 0,
          ),
      ], config);
      for (final hz in [60, 90, 120]) {
        for (final rate in [.75, 1.0, 1.5, 2.0]) {
          final previous = Float64List(12),
              next = Float64List(12),
              velocities = Float64List(12);
          motion.writeOffsets(-100000, 40, previous);
          for (var frame = 1; frame <= hz * 3; frame++) {
            motion.writeOffsets(
              -100000 + (frame * 1000000 / hz * rate).round(),
              40,
              next,
            );
            for (var i = 0; i < 12; i++) {
              final displacement = previous[i] - next[i];
              final velocity = displacement * hz;
              expect(next[i], inInclusiveRange(-40 * .07, 0));
              expect(displacement, inInclusiveRange(-1e-12, .3 * .07 / .055));
              expect(
                (velocity - velocities[i]).abs(),
                lessThan(4 * .07 / .055),
              );
              previous[i] = next[i];
              velocities[i] = velocity;
            }
          }
        }
      }
    },
  );

  test('pause and forward/backward seek are independent of frame history', () {
    final motion = KaraokeFollowerTimeline([
      for (var i = 0; i < 6; i++)
        KaraokeFollowerGlyph(timing: timing(i * 180000), chain: 0),
    ], config);
    final played = Float64List(6), direct = Float64List(6);
    for (var us = 0; us < 1200000; us += 16667) {
      motion.writeOffsets(us, 40, played);
    }
    for (final us in [1200000, 450000, 3000000, -100000, 450000]) {
      motion.writeOffsets(us, 40, played);
      motion.writeOffsets(us, 40, direct);
      expect(played, direct);
      for (var frame = 0; frame < 120; frame++) {
        motion.writeOffsets(us, 40, direct);
        expect(direct, played);
      }
    }
  });

  test(
    'internal original-curve/no-recoil baseline has unchanged highlight',
    () {
      final baseline = KaraokeMotionConfig(
        followerWeights: const [0, 0, 0],
        curve: KaraokeLiftCurve.smoothTop,
        fastOvershootFraction: 0,
      );
      final glyphs = [
        for (var i = 0; i < 6; i++)
          KaraokeFollowerGlyph(timing: timing(i * 100000), chain: 0),
      ];
      final motion = KaraokeFollowerTimeline(glyphs, baseline);
      for (var us = 0; us < 1600000; us += 16667) {
        for (var i = 0; i < glyphs.length; i++) {
          expect(
            motion.liftAt(i, us),
            closeTo(karaokeGlyphLiftAt(us, glyphs[i].timing, baseline), 1e-12),
          );
          expect(
            karaokeGlyphFrame(us, glyphs[i].timing, config).highlightProgress,
            karaokeGlyphFrame(us, glyphs[i].timing, baseline).highlightProgress,
          );
        }
      }
    },
  );

  test(
    '354 entry/exit envelope fades the entire follower pose, without residuals',
    () {
      final motion = KaraokeFollowerTimeline([
        KaraokeFollowerGlyph(timing: timing(0), chain: 0),
        KaraokeFollowerGlyph(timing: timing(3000000), chain: 0),
      ], config);
      final full = Float64List(2), fading = Float64List(2);
      motion.writeOffsets(400000, 40, full);
      for (var ms = 0; ms <= 240; ms += 16) {
        final retention = karaokeExitRetention(
          Duration(milliseconds: ms),
          config,
        );
        motion.writeOffsets(400000, 40, fading, retention: retention);
        for (var i = 0; i < 2; i++) {
          expect(fading[i], closeTo(full[i] * retention, 1e-12));
        }
      }
      expect(fading, everyElement(0));
    },
  );

  test('traction configuration is validated and immutable', () {
    for (final weights in <List<double>>[
      [],
      [.24],
      [.24, .12, .05, .01],
      [.24, .3, .05],
      [double.nan, .12, .05],
      [.36, .12, .05],
      [.24, .12, -.05],
    ]) {
      expect(
        () => KaraokeMotionConfig(followerWeights: weights),
        throwsRangeError,
      );
    }
    final weights = [.24, .12, .05];
    final frozen = KaraokeMotionConfig(followerWeights: weights);
    weights[0] = 0;
    expect(frozen.followerWeights.first, .24);
    expect(() => frozen.followerWeights[0] = 0, throwsUnsupportedError);
  });
}
