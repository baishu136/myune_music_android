import 'dart:math' as math;
import 'dart:typed_data';

/// Internal motion values. Durations are MEDIA time: at 2x a 760 ms lift
/// occupies 380 ms on the wall clock, matching the lyric time axis.
enum KaraokeLiftCurve { smoothTop, easeOutCubic }

class KaraokeMotionConfig {
  KaraokeMotionConfig({
    this.liftHeightFraction = .055,
    this.liftDuration = const Duration(milliseconds: 760),
    this.curve = KaraokeLiftCurve.smoothTop,
    this.staggerFraction = .15,
    this.maxPreStart = const Duration(milliseconds: 35),
    this.highlightFeatherFraction = .72,
    this.exitDuration = const Duration(milliseconds: 240),
    this.maxCompactFollowerGap = const Duration(milliseconds: 80),
    List<double> followerWeights = const [.24, .12, .05],
  }) : followerWeights = List<double>.unmodifiable(followerWeights) {
    if (maxCompactFollowerGap < Duration.zero ||
        maxCompactFollowerGap > const Duration(milliseconds: 120)) {
      throw RangeError.range(
        maxCompactFollowerGap.inMilliseconds,
        0,
        120,
        'maxCompactFollowerGap',
      );
    }
    // Light pre-lift only. Zero weights are an internal 354 comparison baseline.
    if (this.followerWeights.length != 3 ||
        this.followerWeights.any((w) => !w.isFinite || w < 0 || w > .35) ||
        this.followerWeights[1] > this.followerWeights[0] ||
        this.followerWeights[2] > this.followerWeights[1]) {
      throw RangeError('Require three decreasing follower weights in 0–.35');
    }
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
  final List<double> followerWeights;
  // Layout-only motion continuity across tiny timestamp gaps in Han/kana.
  // Capped again at 35% of the shorter neighbouring SOURCE token duration.
  // Zero restores the previous 2ms quantization tolerance. No highlight shift.
  final Duration maxCompactFollowerGap;
}

final karaokeDefaultMotion = KaraokeMotionConfig();

final _compactFollowerScript = RegExp(
  r'^[\u3040-\u30FF\u31F0-\u31FF\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\u{20000}-\u{3134F}\uFE00-\uFE0F\u{E0100}-\u{E01EF}]+$',
  unicode: true,
);

/// Called only while building layout metadata. Complete Han/kana graphemes
/// (including dakuten/variation selectors) or safely shaped runs remain intact.
bool karaokeHasCompactFollowerScript(String text) =>
    _compactFollowerScript.hasMatch(text);

/// Motion-only adjacency. Never fills or alters a real highlight time gap.
bool karaokeFollowerTimingConnected(
  KaraokeGlyphTiming previous,
  KaraokeGlyphTiming next,
  KaraokeMotionConfig config, {
  bool compactScript = false,
}) {
  if (next.liftStartUs < previous.liftStartUs) return false;
  if (previous.sourceTokenStartUs == next.sourceTokenStartUs &&
      previous.sourceTokenEndUs == next.sourceTokenEndUs) {
    return true;
  }
  if (next.sourceTokenStartUs < previous.sourceTokenStartUs) return false;
  var toleranceUs = 2000;
  if (compactScript) {
    final localSpan = math.min(
      math.max(1, previous.sourceTokenEndUs - previous.sourceTokenStartUs),
      math.max(1, next.sourceTokenEndUs - next.sourceTokenStartUs),
    );
    toleranceUs = math.max(
      toleranceUs,
      math.min(
        config.maxCompactFollowerGap.inMicroseconds,
        (localSpan * .35).round(),
      ),
    );
  }
  return next.sourceTokenStartUs - previous.sourceTokenEndUs <= toleranceUs;
}

/// One drawable unit's time mapping. Source boundaries are either supplied
/// token timestamps or synthetic estimates; the layout cache retains that
/// distinction explicitly. visualTokenStartUs includes existing compensation
/// for supplied timing only. Intra-token grapheme timing and all synthetic
/// timing are estimates, not measured vocal timestamps.
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
  return (
    highlightProgress: karaokeGlyphHighlightAt(mediaTimeUs, timing),
    liftProgress: karaokeGlyphLiftAt(mediaTimeUs, timing, config),
  );
}

double karaokeGlyphHighlightAt(int mediaTimeUs, KaraokeGlyphTiming timing) =>
    ((mediaTimeUs - timing.highlightStartUs) /
            math.max(1, timing.highlightEndUs - timing.highlightStartUs))
        .clamp(0.0, 1.0);

