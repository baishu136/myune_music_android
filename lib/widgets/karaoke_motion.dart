import 'dart:math' as math;

/// Internal motion values. Durations are MEDIA time: at 2x a 760 ms lift
/// occupies 380 ms on the wall clock, matching the lyric time axis.
enum KaraokeLiftCurve { smoothTop, easeOutCubic }

class KaraokeMotionConfig {
  KaraokeMotionConfig({
    this.liftHeightFraction = .045,
    this.liftDuration = const Duration(milliseconds: 760),
    this.curve = KaraokeLiftCurve.smoothTop,
    this.staggerFraction = .15,
    this.maxPreStart = const Duration(milliseconds: 35),
    this.highlightFeatherFraction = .72,
    this.exitDuration = const Duration(milliseconds: 240),
  }) {
    if (!liftHeightFraction.isFinite ||
        liftHeightFraction < .02 ||
        liftHeightFraction > .08) {
      throw RangeError.value(
        liftHeightFraction,
        'liftHeightFraction',
        '.02–.08',
      );
    }
    if (liftDuration < const Duration(milliseconds: 400) ||
        liftDuration > const Duration(milliseconds: 1200)) {
      throw RangeError.range(
        liftDuration.inMilliseconds,
        400,
        1200,
        'liftDuration',
      );
    }
    if (!staggerFraction.isFinite ||
        staggerFraction < 0 ||
        staggerFraction > .35) {
      throw RangeError.value(staggerFraction, 'staggerFraction', '0–.35');
    }
    if (maxPreStart < Duration.zero ||
        maxPreStart > const Duration(milliseconds: 80)) {
      throw RangeError.range(maxPreStart.inMilliseconds, 0, 80, 'maxPreStart');
    }
    if (!highlightFeatherFraction.isFinite ||
        highlightFeatherFraction < .3 ||
        highlightFeatherFraction > 1.2) {
      throw RangeError.value(
        highlightFeatherFraction,
        'highlightFeatherFraction',
        '.3–1.2',
      );
    }
    if (exitDuration < const Duration(milliseconds: 100) ||
        exitDuration > const Duration(milliseconds: 600)) {
      throw RangeError.range(
        exitDuration.inMilliseconds,
        100,
        600,
        'exitDuration',
      );
    }
  }

  final double liftHeightFraction;
  final Duration liftDuration;
  final KaraokeLiftCurve curve;
  final double staggerFraction;
  final Duration maxPreStart;
  final double highlightFeatherFraction;
  final Duration exitDuration;
}

final karaokeDefaultMotion = KaraokeMotionConfig();

/// One drawable grapheme's time mapping. Source token boundaries are real
/// lyric timestamps; visualTokenStartUs includes the existing small visual
/// compensation. Highlight and lift starts inside an untimed token are
/// estimates derived from its grapheme count, not source timestamps.
class KaraokeGlyphTiming {
  const KaraokeGlyphTiming({
    required this.sourceTokenStartUs,
    required this.sourceTokenEndUs,
    required this.visualTokenStartUs,
    required this.highlightStartUs,
    required this.highlightEndUs,
    required this.liftStartUs,
  });

  factory KaraokeGlyphTiming.fromToken({
    required int sourceTokenStartUs,
    required int sourceTokenEndUs,
    required int visualTokenStartUs,
    required double highlightStartProgress,
    required double highlightWindowProgress,
    required double estimatedCadenceUs,
    KaraokeMotionConfig? config,
  }) {
    config ??= karaokeDefaultMotion;
    final span = math.max(1, sourceTokenEndUs - visualTokenStartUs);
    final start =
        visualTokenStartUs +
        (span * highlightStartProgress.clamp(0.0, 1.0)).round();
    final end =
        visualTokenStartUs +
        (span *
                (highlightStartProgress + highlightWindowProgress).clamp(
                  0.0,
                  1.0,
                ))
            .round();
    final preStart = math.min(
      config.maxPreStart.inMicroseconds,
      math.max(0, estimatedCadenceUs * config.staggerFraction).round(),
    );
    return KaraokeGlyphTiming(
      sourceTokenStartUs: sourceTokenStartUs,
      sourceTokenEndUs: sourceTokenEndUs,
      visualTokenStartUs: visualTokenStartUs,
      highlightStartUs: start,
      highlightEndUs: math.max(start + 1, end),
      liftStartUs: start - preStart,
    );
  }

  final int sourceTokenStartUs;
  final int sourceTokenEndUs;
  final int visualTokenStartUs;
  final int highlightStartUs;
  final int highlightEndUs;
  final int liftStartUs;
}

typedef KaraokeGlyphFrame = ({double highlightProgress, double liftProgress});

double _smoothTop(double progress) {
  final t = progress.clamp(0.0, 1.0);
  final smooth = t * t * t * (t * (t * 6 - 15) + 10);
  return smooth + .15 * smooth * (1 - smooth);
}

KaraokeGlyphFrame karaokeGlyphFrame(
  int mediaTimeUs,
  KaraokeGlyphTiming timing,
  KaraokeMotionConfig config,
) {
  final highlight =
      ((mediaTimeUs - timing.highlightStartUs) /
              math.max(1, timing.highlightEndUs - timing.highlightStartUs))
          .clamp(0.0, 1.0);
  final liftPhase =
      ((mediaTimeUs - timing.liftStartUs) / config.liftDuration.inMicroseconds)
          .clamp(0.0, 1.0);
  final lift = switch (config.curve) {
    KaraokeLiftCurve.smoothTop => _smoothTop(liftPhase),
    KaraokeLiftCurve.easeOutCubic => 1 - math.pow(1 - liftPhase, 3).toDouble(),
  };
  return (highlightProgress: highlight, liftProgress: lift);
}

double karaokeExitRetention(Duration elapsed, KaraokeMotionConfig config) =>
    1 - _smoothTop(elapsed.inMicroseconds / config.exitDuration.inMicroseconds);

double karaokeLiftPixels(
  double liftProgress,
  double lineHeight,
  KaraokeMotionConfig config,
) =>
    -liftProgress.clamp(0.0, 1.0) *
    (lineHeight * config.liftHeightFraction).clamp(1.2, 4.0);
