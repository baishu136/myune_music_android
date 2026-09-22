import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/karaoke_motion.dart';

void main() {
  final config = KaraokeMotionConfig();
  const fast = KaraokeGlyphTiming(
    sourceTokenStartUs: 1000000,
    sourceTokenEndUs: 1100000,
    visualTokenStartUs: 990000,
    highlightStartUs: 1010000,
    highlightEndUs: 1060000,
    liftStartUs: 1000000,
  );

  test('motion settings reject out-of-range values', () {
    expect(
      () => KaraokeMotionConfig(liftHeightFraction: .12),
      throwsRangeError,
    );
    expect(
      () => KaraokeMotionConfig(liftDuration: const Duration(seconds: 2)),
      throwsRangeError,
    );
    expect(
      () => KaraokeMotionConfig(staggerFraction: double.nan),
      throwsRangeError,
    );
  });

  test('lift parameters cannot alter the existing highlight timeline', () {
    final taller = KaraokeMotionConfig(
      liftHeightFraction: .05,
      liftDuration: const Duration(milliseconds: 950),
    );
    for (final time in [990000, 1010000, 1035000, 1060000, 1200000]) {
      expect(
        karaokeGlyphFrame(time, fast, config).highlightProgress,
        karaokeGlyphFrame(time, fast, taller).highlightProgress,
      );
    }
    expect(fast.sourceTokenStartUs, 1000000);
    expect(fast.visualTokenStartUs, 990000);
  });

  test('a fast glyph does not reach the top at the next highlight onset', () {
    final atNext = karaokeGlyphFrame(1060000, fast, config);
    expect(atNext.highlightProgress, 1);
    expect(atNext.liftProgress, greaterThan(0));
    expect(atNext.liftProgress, lessThan(.1));
    expect(karaokeGlyphFrame(1760000, fast, config).liftProgress, 1);
  });

  test('the same media time has the same motion after playback or seek', () {
    final direct = karaokeGlyphFrame(1370000, fast, config);
    var played = karaokeGlyphFrame(0, fast, config);
    for (var time = 0; time <= 1370000; time += 10000) {
      played = karaokeGlyphFrame(time, fast, config);
    }
    played = karaokeGlyphFrame(1370000, fast, config);
    expect(played, direct);
    expect(
      karaokeGlyphFrame(900000, fast, config).liftProgress,
      0,
      reason: 'a backward seek must immediately show the earlier pose',
    );
    expect(
      karaokeGlyphFrame(2000000, fast, config).liftProgress,
      1,
      reason: 'a forward seek must immediately show the completed pose',
    );
  });

  test('adjacent fast Chinese glyphs overlap without a relay step', () {
    const second = KaraokeGlyphTiming(
      sourceTokenStartUs: 1060000,
      sourceTokenEndUs: 1120000,
      visualTokenStartUs: 1050000,
      highlightStartUs: 1060000,
      highlightEndUs: 1110000,
      liftStartUs: 1050000,
    );
    final firstAtSecondStart = karaokeGlyphFrame(1060000, fast, config);
    final secondAtSecondStart = karaokeGlyphFrame(1060000, second, config);
    expect(firstAtSecondStart.liftProgress, greaterThan(0));
    expect(firstAtSecondStart.liftProgress, lessThan(1));
    expect(secondAtSecondStart.liftProgress, greaterThan(0));
    expect(
      secondAtSecondStart.liftProgress,
      lessThan(firstAtSecondStart.liftProgress),
    );
  });

  test('60, 90 and 120 Hz sampling has bounded motion and no jump', () {
    for (final hz in [60, 90, 120]) {
      final stepUs = (1000000 / hz).round();
      var previous = karaokeGlyphFrame(fast.liftStartUs, fast, config);
      var previousVelocity = 0.0;
      for (
        var time = fast.liftStartUs + stepUs;
        time <= fast.liftStartUs + config.liftDuration.inMicroseconds;
        time += stepUs
      ) {
        final next = karaokeGlyphFrame(time, fast, config);
        final velocity = (next.liftProgress - previous.liftProgress) * hz;
        expect(next.liftProgress, greaterThanOrEqualTo(previous.liftProgress));
        expect(next.liftProgress - previous.liftProgress, lessThan(.05));
        expect((velocity - previousVelocity).abs(), lessThan(1.0));
        previous = next;
        previousVelocity = velocity;
      }
    }
  });

  test('line exit retains its frozen pose before easing to rest', () {
    expect(karaokeExitRetention(Duration.zero, config), 1);
    expect(
      karaokeExitRetention(const Duration(milliseconds: 120), config),
      inExclusiveRange(0, 1),
    );
    expect(karaokeExitRetention(config.exitDuration, config), 0);
  });

  test('slow word, sustained tail and pause do not move early', () {
    const longWord = KaraokeGlyphTiming(
      sourceTokenStartUs: 2000000,
      sourceTokenEndUs: 3300000,
      visualTokenStartUs: 1970000,
      highlightStartUs: 2500000,
      highlightEndUs: 2750000,
      liftStartUs: 2470000,
    );
    expect(karaokeGlyphFrame(2200000, longWord, config).liftProgress, 0);
    expect(
      karaokeGlyphFrame(2700000, longWord, config).highlightProgress,
      inExclusiveRange(0, 1),
    );
    expect(
      karaokeGlyphFrame(2700000, longWord, config).liftProgress,
      inExclusiveRange(0, 1),
    );
    const nextAfterPause = KaraokeGlyphTiming(
      sourceTokenStartUs: 4000000,
      sourceTokenEndUs: 4400000,
      visualTokenStartUs: 3970000,
      highlightStartUs: 3970000,
      highlightEndUs: 4400000,
      liftStartUs: 3940000,
    );
    expect(karaokeGlyphFrame(3300000, nextAfterPause, config).liftProgress, 0);
  });
}
