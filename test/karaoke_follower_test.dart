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
  final config = KaraokeMotionConfig();
  test('complete Han and kana graphemes use compact-script continuity', () {
    for (final text in ['中文', 'かなカナ', 'か\u3099', '\u{20000}\u{E0100}']) {
      expect(karaokeHasCompactFollowerScript(text), isTrue, reason: text);
    }
    for (final text in ['', '中文 歌', 'Follow', '中a', '한글', '👨‍👩‍👧']) {
      expect(karaokeHasCompactFollowerScript(text), isFalse, reason: text);
    }
  });

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

  test('354 height, direction and slow autonomous timing are unchanged', () {
    expect(config.liftHeightFraction, .055);
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
    expect(karaokeLiftPixels(1, 40, config), -2.2);
    expect(motion.ownAt(0, 120000), lessThan(.1));
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
        expect(output[i], closeTo(-2.2 * expected, 1e-12));
      }
    }
    expect(output, everyElement(-2.2));
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
              expect(next[i], inInclusiveRange(-2.2, 0));
              expect(displacement, inInclusiveRange(-1e-12, .3));
              expect((velocity - velocities[i]).abs(), lessThan(4));
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

  test('zero traction is an exact 354 baseline with unchanged highlight', () {
    final baseline = KaraokeMotionConfig(followerWeights: const [0, 0, 0]);
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
  });

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