double karaokeGlyphLiftAt(
  int mediaTimeUs,
  KaraokeGlyphTiming timing,
  KaraokeMotionConfig config,
) {
  return _liftAt(mediaTimeUs, timing.liftStartUs, config);
}

double _liftAt(int mediaTimeUs, int startUs, KaraokeMotionConfig config) {
  final liftPhase =
      ((mediaTimeUs - startUs) / config.liftDuration.inMicroseconds).clamp(
        0.0,
        1.0,
      );
  final lift = switch (config.curve) {
    KaraokeLiftCurve.smoothTop => _smoothTop(liftPhase),
    KaraokeLiftCurve.easeOutCubic => 1 - math.pow(1 - liftPhase, 3).toDouble(),
  };
  return lift;
}

double karaokeExitRetentionFraction(double phase) => 1 - _smoothTop(phase);

double karaokeExitRetention(Duration elapsed, KaraokeMotionConfig config) =>
    1 - _smoothTop(elapsed.inMicroseconds / config.exitDuration.inMicroseconds);

double karaokeLiftPixels(
  double liftProgress,
  double lineHeight,
  KaraokeMotionConfig config,
) =>
    -liftProgress.clamp(0.0, 1.0) *
    (lineHeight * config.liftHeightFraction).clamp(1.2, 4.0);

/// Layout-only metadata. Shaped runs stay intact; cached adjacency respects
/// whitespace, bounded timing gaps, physical wraps and text direction.
class KaraokeFollowerGlyph {
  const KaraokeFollowerGlyph({required this.timing, required this.chain});
  final KaraokeGlyphTiming timing;
  final int chain;
}

/// 354's slow own curve plus bounded, non-recursive three-neighbour traction.
/// No frame integration: seeking to a time equals playing to that time.
class KaraokeFollowerTimeline {
  KaraokeFollowerTimeline(List<KaraokeFollowerGlyph> glyphs, this.config)
    : _starts = Int64List(glyphs.length),
      _sources = Int32List(glyphs.length * 3)
        ..fillRange(0, glyphs.length * 3, -1),
      _own = Float64List(glyphs.length) {
    var chainStart = 0;
    for (var i = 0; i < glyphs.length; i++) {
      _starts[i] = glyphs[i].timing.liftStartUs;
      if (i == 0 || glyphs[i].chain != glyphs[i - 1].chain) chainStart = i;
      for (var hop = 0; hop < 3 && i - hop - 1 >= chainStart; hop++) {
        _sources[i * 3 + hop] = i - hop - 1;
      }
    }
  }

  final KaraokeMotionConfig config;
  final Int64List _starts;
  final Int32List _sources;
  final Float64List _own;
  int get length => _starts.length;

  double ownAt(int index, int mediaUs) =>
      _liftAt(mediaUs, _starts[index], config);

  double liftAt(int index, int mediaUs) {
    final own = ownAt(index, mediaUs);
    var remaining = 1.0;
    for (var hop = 0; hop < 3; hop++) {
      final source = _sources[index * 3 + hop];
      if (source < 0) break;
      remaining *= 1 - config.followerWeights[hop] * ownAt(source, mediaUs);
    }
    // Smooth remaining-travel blend instead of max's velocity-changing switch.
    // Each follower reads ONLY own motion, never another follower's result.
    return (1 - (1 - own) * remaining).clamp(0.0, 1.0);
  }

  void writeOffsets(
    int mediaUs,
    double lineHeight,
    Float64List output, {
    double retention = 1,
  }) {
    assert(output.length == length);
    final envelope = retention.clamp(0.0, 1.0);
    if (envelope == 0) {
      output.fillRange(0, output.length, 0);
      return;
    }
    for (var i = 0; i < length; i++) {
      _own[i] = ownAt(i, mediaUs);
    }
    final maximum = karaokeLiftPixels(1, lineHeight, config) * envelope;
    for (var i = 0; i < length; i++) {
      var remaining = 1.0;
      for (var hop = 0; hop < 3; hop++) {
        final source = _sources[i * 3 + hop];
        if (source < 0) break;
        remaining *= 1 - config.followerWeights[hop] * _own[source];
      }
      output[i] = maximum * (1 - (1 - _own[i]) * remaining).clamp(0.0, 1.0);
    }
  }
}
