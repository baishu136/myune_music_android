import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:characters/characters.dart' as characters;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable, kDebugMode;
import 'package:flutter/rendering.dart'
    show RenderComparison, ScrollCacheExtent;
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../page/playlist/playlist_models.dart';
import '../page/setting/settings_provider.dart';
import '../services/interaction_performance_controller.dart';
import 'interlude_animation_widget.dart';
import 'karaoke_motion.dart';
import 'lyric_seek_guide.dart';
import 'lyric_scroll_motion.dart';

part 'karaoke_media_clock.dart';

const int mobileLyricsTopEdgeAlpha = 0x00;
const int mobileLyricsTopFadeSoftAlpha = 0x24;
const int mobileLyricsTopFadeMidAlpha = 0x68;
const int mobileLyricsTopFadeNearAlpha = 0xC0;
const int mobileLyricsBottomFadeNearAlpha = 0xC0;
const int mobileLyricsBottomFadeMidAlpha = 0x68;
const int mobileLyricsBottomFadeSoftAlpha = 0x24;
const Color mobileLyricsBrowseMaskColor = Color(0x4DFFFFFF);
const Duration mobileLyricsBrowseMaskRevealDelay = Duration(milliseconds: 300);
const Duration mobileLyricsBrowseMaskRevealDuration = Duration(
  milliseconds: 200,
);
const Color mobileLyricsBrowseGuideColor = Color(0xB3FFFFFF);
const Duration mobileLyricsFocusTransitionDuration = Duration(
  milliseconds: 520,
);
const Curve mobileLyricsFocusTransitionCurve = Cubic(.2, .72, .24, 1);
const Duration mobileLyricsDefaultScrollTransitionDuration = Duration(
  milliseconds: 620,
);
const Duration mobileLyricsKaraokeLineShiftDuration =
    mobileLyricsDefaultScrollTransitionDuration;
const double mobileLyricsDefaultScrollFrequency = 8.8;
const double mobileLyricsRenderOverflow = 180;
const double mobileLyricsActiveScale = 1.1;

double mobileLyricsLargeFontProgress(double fontSize) =>
    ((fontSize - 20) / 16).clamp(0.0, 1.0).toDouble();

double mobileLyricsScrollFrequencyForFontSize(double fontSize) => ui.lerpDouble(
  mobileLyricsDefaultScrollFrequency,
  7.2,
  mobileLyricsLargeFontProgress(fontSize),
)!;

double mobileLyricScaleSafeExtent(double contentExtent) =>
    contentExtent * mobileLyricsActiveScale;

double mobileLyricScaleSafeContentWidth(double availableWidth) =>
    availableWidth / mobileLyricsActiveScale;

double mobileLyricsHorizontalInset(TextAlign alignment) => switch (alignment) {
  TextAlign.left || TextAlign.right || TextAlign.start || TextAlign.end => 4,
  _ => 24,
};

double mobileLyricsKaraokeLineShift(int relativeDistance) =>
    relativeDistance < 0
    ? -.16
    : relativeDistance > 0
    ? .22
    : 0;

bool karaokePlaybackPositionDiscontinuity({
  required Duration previousSource,
  required Duration source,
  required Duration elapsedSinceSource,
  double playbackRate = 1,
}) {
  final sourceDelta = source.inMicroseconds - previousSource.inMicroseconds;
  final expectedDelta =
      elapsedSinceSource.inMicroseconds.clamp(0, 5000000) * playbackRate;
  final drift = sourceDelta - expectedDelta;
  return drift.abs() > 160000 || sourceDelta < -20000;
}

String formatMobileLyricsBrowseTime(Duration timestamp) {
  final totalSeconds = timestamp.inSeconds.clamp(0, 359999);
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds ~/ 60) % 60;
  final seconds = totalSeconds % 60;
  final secondLabel = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$secondLabel';
  }
  return '${timestamp.inMinutes.clamp(0, 5999)}:$secondLabel';
}

List<double> mobileLyricsEdgeFadeStops(double viewportHeight) {
  final height = viewportHeight <= 0 ? 1.0 : viewportHeight;
  final topBand = (height * .26)
      .clamp(144.0, 200.0)
      .clamp(0.0, height * .42)
      .toDouble();
  final bottomBand = (height * .30)
      .clamp(160.0, 224.0)
      .clamp(0.0, height * .44)
      .toDouble();
  return [
    0,
    topBand * .18 / height,
    topBand * .44 / height,
    topBand * .72 / height,
    topBand / height,
    1 - bottomBand / height,
    1 - bottomBand * .72 / height,
    1 - bottomBand * .44 / height,
    1 - bottomBand * .18 / height,
    1 - bottomBand * .08 / height,
    1,
  ];
}

class MobileLyricsListController {
  Object? _owner;
  VoidCallback? _recenterCallback;
  ValueChanged<Duration>? _settleCallback;
  bool _recenterPending = false;
  Duration? _settlePending;

  void _attach(
    Object owner,
    VoidCallback recenterCallback,
    ValueChanged<Duration> settleCallback,
  ) {
    _owner = owner;
    _recenterCallback = recenterCallback;
    _settleCallback = settleCallback;
    if (_recenterPending) {
      _recenterPending = false;
      recenterCallback();
    }
    final pendingTarget = _settlePending;
    if (pendingTarget != null) {
      _settlePending = null;
      settleCallback(pendingTarget);
    }
  }

  void _detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _recenterCallback = null;
    _settleCallback = null;
  }

  void recenter() {
    final callback = _recenterCallback;
    if (callback == null) {
      _recenterPending = true;
      return;
    }
    callback();
  }

  void settleOn(Duration target) {
    final callback = _settleCallback;
    if (callback == null) {
      _settlePending = target;
      return;
    }
    callback(target);
  }

  bool selectBrowseTargetAtGlobalPosition(Offset position) {
    final owner = _owner;
    if (owner is _MobileLyricsListState) {
      return owner._selectBrowseTargetAtGlobalPosition(position);
    }
    return false;
  }

  bool selectBrowseTarget() {
    final owner = _owner;
    return owner is _MobileLyricsListState && owner._selectBrowseTarget();
  }

  bool isBrowseTargetAtGlobalPosition(Offset position) {
    final owner = _owner;
    return owner is _MobileLyricsListState &&
        owner._isBrowseTargetAtGlobalPosition(position);
  }
}

class _LyricElasticPulse {
  const _LyricElasticPulse({
    this.id = 0,
    this.displacement = 0,
    this.anchorIndex = 0,
    this.lineDurationSeconds = 1.5,
  });

  final int id;
  final double displacement;
  final int anchorIndex;
  final double lineDurationSeconds;
}

double clampLyricElasticDisplacement(
  double displacement,
  double viewportHeight, {
  double fontSize = 20,
}) {
  final largeFont = mobileLyricsLargeFontProgress(fontSize);
  final viewportShare = ui.lerpDouble(.36, .31, largeFont)!;
  final limit = (viewportHeight * viewportShare)
      .clamp(72.0, ui.lerpDouble(156, 140, largeFont)!)
      .toDouble();
  return displacement.clamp(-limit, limit).toDouble();
}

double lyricSeekVisibleTravel(double viewportHeight, {double fontSize = 20}) {
  final largeFont = mobileLyricsLargeFontProgress(fontSize);
  final viewportShare = ui.lerpDouble(.42, .32, largeFont)!;
  return (viewportHeight * viewportShare)
      .clamp(72.0, ui.lerpDouble(180, 152, largeFont)!)
      .toDouble();
}

double boundedLyricAnimationStart(
  double current,
  double target,
  double viewportHeight, {
  double fontSize = 20,
}) {
  final displacement = target - current;
  final visibleTravel = lyricSeekVisibleTravel(
    viewportHeight,
    fontSize: fontSize,
  );
  if (displacement.abs() <= visibleTravel) return current;
  return target - displacement.sign * visibleTravel;
}

double mobileLyricBlurSigmaForDistance(int distance) => switch (distance) {
  <= 0 => 0,
  1 => .9,
  2 => 1.65,
  3 => 2.35,
  4 => 3,
  _ => 3.4,
};

double karaokeTokenProgress(LyricToken token, Duration position) {
  final duration = token.end.inMicroseconds - token.start.inMicroseconds;
  if (duration <= 0) return position >= token.start ? 1 : 0;
  return ((position.inMicroseconds - token.start.inMicroseconds) / duration)
      .clamp(0.0, 1.0);
}

double karaokeVisualTokenProgress(LyricToken token, Duration position) {
  return karaokeRawVisualTokenProgress(token, position).clamp(0.0, 1.0);
}

double karaokeRawVisualTokenProgress(LyricToken token, Duration position) {
  final visualStart = karaokeVisualTokenStart(token);
  final visualDuration = token.end.inMicroseconds - visualStart.inMicroseconds;
  if (visualDuration <= 0) return position >= token.start ? 1 : 0;
  return (position.inMicroseconds - visualStart.inMicroseconds) /
      visualDuration;
}

Duration karaokeVisualTokenStart(LyricToken token) {
  const minimumVisualDuration = Duration(milliseconds: 520);
  const standardLeadIn = Duration(milliseconds: 45);
  const maximumEdgeExtension = Duration(milliseconds: 60);
  final sourceDuration = token.end - token.start;
  if (sourceDuration <= Duration.zero) return token.start;
  final missing = minimumVisualDuration - sourceDuration;
  // Keep a tiny lead-in for every token so adjacent words hand the motion to
  // one another instead of stopping at the whitespace boundary. Short tokens
  // may use the existing, slightly wider window; completion never moves past
  // the source timestamp.
  final desiredLeadIn = missing > Duration.zero
      ? math.max(standardLeadIn.inMicroseconds, missing.inMicroseconds ~/ 2)
      : standardLeadIn.inMicroseconds;
  final edgeExtension = Duration(
    microseconds: math.min(
      maximumEdgeExtension.inMicroseconds,
      math.min(desiredLeadIn, sourceDuration.inMicroseconds ~/ 4),
    ),
  );
  return token.start - edgeExtension;
}

double karaokePositionBlend(Duration frameDelta) {
  final seconds = frameDelta.inMicroseconds / Duration.microsecondsPerSecond;
  return (1 - math.exp(-seconds / .045)).clamp(0.0, 1.0);
}

double karaokeHighlightFeather(double glyphWidth) =>
    (glyphWidth * .16).clamp(4.5, 12.0);

/// Advance normally; ease only drift, never the passage of playback time.
Duration karaokeAdvanceVisualClock(
  Duration current,
  Duration target,
  Duration frameDelta, {
  double playbackRate = 1,
}) {
  final step = math.max(0, frameDelta.inMicroseconds * playbackRate).round();
  final predicted = current.inMicroseconds + step;
  final correction =
      ((target.inMicroseconds - predicted) * karaokePositionBlend(frameDelta))
          .clamp(-step * .08, step * .08)
          .round();
  return Duration(microseconds: predicted + correction);
}

Duration karaokeVisualClockTarget(
  Duration anchorPosition,
  Duration elapsed,
  Duration anchorElapsed,
  double playbackRate,
) =>
    anchorPosition +
    Duration(
      microseconds: ((elapsed - anchorElapsed).inMicroseconds * playbackRate)
          .round(),
    );

({Offset start, Offset end}) karaokeHighlightGradient(
  Rect glyphBounds,
  TextDirection direction,
  double progress,
  double feather,
) {
  final bounded = progress.clamp(0.0, 1.0);
  final front = direction == TextDirection.rtl
      ? glyphBounds.right - glyphBounds.width * bounded
      : glyphBounds.left + glyphBounds.width * bounded;
  return direction == TextDirection.rtl
      ? (
          start: Offset(front, glyphBounds.center.dy),
          end: Offset(front - feather, glyphBounds.center.dy),
        )
      : (
          start: Offset(front, glyphBounds.center.dy),
          end: Offset(front + feather, glyphBounds.center.dy),
        );
}

Rect karaokePlayedClipRect(
  Rect glyphBounds,
  TextDirection direction,
  double progress,
) {
  final bounded = progress.clamp(0.0, 1.0);
  final front = direction == TextDirection.rtl
      ? glyphBounds.right - glyphBounds.width * bounded
      : glyphBounds.left + glyphBounds.width * bounded;
  return direction == TextDirection.rtl
      ? Rect.fromLTRB(
          front,
          glyphBounds.top,
          glyphBounds.right,
          glyphBounds.bottom,
        )
      : Rect.fromLTRB(
          glyphBounds.left,
          glyphBounds.top,
          front,
          glyphBounds.bottom,
        );
}

double karaokeHighlightLift(double progress, double glyphHeight) {
  final bounded = progress.clamp(0.0, 1.0);
  final amplitude = (glyphHeight * .09).clamp(1.8, 6.0);
  // The eased curve has zero velocity at both ends and an extra top buffer.
  final eased = karaokeLiftCurve(bounded);
  return -eased * amplitude;
}

double karaokeLiftCurve(double progress) {
  final bounded = progress.clamp(0.0, 1.0);
  final eased =
      bounded * bounded * bounded * (bounded * (bounded * 6 - 15) + 10);
  // Keep zero velocity at both endpoints, with a little more braking as the
  // glyph approaches the top instead of stopping abruptly at full height.
  return eased + .2 * eased * (1 - eased);
}

const karaokeFollowerLiftHeights = <double>[.20, .15, .10, .05, .02];

double karaokeLineGlyphCadenceUs(Iterable<LyricToken> tokens, int glyphCount) {
  if (glyphCount <= 0) return 80000;
  final activeUs = tokens.fold<int>(0, (sum, token) {
    final durationUs = token.end.inMicroseconds - token.start.inMicroseconds;
    return sum + math.max(0, durationUs);
  });
  if (activeUs <= 0) return 80000;
  return (activeUs / glyphCount).clamp(40000.0, 260000.0);
}

/// Token boundaries are timed by the lyric source. Within an untimed token,
/// each grapheme gets an estimated share of that token's duration.
List<double> karaokeLocalGlyphCadencesUs(
  List<LyricToken> tokens,
  List<int> glyphCounts,
) {
  assert(tokens.length == glyphCounts.length);
  final raw = <double>[];
  for (var tokenIndex = 0; tokenIndex < tokens.length; tokenIndex++) {
    final count = glyphCounts[tokenIndex];
    if (count <= 0) continue;
    final token = tokens[tokenIndex];
    var cadence = (token.end - token.start).inMicroseconds / count;
    // A sustained final syllable is not evidence that the preceding rapid
    // characters were sung slowly. Bound only the tail against nearby pace.
    if (tokenIndex == tokens.length - 1 && raw.isNotEmpty && count <= 2) {
      cadence = math.min(cadence, raw.last * 2.5);
    }
    raw.addAll(List<double>.filled(count, cadence.clamp(40000.0, 260000.0)));
  }
  return List<double>.generate(raw.length, (index) {
    final before = raw[math.max(0, index - 1)];
    final after = raw[math.min(raw.length - 1, index + 1)];
    return (before * .2 + raw[index] * .6 + after * .2).clamp(
      40000.0,
      260000.0,
    );
  });
}

double karaokeFollowerLiftFactor(
  double elapsedUs,
  int distance,
  double lineCadenceUs,
) {
  if (distance <= 0 ||
      distance > karaokeFollowerLiftHeights.length ||
      lineCadenceUs <= 0) {
    return 0;
  }
  final delayUs = lineCadenceUs * .22 * distance;
  final riseUs = lineCadenceUs * 1.05;
  final gate = karaokeLiftCurve((elapsedUs - delayUs) / riseUs);
  return karaokeFollowerLiftHeights[distance - 1] * gate;
}

List<double> karaokeChainedLiftFactors(
  List<double> ownFactors, {
  required List<double> sourceStartTimesUs,
  required double positionUs,
  required double lineCadenceUs,
  List<double>? sourceCadencesUs,
  Set<int> breakBefore = const {},
  List<bool>? breakBeforeFlags,
  List<double>? resultBuffer,
}) {
  assert(ownFactors.length == sourceStartTimesUs.length);
  assert(
    sourceCadencesUs == null || sourceCadencesUs.length == ownFactors.length,
  );
  final result = resultBuffer ?? List<double>.filled(ownFactors.length, 0);
  assert(result.length == ownFactors.length);
  var chainStart = 0;
  for (var index = 0; index < ownFactors.length; index++) {
    if (breakBeforeFlags?[index] == true || breakBefore.contains(index)) {
      chainStart = index;
    }
    var follower = 0.0;
    for (
      var distance = 1;
      distance <= karaokeFollowerLiftHeights.length &&
          index - distance >= chainStart;
      distance++
    ) {
      final sourceIndex = index - distance;
      if (ownFactors[sourceIndex] <= 0) continue;
      follower = math.max(
        follower,
        karaokeFollowerLiftFactor(
          positionUs - sourceStartTimesUs[sourceIndex],
          distance,
          sourceCadencesUs?[sourceIndex] ?? lineCadenceUs,
        ),
      );
    }
    final own = ownFactors[index].clamp(0.0, 1.0);
    result[index] = follower + own * (1 - follower);
  }
  return result;
}

double karaokeGlyphLiftFactor(
  double tokenProgress, {
  required int glyphIndex,
  required int glyphCount,
}) {
  final index = glyphIndex.clamp(0, math.max(0, glyphCount - 1)).toInt();
  final ownFactors = List<double>.generate(
    index + 1,
    (currentIndex) => karaokeLiftCurve(
      karaokeGlyphLiftProgress(
        tokenProgress,
        glyphIndex: currentIndex,
        glyphCount: glyphCount,
      ),
    ),
  );
  const syntheticDurationUs = 1000000.0;
  final sourceStarts = List<double>.generate(
    index + 1,
    (currentIndex) =>
        karaokeGlyphLiftStartProgress(currentIndex, glyphCount, 0) *
        syntheticDurationUs,
  );
  return karaokeChainedLiftFactors(
    ownFactors,
    sourceStartTimesUs: sourceStarts,
    positionUs: tokenProgress * syntheticDurationUs,
    lineCadenceUs: syntheticDurationUs / math.max(1, glyphCount),
  ).last;
}

bool karaokeTokensShareLiftChain(LyricToken previous, LyricToken next) {
  const maximumGap = Duration(milliseconds: 220);
  const toleratedReorder = Duration(milliseconds: 50);
  return next.start + toleratedReorder >= previous.start &&
      next.start - previous.end <= maximumGap;
}

double karaokeGlyphLiftProgress(
  double tokenProgress, {
  required int glyphIndex,
  required int glyphCount,
  double? nextTokenStartProgress,
  double leadInProgress = 0,
}) {
  final index = glyphIndex.clamp(0, math.max(0, glyphCount - 1)).toInt();
  final start = karaokeGlyphLiftStartProgress(
    index,
    glyphCount,
    leadInProgress,
  );
  final end = index + 1 < glyphCount
      ? karaokeGlyphHighlightStart(index + 1, glyphCount)
      : nextTokenStartProgress != null && nextTokenStartProgress > start
      ? nextTokenStartProgress.clamp(start, 1.0)
      : 1.0;
  if (end <= start) {
    return karaokeGlyphProgress(
      tokenProgress,
      glyphIndex: index,
      glyphCount: glyphCount,
    );
  }
  return ((tokenProgress - start) / (end - start)).clamp(0.0, 1.0);
}

double karaokeGlyphLiftStartProgress(
  int glyphIndex,
  int glyphCount,
  double leadInProgress,
) => glyphIndex > 0
    ? karaokeGlyphHighlightStart(glyphIndex - 1, glyphCount)
    : -leadInProgress.clamp(0.0, 1.0);

double karaokeGlyphLiftLeadInProgress(LyricToken token, int glyphCount) {
  final visualDuration =
      token.end.inMicroseconds - karaokeVisualTokenStart(token).inMicroseconds;
  if (visualDuration <= 0) return 0;
  final firstStep = glyphCount > 1
      ? karaokeGlyphHighlightStart(1, glyphCount)
      : 1.0;
  // Start the first glyph at most 80 ms before its highlight, and never more
  // than one character interval or 35% of a very short token early.
  return math.min(firstStep, math.min(.35, 80000 / visualDuration));
}

double karaokeGlyphHighlightStart(int glyphIndex, int glyphCount) {
  if (glyphCount <= 1) return 0;
  final travelWindow = math.min(.48, 1.8 / (glyphCount + .8));
  final index = glyphIndex.clamp(0, glyphCount - 1);
  return (1 - travelWindow) * index / (glyphCount - 1);
}

double? karaokeNextTokenStartProgress(LyricToken current, LyricToken next) {
  if (!karaokeTokensShareLiftChain(current, next)) return null;
  final visualStart = karaokeVisualTokenStart(current);
  final duration = current.end.inMicroseconds - visualStart.inMicroseconds;
  if (duration <= 0) return null;
  final nextStart = karaokeVisualTokenStart(next);
  return ((nextStart.inMicroseconds - visualStart.inMicroseconds) / duration)
      .clamp(0.0, 1.0);
}

double karaokeGlyphProgress(
  double tokenProgress, {
  required int glyphIndex,
  required int glyphCount,
}) {
  final bounded = tokenProgress.clamp(0.0, 1.0);
  if (bounded <= 0) return 0;
  if (bounded >= 1) return 1;
  if (glyphCount <= 1) return bounded;
  // A fixed wide window makes most letters in a long word animate together,
  // which reads as word-level highlighting. Scale the window with grapheme
  // count so only about one or two neighbouring glyphs overlap at once.
  final travelWindow = math.min(.48, 1.8 / (glyphCount + .8));
  final start = karaokeGlyphHighlightStart(glyphIndex, glyphCount);
  return ((bounded - start) / travelWindow).clamp(0.0, 1.0);
}

double karaokeContinuousHighlightProgress(
  double tokenProgress, {
  required double precedingExtent,
  required double glyphExtent,
  required double totalExtent,
}) {
  if (glyphExtent <= 0 || totalExtent <= 0) return 0;
  final front = tokenProgress.clamp(0.0, 1.0) * totalExtent;
  return ((front - precedingExtent) / glyphExtent).clamp(0.0, 1.0);
}

double karaokeContinuousGradientFeather(double lineHeight) =>
    (lineHeight * 1.55).clamp(32.0, 88.0);

({Offset start, Offset end}) karaokeContinuousGradient(
  Rect tokenBounds,
  TextDirection direction,
  double progress,
  double feather,
) {
  final bounded = progress.clamp(0.0, 1.0);
  final halfFeather = feather / 2;
  final front = direction == TextDirection.rtl
      ? tokenBounds.right +
            halfFeather -
            (tokenBounds.width + feather) * bounded
      : tokenBounds.left -
            halfFeather +
            (tokenBounds.width + feather) * bounded;
  return direction == TextDirection.rtl
      ? (
          start: Offset(front + halfFeather, tokenBounds.center.dy),
          end: Offset(front - halfFeather, tokenBounds.center.dy),
        )
      : (
          start: Offset(front - halfFeather, tokenBounds.center.dy),
          end: Offset(front + halfFeather, tokenBounds.center.dy),
        );
}

({Offset start, Offset end}) karaokeGlyphHighlightGradient(
  Rect glyphBounds,
  TextDirection direction,
  double progress, {
  double featherFraction = .72,
}) {
  final bounded = progress.clamp(0.0, 1.0);
  final feather = (glyphBounds.width * featherFraction).clamp(6.0, 28.0);
  final halfFeather = feather / 2;
  final front = direction == TextDirection.rtl
      ? glyphBounds.right +
            halfFeather -
            (glyphBounds.width + feather) * bounded
      : glyphBounds.left -
            halfFeather +
            (glyphBounds.width + feather) * bounded;
  return direction == TextDirection.rtl
      ? (
          start: Offset(front + halfFeather, glyphBounds.center.dy),
          end: Offset(front - halfFeather, glyphBounds.center.dy),
        )
      : (
          start: Offset(front - halfFeather, glyphBounds.center.dy),
          end: Offset(front + halfFeather, glyphBounds.center.dy),
        );
}

List<({int start, int end})> karaokeGraphemeRanges(
  String text, {
  int startOffset = 0,
}) {
  final ranges = <({int start, int end})>[];
  var offset = startOffset;
  for (final grapheme in characters.Characters(text)) {
    final end = offset + grapheme.length;
    if (grapheme.trim().isNotEmpty) ranges.add((start: offset, end: end));
    offset = end;
  }
  return ranges;
}

({int start, int end})? karaokeVisibleTokenBounds(String token) {
  final leading = RegExp(r'^\s*').firstMatch(token)?.end ?? 0;
  final trailingMatch = RegExp(r'\s*$').firstMatch(token);
  final trailing = trailingMatch?.start ?? token.length;
  if (trailing <= leading) return null;
  return (start: leading, end: trailing);
}

double karaokeSyntheticTokenWeight(String token) {
  final visible = token.trim();
  if (visible.isEmpty) return .25;
  // A short word should finish quickly while a long word still gets enough
  // time for its highlight to remain readable. The sub-linear exponent avoids
  // making long English words feel disproportionately slow.
  return math.pow(visible.runes.length, .72).toDouble();
}

List<String> _syntheticKaraokeChunks(String text) {
  if (text.isEmpty) return const [];
  // English-like lyrics move word by word, while CJK lyrics keep true
  // character granularity. Whitespace stays attached to the preceding token
  // so the highlight never leaves isolated gaps between words.
  final raw = RegExp(
    r'[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]|[^\s\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]+\s*|\s+',
  ).allMatches(text).map((match) => match.group(0)!).toList(growable: false);
  return raw.isEmpty ? [text] : raw;
}

class _SynthesizedKaraokeCacheEntry {
  const _SynthesizedKaraokeCacheEntry(this.nextTimestamp, this.line);

  final Duration? nextTimestamp;
  final LyricLine line;
}

final Expando<_SynthesizedKaraokeCacheEntry> _synthesizedKaraokeCache =
    Expando<_SynthesizedKaraokeCacheEntry>();

bool karaokeRowCanHighlight(int rowIndex) => rowIndex == 0;

/// Gives an ordinary line a deterministic karaoke timeline for the optional
/// "all lyrics" mode. The generated word/character tokens mirror the visual
/// cadence of timed LRC without pretending to infer unavailable vocals.
LyricLine synthesizeKaraokeTiming(LyricLine line, {Duration? nextTimestamp}) {
  if (line.isInterlude || line.texts.isEmpty) return line;
  final cached = _synthesizedKaraokeCache[line];
  if (cached != null && cached.nextTimestamp == nextTimestamp) {
    return cached.line;
  }
  final interval = nextTimestamp == null
      ? const Duration(seconds: 4)
      : nextTimestamp - line.timestamp;
  final boundedMs = (interval.inMilliseconds * .92)
      .round()
      .clamp(650, 8000)
      .toInt();
  final tokenRows = <List<LyricToken>>[];
  for (var rowIndex = 0; rowIndex < line.texts.length; rowIndex++) {
    // Only the original lyric row owns karaoke timing. Translation rows stay
    // static and unplayed even in the synthetic "all lyrics" mode.
    if (!karaokeRowCanHighlight(rowIndex)) {
      tokenRows.add(const <LyricToken>[]);
      continue;
    }
    final text = line.texts[rowIndex];
    final chunks = _syntheticKaraokeChunks(text);
    final weights = chunks.map(karaokeSyntheticTokenWeight).toList();
    final totalWeight = weights.fold<double>(0, (sum, value) => sum + value);
    var elapsedWeight = 0.0;
    final row = <LyricToken>[];
    for (var index = 0; index < chunks.length; index++) {
      final startMs = (boundedMs * elapsedWeight / totalWeight).round();
      elapsedWeight += weights[index];
      final endMs = (boundedMs * elapsedWeight / totalWeight).round();
      row.add(
        LyricToken(
          text: chunks[index],
          start: line.timestamp + Duration(milliseconds: startMs),
          end: line.timestamp + Duration(milliseconds: endMs),
        ),
      );
    }
    tokenRows.add(row);
  }
  final synthesized = LyricLine(
    timestamp: line.timestamp,
    texts: line.texts,
    tokens: tokenRows,
  );
  _synthesizedKaraokeCache[line] = _SynthesizedKaraokeCacheEntry(
    nextTimestamp,
    synthesized,
  );
  return synthesized;
}

bool hasUsableKaraokeTiming(LyricLine line) {
  final rows = line.tokens;
  if (rows == null || rows.isEmpty) return false;
  return rows.first.any((token) => token.end > token.start);
}

class MobileLyricsList extends StatefulWidget {
  const MobileLyricsList({
    super.key,
    required this.lines,
    required this.active,
    this.contentIdentity,
    this.activeColor,
    this.fontSize = 20,
    this.fontFamily,
    this.fontWeight = FontWeight.w600,
    this.controller,
    this.edgeFadeEnabled = false,
    this.glowEnabled = false,
    this.glowRadius = 8,
    this.brightForeground = false,
    this.textAlign = TextAlign.center,
    this.elasticScrollEnabled = false,
    this.karaokeLyricsEnabled = true,
    this.karaokeLyricsMode = KaraokeLyricsMode.timedOnly,
    this.lineBlurEnabled = false,
    this.highlightActiveLine = false,
    this.isPlaying = true,
    this.playbackRate = 1,
    this.playbackRateListenable,
    this.actualPlaybackListenable,
    this.seekPositionListenable,
    this.seekIntentListenable,
    this.position = Duration.zero,
    this.positionListenable,
    this.onBrowseTargetChanged,
    this.onBrowseTargetSelected,
  });

  final List<LyricLine> lines;
  final int active;
  final Object? contentIdentity;
  final Color? activeColor;
  final double fontSize;
  final String? fontFamily;
  final FontWeight fontWeight;
  final MobileLyricsListController? controller;
  final bool edgeFadeEnabled;
  final bool glowEnabled;
  final double glowRadius;
  final bool brightForeground;
  final TextAlign textAlign;
  final bool elasticScrollEnabled;
  final bool karaokeLyricsEnabled;
  final KaraokeLyricsMode karaokeLyricsMode;
  final bool lineBlurEnabled;
  final bool highlightActiveLine;
  final bool isPlaying;
  final double playbackRate;
  final ValueListenable<double>? playbackRateListenable;
  final ValueListenable<bool>? actualPlaybackListenable;
  final ValueListenable<Duration?>? seekPositionListenable;
  final ValueListenable<int>? seekIntentListenable;
  final Duration position;
  final ValueListenable<Duration>? positionListenable;
  final ValueChanged<Duration?>? onBrowseTargetChanged;
  final ValueChanged<Duration>? onBrowseTargetSelected;

  @override
  State<MobileLyricsList> createState() => _MobileLyricsListState();
}

class _MobileLyricsListState extends State<MobileLyricsList>
    with SingleTickerProviderStateMixin {
  static const _focusAnchor = .4;

  ScrollController? _scrollControllerState;
  // One critically damped motion retains velocity when consecutive lyric
  // targets arrive. This avoids restarting a slow easing curve at every line.
  final LyricScrollMotion _motion = LyricScrollMotion(
    dampingRatio: 1,
    frequency: mobileLyricsDefaultScrollFrequency,
  );
  final ValueNotifier<_LyricDebugSnapshot> _debugSnapshot = ValueNotifier(
    const _LyricDebugSnapshot(),
  );
  final ValueNotifier<_LyricElasticPulse> _elasticPulse = ValueNotifier(
    const _LyricElasticPulse(),
  );
  final ValueNotifier<_LyricBrowseHighlightFrame> _browseHighlight =
      ValueNotifier(const _LyricBrowseHighlightFrame());
  final GlobalKey _browseTapTargetRenderKey = GlobalKey();
  late final Ticker _motionTicker;
  Duration? _lastTick;
  Duration _lastDebugUpdate = Duration.zero;
  Timer? _resumeFollowTimer;
  Timer? _browseHighlightRevealTimer;
  Timer? _browseChromeExitTimer;
  Timer? _seekTargetTimer;
  Timer? _seekTargetConfirmationTimer;
  bool _isManuallyBrowsing = false;
  bool _browseHighlightVisible = false;
  bool _lyricsPointerDown = false;
  bool _browseSelectionDispatching = false;
  bool _hasInitialPosition = false;
  bool _layoutInvalid = true;
  bool _pendingTypographyReanchor = false;
  bool _debugOverlayEnabled = false;
  int _layoutRequestId = 0;
  int _seekElasticReplayId = 0;
  int _lyricContentRevision = 0;
  bool _awaitingNextSongLyrics = false;
  int _recompositionCount = 0;
  int? _browseTargetIndex;
  int? _seekTargetIndex;
  int? _normalExitIndex;
  bool _explicitSeekPending = false;
  Timer? _explicitSeekTimer;
  Duration? _seekTargetTimestamp;
  double _viewportHeight = 0;
  double _layoutWidth = 0;
  double _topPadding = 0;
  double _bottomPadding = 0;
  double _browseMinimumHitHeight = 0;
  List<double> _itemHeights = const [];
  List<double> _itemOffsets = const [];
  List<LyricLine>? _layoutLines;
  double _layoutFontSize = -1;
  String? _layoutFontFamily;
  TextAlign _layoutTextAlign = TextAlign.center;
  TextDirection? _layoutDirection;
  double _layoutTextScale = -1;

  ScrollController get _scrollController => _scrollControllerState!;

  @override
  void initState() {
    super.initState();
    _motionTicker = createTicker(_onMotionTick);
    widget.seekIntentListenable?.addListener(_markExplicitSeek);
    widget.controller?._attach(this, _recenterActive, _settleOnTimestamp);
  }

  void _markExplicitSeek() {
    _explicitSeekPending = true;
    _explicitSeekTimer?.cancel();
    _explicitSeekTimer = Timer(const Duration(seconds: 2), () {
      _explicitSeekPending = false;
    });
  }

  @override
  void didUpdateWidget(covariant MobileLyricsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seekIntentListenable != widget.seekIntentListenable) {
      oldWidget.seekIntentListenable?.removeListener(_markExplicitSeek);
      widget.seekIntentListenable?.addListener(_markExplicitSeek);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this, _recenterActive, _settleOnTimestamp);
    }
    final linesChanged = oldWidget.lines != widget.lines;
    final contentChanged = oldWidget.contentIdentity != widget.contentIdentity;
    if (contentChanged) {
      _normalExitIndex = null;
      _explicitSeekPending = false;
      _awaitingNextSongLyrics = true;
      _resetScrollPositionForNewContent();
    }
    final fontChanged =
        (oldWidget.fontSize - widget.fontSize).abs() >= .01 ||
        oldWidget.fontFamily != widget.fontFamily ||
        oldWidget.fontWeight != widget.fontWeight ||
        oldWidget.textAlign != widget.textAlign;
    if (linesChanged) {
      _lyricContentRevision++;
      _seekElasticReplayId++;
    }
    if (linesChanged || fontChanged || contentChanged) {
      _layoutInvalid = true;
      if (fontChanged && !contentChanged) {
        // Font growth changes every item offset. Continuing the previous
        // spring against the new coordinates causes visible back-and-forth
        // movement, especially near the largest lyric size.
        _pendingTypographyReanchor = true;
        _stopMotion();
        final previousPulse = _elasticPulse.value;
        _elasticPulse.value = _LyricElasticPulse(id: previousPulse.id + 1);
      }
      final replacingNextSongLyrics =
          linesChanged && _awaitingNextSongLyrics && !contentChanged;
      final preserveManualInteraction =
          !contentChanged &&
          !replacingNextSongLyrics &&
          (_lyricsPointerDown || _isManuallyBrowsing);
      final pendingSeekTimestamp = contentChanged ? null : _seekTargetTimestamp;
      if (pendingSeekTimestamp != null && widget.lines.isNotEmpty) {
        final remappedTarget = _nearestLyricIndex(pendingSeekTimestamp);
        _seekTargetTimer?.cancel();
        _seekTargetConfirmationTimer?.cancel();
        _seekTargetIndex = remappedTarget;
        _seekTargetTimestamp = pendingSeekTimestamp;
        _armSeekTargetTimeout(pendingSeekTimestamp, remappedTarget);
        if (widget.active == remappedTarget) {
          _armSeekTargetConfirmation(remappedTarget);
        }
      } else {
        _clearSeekTarget();
      }
      if (!preserveManualInteraction) {
        _resumeAutomaticFollow(notifyBrowseTarget: false);
      }
      if (replacingNextSongLyrics) _resetScrollPositionForNewContent();
      if (oldWidget.lines.isEmpty) _hasInitialPosition = false;
      if (linesChanged && widget.lines.isNotEmpty) {
        _awaitingNextSongLyrics = false;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onBrowseTargetChanged?.call(null);
      });
      if (!preserveManualInteraction) {
        _scheduleLayoutRetarget(
          jump:
              contentChanged ||
              replacingNextSongLyrics ||
              oldWidget.lines.isEmpty,
        );
      }
      return;
    }

    if (oldWidget.elasticScrollEnabled != widget.elasticScrollEnabled) {
      _stopMotion();
      if (_scrollControllerState?.hasClients ?? false) {
        _motion.sync(_scrollController.offset, viewportExtent: _viewportHeight);
      }
      _retargetIndex(widget.active, force: true, springLines: false);
    }

    if (oldWidget.active == widget.active) return;
    _normalExitIndex =
        widget.active == oldWidget.active + 1 &&
            _seekTargetIndex == null &&
            !_explicitSeekPending &&
            !_isManuallyBrowsing &&
            widget.isPlaying &&
            oldWidget.isPlaying
        ? oldWidget.active
        : null;
    _explicitSeekPending = false;
    final seekTarget = _seekTargetIndex;
    if (seekTarget != null) {
      if (widget.active == seekTarget) {
        _armSeekTargetConfirmation(seekTarget);
      } else {
        _seekTargetConfirmationTimer?.cancel();
        _seekTargetConfirmationTimer = null;
      }
      return;
    }
    // Timestamp jumps, decoder catch-up and skipped empty lines can advance
    // several rows at once. Do not animate the entire off-screen distance:
    // mount near the destination first, then animate only the visible tail.
    _retargetIndex(widget.active, boundedTravel: true);
  }

  void _resetScrollPositionForNewContent() {
    _layoutRequestId++;
    _seekElasticReplayId++;
    _stopMotion();
    _pendingTypographyReanchor = false;
    final previousController = _scrollControllerState;
    _scrollControllerState = null;
    _hasInitialPosition = false;
    _motion.sync(0, viewportExtent: _viewportHeight);
    if (previousController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previousController.dispose();
      });
    }
  }

  void _onMotionTick(Duration elapsed) {
    if (!_scrollController.hasClients) {
      _stopMotion();
      return;
    }
    final previousTick = _lastTick;
    _lastTick = elapsed;
    if (previousTick == null) return;
    InteractionPerformanceController.instance.pulse(
      InteractionPhase.visualAnimation,
      settleAfter: const Duration(milliseconds: 80),
    );
    final frameSeconds =
        (elapsed - previousTick).inMicroseconds /
        Duration.microsecondsPerSecond;
    final maxOffset = _scrollController.position.maxScrollExtent;
    _motion.retarget(
      _motion.target.clamp(0.0, maxOffset),
      viewportExtent: _viewportHeight,
    );
    final nextOffset = _motion.advance(frameSeconds).clamp(0.0, maxOffset);
    if ((_scrollController.offset - nextOffset).abs() >= .05) {
      _scrollController.jumpTo(nextOffset);
    }
    _updateDebugSnapshot(elapsed, frameSeconds);
    if (_motion.isSettled) _stopMotion();
  }

  void _startMotion() {
    if (_motionTicker.isActive) return;
    // Ticker elapsed time starts at zero for every start. Seeding the previous
    // value lets the first rendered tick advance immediately instead of
    // spending one frame only initializing timing state.
    _lastTick = Duration.zero;
    _motionTicker.start();
  }

  void _stopMotion() {
    if (_motionTicker.isActive) _motionTicker.stop();
    _lastTick = null;
    InteractionPerformanceController.instance.endPhase(
      InteractionPhase.visualAnimation,
    );
  }

  bool _retargetIndex(
    int index, {
    bool force = false,
    bool springLines = true,
    bool boundedTravel = false,
  }) {
    if (((_lyricsPointerDown || _isManuallyBrowsing) && !force) ||
        index < 0 ||
        index >= _itemOffsets.length) {
      return false;
    }
    return _retargetOffset(
      _itemOffsets[index],
      springLines: springLines,
      anchorIndex: index,
      boundedTravel: boundedTravel,
    );
  }

  bool _retargetOffset(
    double target, {
    bool springLines = false,
    int? anchorIndex,
    bool boundedTravel = false,
  }) {
    if (!_scrollController.hasClients) {
      _scheduleLayoutRetarget();
      return false;
    }
    final clampedTarget = target.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    if (widget.elasticScrollEnabled && springLines) {
      final displacement = clampedTarget - _scrollController.offset;
      _stopMotion();
      if (displacement.abs() >= .35) {
        InteractionPerformanceController.instance.pulse(
          InteractionPhase.visualAnimation,
          settleAfter: const Duration(milliseconds: 1100),
        );
        final previous = _elasticPulse.value;
        final visualDisplacement = clampLyricElasticDisplacement(
          displacement,
          _viewportHeight,
          fontSize: widget.fontSize,
        );
        final isLongJump = visualDisplacement.abs() + .5 < displacement.abs();
        final lineDuration = _lineDurationSeconds(anchorIndex ?? widget.active);
        _elasticPulse.value = _LyricElasticPulse(
          id: previous.id + 1,
          displacement: visualDisplacement,
          anchorIndex: anchorIndex ?? widget.active,
          lineDurationSeconds: isLongJump
              ? lineDuration.clamp(.35, .75).toDouble()
              : lineDuration,
        );
        _scrollController.jumpTo(clampedTarget);
      }
      _motion.sync(clampedTarget, viewportExtent: _viewportHeight);
      return true;
    }

    if (widget.elasticScrollEnabled) {
      _motion.offset = _scrollController.offset;
      _motion.retarget(clampedTarget, viewportExtent: _viewportHeight);
      _startMotion();
      return true;
    }

    var animationStart = _scrollController.offset;
    if (boundedTravel) {
      final boundedStart = boundedLyricAnimationStart(
        animationStart,
        clampedTarget,
        _viewportHeight,
        fontSize: widget.fontSize,
      );
      if ((boundedStart - animationStart).abs() >= .05) {
        animationStart = boundedStart;
        _scrollController.jumpTo(animationStart);
      }
    }
    if (_motionTicker.isActive) {
      // Preserve the current velocity across dense or multi-line lyric
      // changes, while synchronizing any offset changed by a bounded seek.
      _motion.offset = animationStart;
    } else {
      _motion.sync(animationStart, viewportExtent: _viewportHeight);
    }
    _motion.retarget(clampedTarget, viewportExtent: _viewportHeight);
    _startMotion();
    return true;
  }

  double _lineDurationSeconds(int index) {
    if (index < 0 || index + 1 >= widget.lines.length) return 1.5;
    final duration =
        widget.lines[index + 1].timestamp.inMicroseconds -
        widget.lines[index].timestamp.inMicroseconds;
    return duration <= 0 ? 1.5 : duration / Duration.microsecondsPerSecond;
  }

  void _jumpToIndex(int index) {
    if (!_scrollController.hasClients ||
        index < 0 ||
        index >= _itemOffsets.length) {
      return;
    }
    final target = _itemOffsets[index].clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _stopMotion();
    _scrollController.jumpTo(target);
    _motion.sync(target, viewportExtent: _viewportHeight);
    _hasInitialPosition = true;
    _pendingTypographyReanchor = false;
  }

  void _scheduleLayoutRetarget({bool jump = false}) {
    final requestId = ++_layoutRequestId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          requestId != _layoutRequestId ||
          _lyricsPointerDown ||
          _isManuallyBrowsing) {
        return;
      }
      final controller = _scrollControllerState;
      if (controller == null ||
          !controller.hasClients ||
          _itemOffsets.isEmpty) {
        return;
      }
      final seekTarget = _seekTargetIndex;
      if (seekTarget != null) {
        if (_pendingTypographyReanchor) {
          _jumpToIndex(seekTarget);
        } else {
          _retargetIndex(seekTarget, force: true, boundedTravel: true);
        }
        return;
      }
      if (jump || !_hasInitialPosition || _pendingTypographyReanchor) {
        _jumpToIndex(widget.active.clamp(0, _itemOffsets.length - 1));
      } else {
        _retargetIndex(widget.active, force: true, springLines: false);
      }
    });
  }

  void _startManualInteraction() {
    if (!mounted) return;
    _layoutRequestId++;
    _seekElasticReplayId++;
    _clearSeekTarget(rebuild: true);
    _browseHighlightRevealTimer?.cancel();
    _browseHighlightRevealTimer = null;
    _browseChromeExitTimer?.cancel();
    _browseChromeExitTimer = null;
    if (!_isManuallyBrowsing || _browseHighlightVisible) {
      setState(() {
        _isManuallyBrowsing = true;
        _browseHighlightVisible = false;
      });
    }
    _stopMotion();
    final previousPulse = _elasticPulse.value;
    _elasticPulse.value = _LyricElasticPulse(id: previousPulse.id + 1);
    _motion.sync(
      _scrollController.hasClients ? _scrollController.offset : 0,
      viewportExtent: _viewportHeight,
    );
    _resumeFollowTimer?.cancel();
    _resumeFollowTimer = null;
    _updateBrowseTargetFromOffset(force: true);
  }

  void _scheduleResumeFollowTimer() {
    if (!mounted || !_isManuallyBrowsing) return;
    _scheduleBrowseHighlightReveal();
    _resumeFollowTimer?.cancel();
    _resumeFollowTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _resumeFollowTimer = null;
      if (_lyricsPointerDown) return;
      if (_scrollController.hasClients &&
          _scrollController.position.isScrollingNotifier.value) {
        return;
      }
      _resumeAutomaticFollow();
      _retargetIndex(widget.active, force: true);
    });
  }

  void _scheduleBrowseHighlightReveal() {
    _browseHighlightRevealTimer?.cancel();
    _browseHighlightRevealTimer = Timer(mobileLyricsBrowseMaskRevealDelay, () {
      if (!mounted || !_isManuallyBrowsing || _browseTargetIndex == null) {
        return;
      }
      _browseHighlightRevealTimer = null;
      setState(() => _browseHighlightVisible = true);
    });
  }

  void _resumeAutomaticFollow({bool notifyBrowseTarget = true}) {
    _resumeFollowTimer?.cancel();
    _resumeFollowTimer = null;
    _browseHighlightRevealTimer?.cancel();
    _browseHighlightRevealTimer = null;
    _browseChromeExitTimer?.cancel();
    _browseChromeExitTimer = null;
    final wasManuallyBrowsing = _isManuallyBrowsing;
    final animateExit =
        _browseHighlightVisible && _browseHighlight.value.entry != null;
    _isManuallyBrowsing = false;
    _browseHighlightVisible = false;
    if (animateExit) {
      _browseChromeExitTimer = Timer(mobileLyricsBrowseMaskRevealDuration, () {
        if (!mounted || _isManuallyBrowsing || _browseHighlightVisible) return;
        _browseChromeExitTimer = null;
        setState(() => _browseTargetIndex = null);
        _clearBrowseHighlight();
      });
    } else {
      _browseTargetIndex = null;
      _clearBrowseHighlight();
    }
    if (notifyBrowseTarget) widget.onBrowseTargetChanged?.call(null);
    if ((wasManuallyBrowsing || animateExit) && mounted) setState(() {});
  }

  bool _selectBrowseTarget({bool requireVisible = true}) {
    final target = _browseTargetIndex;
    if (!_isManuallyBrowsing ||
        (requireVisible && !_browseHighlightVisible) ||
        target == null ||
        target < 0 ||
        target >= widget.lines.length) {
      return false;
    }
    _browseSelectionDispatching = true;
    try {
      widget.onBrowseTargetSelected?.call(widget.lines[target].timestamp);
    } finally {
      _browseSelectionDispatching = false;
    }
    return true;
  }

  double _browseHitHeight(_LyricBrowseHighlightEntry entry) =>
      entry.height < _browseMinimumHitHeight
      ? _browseMinimumHitHeight
      : entry.height;

  bool _browseTargetContainsGlobalPosition(Offset position) {
    final renderObject = _browseTapTargetRenderKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;
    final localPosition = renderObject.globalToLocal(position);
    return (Offset.zero & renderObject.size).contains(localPosition);
  }

  bool _isBrowseTargetAtGlobalPosition(Offset position) =>
      _isManuallyBrowsing &&
      _browseHighlightVisible &&
      _browseTargetIndex != null &&
      widget.onBrowseTargetSelected != null &&
      _browseTargetContainsGlobalPosition(position);

  bool _selectBrowseTargetAtGlobalPosition(Offset position) {
    if (!_isBrowseTargetAtGlobalPosition(position)) {
      return false;
    }
    _selectBrowseTarget();
    return true;
  }

  void _handleLyricsPointerDown(PointerDownEvent event) {
    _lyricsPointerDown = true;
    _layoutRequestId++;
    _stopMotion();
    if (!_isManuallyBrowsing && _scrollController.hasClients) {
      final frozenOffset = _scrollController.offset;
      _scrollController.jumpTo(frozenOffset);
      _motion.sync(frozenOffset, viewportExtent: _viewportHeight);
    }
    _resumeFollowTimer?.cancel();
    _resumeFollowTimer = null;
  }

  void _handleLyricsPointerMove(PointerMoveEvent event) {
    // Scrolling is owned by the list. The jump target has its own tap
    // recognizer, so a drag automatically rejects the jump in the gesture
    // arena instead of relying on a second, timing-sensitive pointer latch.
  }

  void _handleLyricsPointerEnd(PointerEvent event) {
    if (!_lyricsPointerDown) return;
    _lyricsPointerDown = false;
    final scrollStillActive =
        _scrollController.hasClients &&
        _scrollController.position.isScrollingNotifier.value;
    if (!_isManuallyBrowsing) {
      if (!scrollStillActive) {
        _scheduleLayoutRetarget(jump: !_hasInitialPosition);
      }
      return;
    }
    if (_isManuallyBrowsing &&
        _resumeFollowTimer == null &&
        !scrollStillActive) {
      _scheduleResumeFollowTimer();
    }
  }

  void _clearBrowseHighlight() {
    if (_browseHighlight.value.entry == null) return;
    _browseHighlight.value = const _LyricBrowseHighlightFrame();
  }

  void _updateBrowseHighlightForOffset(double offset) {
    final target = _browseTargetIndex;
    if (!_isManuallyBrowsing ||
        target == null ||
        _itemOffsets.isEmpty ||
        _itemHeights.isEmpty ||
        _viewportHeight <= 0) {
      _clearBrowseHighlight();
      return;
    }
    final anchorY = _viewportHeight * _focusAnchor;
    final centerY = anchorY + _itemOffsets[target] - offset;
    _browseHighlight.value = _LyricBrowseHighlightFrame(
      entry: _LyricBrowseHighlightEntry(
        top: centerY - _itemHeights[target] / 2,
        height: _itemHeights[target],
      ),
    );
  }

  void _updateBrowseTargetFromOffset({bool force = false}) {
    if (!_isManuallyBrowsing ||
        widget.lines.isEmpty ||
        !_scrollController.hasClients ||
        _itemOffsets.isEmpty) {
      return;
    }
    final contentAnchor =
        _scrollController.offset + _viewportHeight * _focusAnchor;
    var low = 0;
    var high = _itemOffsets.length - 1;
    while (low < high) {
      final mid = (low + high) >> 1;
      final itemCenter = _itemOffsets[mid] + _viewportHeight * _focusAnchor;
      if (itemCenter < contentAnchor) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    var index = low;
    if (index > 0) {
      final currentCenter =
          _itemOffsets[index] + _viewportHeight * _focusAnchor;
      final previousCenter =
          _itemOffsets[index - 1] + _viewportHeight * _focusAnchor;
      if ((contentAnchor - previousCenter).abs() <
          (contentAnchor - currentCenter).abs()) {
        index--;
      }
    }
    final changed = index != _browseTargetIndex;
    if (changed) {
      setState(() => _browseTargetIndex = index);
      widget.onBrowseTargetChanged?.call(widget.lines[index].timestamp);
    } else if (force) {
      widget.onBrowseTargetChanged?.call(widget.lines[index].timestamp);
    }
    _updateBrowseHighlightForOffset(_scrollController.offset);
  }

  void _recenterActive() {
    _clearSeekTarget();
    _resumeAutomaticFollow();
    _scheduleLayoutRetarget(jump: true);
  }

  void _settleOnTimestamp(Duration timestamp) {
    if (widget.lines.isEmpty) return;
    final fromBrowseSelection = _browseSelectionDispatching;
    _resumeAutomaticFollow();

    final targetIndex = _nearestLyricIndex(timestamp);

    _seekTargetTimer?.cancel();
    _seekTargetTimestamp = timestamp;
    final previousPulseId = _elasticPulse.value.id;
    final elasticReplayId = ++_seekElasticReplayId;
    final seekLines = widget.lines;
    setState(() {
      _seekTargetIndex = targetIndex;
    });
    final retargeted = _retargetIndex(
      targetIndex,
      force: true,
      boundedTravel: true,
    );
    if (!retargeted) _scheduleLayoutRetarget();
    if (fromBrowseSelection) {
      final pulse = _elasticPulse.value;
      _elasticPulse.value = _LyricElasticPulse(
        id: pulse.id + 1,
        anchorIndex: targetIndex,
      );
    }
    if (!fromBrowseSelection &&
        widget.elasticScrollEnabled &&
        _elasticPulse.value.id == previousPulseId) {
      final currentPosition =
          widget.positionListenable?.value ?? widget.position;
      final direction = timestamp >= currentPosition ? 1.0 : -1.0;
      _elasticPulse.value = _LyricElasticPulse(
        id: previousPulseId + 1,
        displacement: direction * 14,
        anchorIndex: targetIndex,
        lineDurationSeconds: .45,
      );
    }
    if (!fromBrowseSelection && widget.elasticScrollEnabled) {
      final currentPosition =
          widget.positionListenable?.value ?? widget.position;
      final direction = timestamp >= currentPosition ? 1.0 : -1.0;
      final pulse = _elasticPulse.value;
      final displacement = pulse.displacement.abs() >= .35
          ? pulse.displacement
          : direction * 14;
      final lineDuration = pulse.lineDurationSeconds.clamp(.35, .75).toDouble();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            elasticReplayId != _seekElasticReplayId ||
            !identical(widget.lines, seekLines) ||
            !widget.elasticScrollEnabled ||
            targetIndex >= widget.lines.length) {
          return;
        }
        final latest = _elasticPulse.value;
        _elasticPulse.value = _LyricElasticPulse(
          id: latest.id + 1,
          displacement: displacement,
          anchorIndex: targetIndex,
          lineDurationSeconds: lineDuration,
        );
      });
      WidgetsBinding.instance.scheduleFrame();
    }
    _armSeekTargetTimeout(timestamp, targetIndex);
    if (widget.active == targetIndex) {
      _armSeekTargetConfirmation(targetIndex);
    }
  }

  int _nearestLyricIndex(Duration timestamp) {
    var targetIndex = 0;
    var nearestDistance = (widget.lines.first.timestamp - timestamp)
        .inMilliseconds
        .abs();
    for (var index = 1; index < widget.lines.length; index++) {
      final distance = (widget.lines[index].timestamp - timestamp)
          .inMilliseconds
          .abs();
      if (distance >= nearestDistance) continue;
      nearestDistance = distance;
      targetIndex = index;
    }
    return targetIndex;
  }

  void _armSeekTargetTimeout(Duration timestamp, int targetIndex) {
    _seekTargetTimer?.cancel();
    _seekTargetTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted ||
          _seekTargetTimestamp != timestamp ||
          _seekTargetIndex != targetIndex) {
        return;
      }
      _clearSeekTarget(rebuild: true);
      _retargetIndex(widget.active, force: true);
    });
  }

  void _armSeekTargetConfirmation(int targetIndex) {
    final timestamp = _seekTargetTimestamp;
    if (timestamp == null || _seekTargetIndex != targetIndex) return;
    _seekTargetConfirmationTimer?.cancel();
    _seekTargetConfirmationTimer = Timer(const Duration(milliseconds: 750), () {
      if (!mounted ||
          _seekTargetTimestamp != timestamp ||
          _seekTargetIndex != targetIndex ||
          widget.active != targetIndex) {
        return;
      }
      _clearSeekTarget(rebuild: true);
    });
  }

  void _clearSeekTarget({bool rebuild = false}) {
    final hadTarget = _seekTargetIndex != null;
    _seekTargetTimer?.cancel();
    _seekTargetTimer = null;
    _seekTargetConfirmationTimer?.cancel();
    _seekTargetConfirmationTimer = null;
    _seekTargetIndex = null;
    _seekTargetTimestamp = null;
    if (rebuild && hadTarget && mounted) setState(() {});
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _startManualInteraction();
    } else if (notification is ScrollUpdateNotification &&
        _isManuallyBrowsing) {
      _motion.sync(
        notification.metrics.pixels,
        viewportExtent: _viewportHeight,
      );
      _updateBrowseTargetFromOffset();
    } else if (notification is ScrollEndNotification && _isManuallyBrowsing) {
      _scheduleResumeFollowTimer();
    }
    return false;
  }

  bool _ensureLayoutMetrics(BuildContext context, BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final viewport = constraints.maxHeight;
    final direction = Directionality.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final unchanged =
        !_layoutInvalid &&
        identical(_layoutLines, widget.lines) &&
        (_layoutWidth - width).abs() < .5 &&
        (_viewportHeight - viewport).abs() < .5 &&
        (_layoutFontSize - widget.fontSize).abs() < .01 &&
        _layoutFontFamily == widget.fontFamily &&
        widget.textAlign == _layoutTextAlign &&
        _layoutDirection == direction &&
        (_layoutTextScale - textScale).abs() < .001;
    if (unchanged) return false;

    _layoutInvalid = false;
    _layoutLines = widget.lines;
    _layoutWidth = width;
    _viewportHeight = viewport;
    _layoutFontSize = widget.fontSize;
    _motion.updateDynamics(
      frequency: mobileLyricsScrollFrequencyForFontSize(widget.fontSize),
    );
    _layoutFontFamily = widget.fontFamily;
    _layoutTextAlign = widget.textAlign;
    _layoutDirection = direction;
    _layoutTextScale = textScale;

    final horizontalInset = mobileLyricsHorizontalInset(widget.textAlign);
    final availableWidth = mobileLyricScaleSafeContentWidth(
      (width - horizontalInset * 2).clamp(1.0, double.infinity),
    );
    final textStyle = DefaultTextStyle.of(context).style.copyWith(
      fontFamily: widget.fontFamily,
      fontSize: widget.fontSize,
      fontWeight: widget.fontWeight,
      height: 1.2,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final lineMetricPainter = TextPainter(
      text: TextSpan(text: 'M', style: textStyle),
      textDirection: direction,
      textScaler: scaler,
    )..layout(maxWidth: availableWidth);
    _browseMinimumHitHeight = lineMetricPainter.height * 3 + 10;
    final heights = List<double>.filled(widget.lines.length, 0);
    final offsets = List<double>.filled(widget.lines.length, 0);
    var runningOffset = 0.0;
    for (var index = 0; index < widget.lines.length; index++) {
      final painter = TextPainter(
        text: TextSpan(
          text: widget.lines[index].texts.join('\n'),
          style: textStyle,
        ),
        textAlign: widget.textAlign,
        textDirection: direction,
        textScaler: scaler,
      )..layout(maxWidth: availableWidth);
      final contentHeight = (painter.height + 10).clamp(
        widget.fontSize * 1.2 + 10,
        double.infinity,
      );
      // AnimatedScale changes paint bounds without changing sliver geometry.
      // Reserve the maximum painted extent so a departing active line stays
      // mounted until its enlarged pixels have actually left the viewport.
      final height = mobileLyricScaleSafeExtent(contentHeight);
      heights[index] = height;
      offsets[index] = runningOffset;
      runningOffset += height;
    }
    _itemHeights = heights;
    _topPadding = widget.lines.isEmpty
        ? 0
        : (viewport * _focusAnchor - heights.first / 2).clamp(
            0.0,
            double.infinity,
          );
    _bottomPadding = widget.lines.isEmpty
        ? 0
        : (viewport * (1 - _focusAnchor) - heights.last / 2).clamp(
            0.0,
            double.infinity,
          );
    _itemOffsets = List<double>.generate(
      offsets.length,
      (index) =>
          _topPadding +
          offsets[index] +
          heights[index] / 2 -
          viewport * _focusAnchor,
      growable: false,
    );
    final controller = _scrollControllerState;
    if (_pendingTypographyReanchor &&
        controller != null &&
        controller.hasClients &&
        _itemOffsets.isNotEmpty) {
      // Font metrics and the scroll anchor must become visible in the same
      // frame. A post-frame jump briefly paints the resized line at its old
      // offset, which looks like a one-frame twitch while dragging the slider.
      final anchor = widget.active.clamp(0, _itemOffsets.length - 1);
      final target = _itemOffsets[anchor];
      controller.position.correctPixels(target);
      _motion.sync(target, viewportExtent: _viewportHeight);
      _hasInitialPosition = true;
      _pendingTypographyReanchor = false;
      return true;
    }
    _scheduleLayoutRetarget(jump: !_hasInitialPosition);
    return true;
  }

  void _updateDebugSnapshot(Duration elapsed, double frameSeconds) {
    if (!_debugOverlayEnabled ||
        elapsed - _lastDebugUpdate < const Duration(milliseconds: 160)) {
      return;
    }
    _lastDebugUpdate = elapsed;
    _debugSnapshot.value = _LyricDebugSnapshot(
      currentIndex: widget.active,
      targetOffset: _motion.target,
      currentOffset: _motion.offset,
      velocity: _motion.velocity,
      userScrolling: _isManuallyBrowsing,
      fps: frameSeconds <= 0 ? 0 : 1 / frameSeconds,
      frameTimeMs: frameSeconds * 1000,
      recompositionCount: _recompositionCount,
    );
  }

  @override
  void dispose() {
    widget.seekIntentListenable?.removeListener(_markExplicitSeek);
    _explicitSeekTimer?.cancel();
    InteractionPerformanceController.instance.endPhase(
      InteractionPhase.visualAnimation,
    );
    widget.controller?._detach(this);
    _motionTicker.dispose();
    _scrollControllerState?.dispose();
    _debugSnapshot.dispose();
    _elasticPulse.dispose();
    _browseHighlight.dispose();
    _resumeFollowTimer?.cancel();
    _browseHighlightRevealTimer?.cancel();
    _browseChromeExitTimer?.cancel();
    _seekTargetTimer?.cancel();
    _seekTargetConfirmationTimer?.cancel();
    _layoutRequestId++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.lines.isEmpty
      ? const Center(child: Text('暂无歌词'))
      : LayoutBuilder(
          builder: (context, constraints) {
            _ensureLayoutMetrics(context, constraints);
            final displayedActive = (_seekTargetIndex ?? widget.active).clamp(
              0,
              widget.lines.length - 1,
            );
            final displayedPosition = _seekTargetIndex == null
                ? widget.position
                : widget.lines[displayedActive].timestamp;
            if (_scrollControllerState == null) {
              final initialIndex = displayedActive.clamp(
                0,
                _itemOffsets.length - 1,
              );
              final initialOffset = _itemOffsets[initialIndex];
              _scrollControllerState = ScrollController(
                initialScrollOffset: initialOffset,
              );
              _motion.sync(initialOffset, viewportExtent: _viewportHeight);
              _hasInitialPosition = true;
            }
            // Extend the render viewport beyond the clipped screen. This keeps
            // tall translated lines mounted until their final pixels leave the
            // top edge, including while elastic transforms are settling.
            Widget lyrics = ClipRect(
              key: const ValueKey('mobile_lyrics_viewport'),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: -mobileLyricsRenderOverflow,
                    bottom: -mobileLyricsRenderOverflow,
                    left: 0,
                    right: 0,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScrollNotification,
                      child: KeyedSubtree(
                        key: ValueKey((
                          'mobile_lyrics_content',
                          widget.contentIdentity,
                        )),
                        child: ListView.builder(
                          key: const ValueKey('mobile_lyrics_scroll_view'),
                          controller: _scrollController,
                          padding: EdgeInsets.only(
                            top: _topPadding + mobileLyricsRenderOverflow,
                            bottom: _bottomPadding + mobileLyricsRenderOverflow,
                          ),
                          scrollCacheExtent: const ScrollCacheExtent.pixels(
                            240,
                          ),
                          itemCount: widget.lines.length,
                          itemExtentBuilder: (index, dimensions) =>
                              _itemHeights[index],
                          itemBuilder: (itemContext, index) {
                            _recompositionCount++;
                            final distance = (index - displayedActive).abs();
                            final browseTarget =
                                _isManuallyBrowsing &&
                                index == _browseTargetIndex;
                            final browseHighlighted =
                                browseTarget && _browseHighlightVisible;
                            Widget item = _LyricLineItem(
                              key: ValueKey('mobile_lyric_$index'),
                              line: widget.lines[index],
                              active: index == displayedActive,
                              distance: distance,
                              relativeDistance: index - displayedActive,
                              height: _itemHeights[index],
                              fontSize: widget.fontSize,
                              fontFamily: widget.fontFamily,
                              activeColor: widget.activeColor,
                              styleIdentity: (
                                widget.contentIdentity,
                                widget.activeColor?.toARGB32(),
                              ),
                              fontWeight: widget.fontWeight,
                              glowEnabled: widget.glowEnabled,
                              glowRadius: widget.glowRadius,
                              brightForeground: widget.brightForeground,
                              textAlign: widget.textAlign,
                              lineBlurEnabled: widget.lineBlurEnabled,
                              highlightActiveLine: widget.highlightActiveLine,
                              karaokeLyricsEnabled: widget.karaokeLyricsEnabled,
                              karaokeLyricsMode: widget.karaokeLyricsMode,
                              nextTimestamp: index + 1 < widget.lines.length
                                  ? widget.lines[index + 1].timestamp
                                  : null,
                              browseHighlighted: browseHighlighted,
                              lineBlurSuppressed: _isManuallyBrowsing,
                              regularScrollMode: !widget.elasticScrollEnabled,
                              isPlaying: widget.isPlaying,
                              normalExit: index == _normalExitIndex,
                              playbackRate: widget.playbackRate,
                              playbackRateListenable:
                                  widget.playbackRateListenable,
                              actualPlaybackListenable:
                                  widget.actualPlaybackListenable,
                              seekPositionListenable:
                                  widget.seekPositionListenable,
                              position: displayedPosition,
                              positionListenable:
                                  _seekTargetIndex == null &&
                                      index == displayedActive
                                  ? widget.positionListenable
                                  : null,
                            );
                            if (widget.elasticScrollEnabled) {
                              item = _ElasticLyricLine(
                                key: ValueKey(
                                  'mobile_lyric_elastic_${_lyricContentRevision}_$index',
                                ),
                                index: index,
                                pulse: _elasticPulse,
                                child: item,
                              );
                            }
                            return item;
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
            lyrics = Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: AnimatedOpacity(
                    key: const ValueKey('mobile_lyrics_browse_highlight'),
                    opacity: _browseHighlightVisible ? 1 : 0,
                    duration: mobileLyricsBrowseMaskRevealDuration,
                    curve: Curves.easeOutCubic,
                    child: IgnorePointer(
                      child: ValueListenableBuilder<_LyricBrowseHighlightFrame>(
                        valueListenable: _browseHighlight,
                        builder: (context, frame, _) =>
                            TweenAnimationBuilder<double>(
                              key: const ValueKey(
                                'mobile_lyrics_browse_highlight_scale',
                              ),
                              tween: Tween<double>(
                                begin: .86,
                                end: _browseHighlightVisible ? 1 : .86,
                              ),
                              duration: mobileLyricsBrowseMaskRevealDuration,
                              curve: Curves.easeOutCubic,
                              builder: (context, scale, _) => CustomPaint(
                                painter: _LyricBrowseHighlightPainter(
                                  frame: frame,
                                  scale: scale,
                                ),
                              ),
                            ),
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: AnimatedSwitcher(
                    duration: mobileLyricsBrowseMaskRevealDuration,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: _isManuallyBrowsing && _browseTargetIndex != null
                        ? KeyedSubtree(
                            key: const ValueKey(
                              'mobile_lyrics_browse_time_visible',
                            ),
                            child:
                                ValueListenableBuilder<
                                  _LyricBrowseHighlightFrame
                                >(
                                  valueListenable: _browseHighlight,
                                  builder: (context, frame, _) {
                                    final entry = frame.entry;
                                    if (entry == null) {
                                      return const SizedBox.shrink();
                                    }
                                    return LyricSeekGuide(
                                      timeLabel: formatMobileLyricsBrowseTime(
                                        widget
                                            .lines[_browseTargetIndex!]
                                            .timestamp,
                                      ),
                                      contentColor:
                                          mobileLyricsBrowseGuideColor,
                                      centerY: entry.top + entry.height / 2,
                                      timeOnLeft:
                                          widget.textAlign == TextAlign.right ||
                                          widget.textAlign == TextAlign.end,
                                    );
                                  },
                                ),
                          )
                        : const SizedBox.expand(
                            key: ValueKey('mobile_lyrics_browse_time_hidden'),
                          ),
                  ),
                ),
                lyrics,
                if (_isManuallyBrowsing &&
                    _browseHighlightVisible &&
                    _browseTargetIndex != null &&
                    widget.onBrowseTargetSelected != null)
                  Positioned.fill(
                    child: ValueListenableBuilder<_LyricBrowseHighlightFrame>(
                      valueListenable: _browseHighlight,
                      builder: (context, frame, _) {
                        final entry = frame.entry;
                        if (entry == null) return const SizedBox.shrink();
                        final hitHeight = _browseHitHeight(entry);
                        final centerY = entry.top + entry.height / 2;
                        return Align(
                          alignment: Alignment.topCenter,
                          child: Transform.translate(
                            offset: Offset(0, centerY - hitHeight / 2),
                            child: SizedBox(
                              key: const ValueKey(
                                'mobile_lyrics_browse_tap_target',
                              ),
                              width: double.infinity,
                              height: hitHeight,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _selectBrowseTarget,
                                child: SizedBox(key: _browseTapTargetRenderKey),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
            lyrics = Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _handleLyricsPointerDown,
              onPointerMove: _handleLyricsPointerMove,
              onPointerUp: _handleLyricsPointerEnd,
              onPointerCancel: _handleLyricsPointerEnd,
              child: lyrics,
            );
            if (widget.edgeFadeEnabled) {
              lyrics = ShaderMask(
                key: const ValueKey('mobile_lyrics_edge_fade'),
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: const [
                    // A wide, symmetric multi-stop ramp removes the visible
                    // dark strip while keeping the fully opaque reading area
                    // away from the playback controls and top chrome.
                    Color(mobileLyricsTopEdgeAlpha << 24),
                    Color(mobileLyricsTopFadeSoftAlpha << 24),
                    Color(mobileLyricsTopFadeMidAlpha << 24),
                    Color(mobileLyricsTopFadeNearAlpha << 24),
                    Colors.black,
                    Colors.black,
                    Color(mobileLyricsBottomFadeNearAlpha << 24),
                    Color(mobileLyricsBottomFadeMidAlpha << 24),
                    Color(mobileLyricsBottomFadeSoftAlpha << 24),
                    Colors.transparent,
                    Colors.transparent,
                  ],
                  stops: mobileLyricsEdgeFadeStops(bounds.height),
                ).createShader(bounds),
                child: lyrics,
              );
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                lyrics,
                if (kDebugMode)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton.filledTonal(
                      visualDensity: VisualDensity.compact,
                      tooltip: '歌词滚动调试信息',
                      icon: Icon(
                        _debugOverlayEnabled
                            ? Icons.bug_report
                            : Icons.bug_report_outlined,
                        size: 18,
                      ),
                      onPressed: () => setState(() {
                        _debugOverlayEnabled = !_debugOverlayEnabled;
                      }),
                    ),
                  ),
                if (kDebugMode && _debugOverlayEnabled)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: IgnorePointer(
                      child: ValueListenableBuilder<_LyricDebugSnapshot>(
                        valueListenable: _debugSnapshot,
                        builder: (context, snapshot, _) =>
                            _LyricDebugPanel(snapshot: snapshot),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
}

class _ElasticLyricLine extends StatefulWidget {
  const _ElasticLyricLine({
    super.key,
    required this.index,
    required this.pulse,
    required this.child,
  });

  final int index;
  final ValueListenable<_LyricElasticPulse> pulse;
  final Widget child;

  @override
  State<_ElasticLyricLine> createState() => _ElasticLyricLineState();
}

class _ElasticLyricLineState extends State<_ElasticLyricLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
  );
  Timer? _delayTimer;
  int _lastPulseId = 0;
  double _pendingDurationSeconds = 1.5;

  @override
  void initState() {
    super.initState();
    widget.pulse.addListener(_handlePulse);
  }

  @override
  void didUpdateWidget(covariant _ElasticLyricLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pulse == widget.pulse) return;
    oldWidget.pulse.removeListener(_handlePulse);
    widget.pulse.addListener(_handlePulse);
  }

  void _handlePulse() {
    final pulse = widget.pulse.value;
    if (pulse.id == _lastPulseId) return;
    _lastPulseId = pulse.id;
    _delayTimer?.cancel();
    _controller.stop();

    if (pulse.displacement.abs() < .35) {
      _controller.value = 0;
      return;
    }

    _controller.value = pulse.displacement;
    _pendingDurationSeconds = pulse.lineDurationSeconds;
    final distance = (widget.index - pulse.anchorIndex).abs();
    if (distance > 4) {
      // Cached rows outside the visible elastic wave must not keep their own
      // spring ticker alive. They cannot be seen, but collectively add raster
      // and scheduling pressure when glow is enabled.
      _controller.value = 0;
      return;
    }
    final delayStep = (_pendingDurationSeconds * 38).clamp(10.0, 44.0);
    final delay = Duration(milliseconds: (distance * delayStep).round());
    if (delay == Duration.zero) {
      _startSpring();
    } else {
      _delayTimer = Timer(delay, _startSpring);
    }
  }

  void _startSpring() {
    if (!mounted) return;
    final durationSquared = _pendingDurationSeconds * _pendingDurationSeconds;
    final stiffness = (210 / (durationSquared > 0 ? durationSquared : 1))
        .clamp(105.0, 210.0)
        .toDouble();
    final durationProgress = (_pendingDurationSeconds / 1.5)
        .clamp(0.0, 1.0)
        .toDouble();
    final spring = SpringDescription.withDampingRatio(
      mass: 1,
      stiffness: stiffness,
      ratio: .74 - .10 * durationProgress,
    );
    _controller.animateWith(
      SpringSimulation(
        spring,
        _controller.value,
        0,
        0,
        tolerance: const Tolerance(distance: .5, velocity: .1),
      ),
    );
  }

  @override
  void dispose() {
    widget.pulse.removeListener(_handlePulse);
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) => Transform.translate(
      key: ValueKey('mobile_lyric_elastic_transform_${widget.index}'),
      offset: Offset(0, _controller.value),
      child: child,
    ),
  );
}

class _LyricBrowseHighlightFrame {
  const _LyricBrowseHighlightFrame({this.entry});

  final _LyricBrowseHighlightEntry? entry;
}

class _LyricBrowseHighlightEntry {
  const _LyricBrowseHighlightEntry({required this.top, required this.height});

  final double top;
  final double height;
}

class _LyricBrowseHighlightPainter extends CustomPainter {
  const _LyricBrowseHighlightPainter({
    required this.frame,
    required this.scale,
  });

  final _LyricBrowseHighlightFrame frame;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final entry = frame.entry;
    if (entry == null || size.width <= 0) return;
    final targetRect = Rect.fromLTWH(
      0,
      entry.top + 2,
      size.width,
      (entry.height - 4).clamp(1.0, double.infinity),
    );
    final rect = Rect.fromCenter(
      center: targetRect.center,
      width: targetRect.width * scale,
      height: targetRect.height * scale,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      Paint()
        ..style = PaintingStyle.fill
        ..color = mobileLyricsBrowseMaskColor,
    );
  }

  @override
  bool shouldRepaint(covariant _LyricBrowseHighlightPainter oldDelegate) =>
      !identical(frame, oldDelegate.frame) || oldDelegate.scale != scale;
}

class _LyricLineItem extends StatelessWidget {
  const _LyricLineItem({
    super.key,
    required this.line,
    required this.active,
    required this.distance,
    required this.relativeDistance,
    required this.height,
    required this.fontSize,
    required this.fontFamily,
    required this.activeColor,
    required this.styleIdentity,
    required this.fontWeight,
    required this.glowEnabled,
    required this.glowRadius,
    required this.brightForeground,
    required this.textAlign,
    required this.lineBlurEnabled,
    required this.highlightActiveLine,
    required this.karaokeLyricsEnabled,
    required this.karaokeLyricsMode,
    required this.nextTimestamp,
    required this.browseHighlighted,
    required this.lineBlurSuppressed,
    required this.regularScrollMode,
    required this.isPlaying,
    required this.normalExit,
    required this.playbackRate,
    required this.playbackRateListenable,
    required this.actualPlaybackListenable,
    required this.seekPositionListenable,
    required this.position,
    required this.positionListenable,
  });

  final LyricLine line;
  final bool active;
  final int distance;
  final int relativeDistance;
  final double height;
  final double fontSize;
  final String? fontFamily;
  final Color? activeColor;
  final Object? styleIdentity;
  final FontWeight fontWeight;
  final bool glowEnabled;
  final double glowRadius;
  final bool brightForeground;
  final TextAlign textAlign;
  final bool lineBlurEnabled;
  final bool highlightActiveLine;
  final bool karaokeLyricsEnabled;
  final KaraokeLyricsMode karaokeLyricsMode;
  final Duration? nextTimestamp;
  final bool browseHighlighted;
  final bool lineBlurSuppressed;
  final bool regularScrollMode;
  final bool isPlaying;
  final bool normalExit;
  final double playbackRate;
  final ValueListenable<double>? playbackRateListenable;
  final ValueListenable<bool>? actualPlaybackListenable;
  final ValueListenable<Duration?>? seekPositionListenable;
  final Duration position;
  final ValueListenable<Duration>? positionListenable;

  double get _opacity => switch (distance) {
    0 => 1,
    1 => .68,
    2 => .52,
    3 => .40,
    _ => .32,
  };

  double get _scale => switch (distance) {
    0 => mobileLyricsActiveScale,
    _ => 1,
  };

  Offset get _lyricLineOffset => !lineBlurSuppressed && !browseHighlighted
      ? Offset(0, mobileLyricsKaraokeLineShift(relativeDistance))
      : Offset.zero;

  Alignment get _alignment => switch (textAlign) {
    TextAlign.left || TextAlign.start => Alignment.centerLeft,
    TextAlign.right || TextAlign.end => Alignment.centerRight,
    _ => Alignment.center,
  };

  double get _blurSigma {
    if (!lineBlurEnabled || lineBlurSuppressed || active || distance <= 0) {
      return 0;
    }
    return mobileLyricBlurSigmaForDistance(distance);
  }

  @override
  Widget build(BuildContext context) {
    final hasTimedKaraoke = hasUsableKaraokeTiming(line);
    final karaokeWillAnimate =
        karaokeLyricsEnabled &&
        (hasTimedKaraoke || karaokeLyricsMode == KaraokeLyricsMode.all);
    final effectiveLine =
        karaokeWillAnimate &&
            karaokeLyricsMode == KaraokeLyricsMode.all &&
            !hasTimedKaraoke
        ? synthesizeKaraokeTiming(line, nextTimestamp: nextTimestamp)
        : line;
    final darkForeground =
        brightForeground || Theme.of(context).brightness == Brightness.dark;
    final inactiveBase = darkForeground
        ? Colors.white
        : const Color(0xFF757575);
    final karaokeUnplayedColor = darkForeground
        ? Colors.white.withValues(alpha: .36)
        : const Color(0xFF757575).withValues(alpha: .68);
    // Karaoke uses one stable visual state for every non-playing line.
    final inactiveColor = karaokeLyricsEnabled
        ? karaokeUnplayedColor
        : inactiveBase.withValues(alpha: _opacity);
    final resolvedActiveColor = highlightActiveLine
        ? Colors.white
        : activeColor ?? Theme.of(context).colorScheme.primary;
    final browseHighlightColor = highlightActiveLine
        ? Colors.white
        : resolvedActiveColor;
    final lineColor = browseHighlighted
        ? browseHighlightColor
        : active
        ? resolvedActiveColor
        : inactiveColor;
    final style = DefaultTextStyle.of(context).style.copyWith(
      fontFamily: fontFamily,
      fontSize: fontSize,
      height: 1.2,
      fontWeight: fontWeight,
      color: lineColor,
      shadows: null,
    );
    // Keep the expensive blurred glyph raster independent from the line's
    // distance opacity. As the active line advances, most visible lyrics only
    // change alpha; applying that with a composited Opacity layer lets their
    // cached glow textures survive instead of repainting every blur.
    final glowStyle = style.copyWith(color: Colors.transparent);
    final glowColor = lineColor.withValues(alpha: .30);
    Widget buildLyric(Duration currentPosition) {
      if (line.isInterlude) {
        return Align(
          alignment: _alignment,
          child: InterludeAnimationWidget(
            isCurrent: active,
            baseColor: inactiveColor,
            highlightColor: resolvedActiveColor.withValues(alpha: .9),
            startTime: line.timestamp,
            interludeDuration: line.interludeDuration ?? Duration.zero,
            currentTime: currentPosition,
            isPlaying: isPlaying,
          ),
        );
      }
      // Karaoke has priority over whole-line highlighting when explicitly
      // enabled. Previously highlight mode returned here first, which made the
      // new karaoke switch appear to do nothing for users who had kept the
      // older highlight option enabled.
      if (!karaokeWillAnimate || browseHighlighted) {
        return Text(line.texts.join('\n'), textAlign: textAlign);
      }
      final animatedPosition = active
          ? currentPosition
          : line.timestamp - const Duration(milliseconds: 120);
      return _KaraokeLyricText(
        cacheIdentity: (line, nextTimestamp, karaokeLyricsMode),
        line: effectiveLine,
        position: animatedPosition,
        positionListenable: active ? positionListenable : null,
        isPlaying: active && isPlaying,
        normalExit: normalExit,
        playbackRate: playbackRate,
        playbackRateListenable: playbackRateListenable,
        actualPlaybackListenable: actualPlaybackListenable,
        seekPositionListenable: seekPositionListenable,
        playedColor: active ? style.color! : karaokeUnplayedColor,
        unplayedColor: karaokeUnplayedColor,
        textAlign: textAlign,
      );
    }

    // Karaoke listens directly from its painter, so playback ticks repaint
    // only its cached custom-paint surface and never rebuild the lyric row.
    final followsPlaybackPosition =
        active && positionListenable != null && line.isInterlude;
    final lyric = followsPlaybackPosition
        ? ValueListenableBuilder<Duration>(
            valueListenable: positionListenable!,
            builder: (context, currentPosition, _) =>
                buildLyric(currentPosition),
          )
        : buildLyric(position);
    final lyricWithGlow = glowEnabled && !line.isInterlude
        ? Stack(
            fit: StackFit.passthrough,
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Opacity(
                  key: const ValueKey('mobile_lyric_glow_opacity'),
                  opacity: lineColor.a,
                  child: RepaintBoundary(
                    child: IgnorePointer(
                      child: CustomPaint(
                        key: const ValueKey('mobile_lyric_glow_layer'),
                        isComplex: true,
                        willChange: false,
                        painter: MobileLyricGlowPainter(
                          text: line.texts.join('\n'),
                          style: glowStyle,
                          color: glowColor,
                          blurRadius: glowRadius,
                          textAlign: textAlign,
                          textDirection: Directionality.of(context),
                          textScaler: MediaQuery.textScalerOf(context),
                          locale: Localizations.maybeLocaleOf(context),
                          primaryRowOnly: karaokeWillAnimate,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              lyric,
            ],
          )
        : lyric;
    final sigma = _blurSigma;
    final lyricPaintLayer = Padding(
      key: const ValueKey('mobile_lyric_filter_safe_area'),
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: lyricWithGlow,
    );
    final effectiveLyric = lineBlurEnabled
        ? _AnimatedLyricBlur(
            sigma: sigma,
            duration: regularScrollMode
                ? mobileLyricsDefaultScrollTransitionDuration
                : mobileLyricsFocusTransitionDuration,
            child: RepaintBoundary(child: lyricPaintLayer),
          )
        : lyricPaintLayer;
    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: mobileLyricsHorizontalInset(textAlign),
        ),
        child: AnimatedSlide(
          key: const ValueKey('mobile_lyric_karaoke_line_shift'),
          offset: _lyricLineOffset,
          duration: mobileLyricsKaraokeLineShiftDuration,
          curve: mobileLyricsFocusTransitionCurve,
          child: FractionallySizedBox(
            key: const ValueKey('mobile_lyric_scale_safe_content'),
            widthFactor: 1 / mobileLyricsActiveScale,
            heightFactor: 1 / mobileLyricsActiveScale,
            alignment: _alignment,
            child: AnimatedScale(
              scale: _scale,
              duration: regularScrollMode
                  ? mobileLyricsDefaultScrollTransitionDuration
                  : active
                  ? const Duration(milliseconds: 220)
                  : const Duration(milliseconds: 280),
              curve: regularScrollMode
                  ? mobileLyricsFocusTransitionCurve
                  : active
                  ? Curves.easeOutCubic
                  : const Cubic(.16, 1, .3, 1),
              alignment: _alignment,
              // Keep the expensive glyph and glow raster below the transform.
              // The scale-safe parent reserves the transformed paint bounds, so
              // sliver culling cannot remove a still-visible departing line.
              child: RepaintBoundary(
                key: const ValueKey('mobile_lyric_scaled_paint'),
                child: AnimatedDefaultTextStyle(
                  key: ValueKey(styleIdentity),
                  duration: regularScrollMode
                      ? mobileLyricsDefaultScrollTransitionDuration
                      : active
                      ? const Duration(milliseconds: 210)
                      : const Duration(milliseconds: 280),
                  curve: regularScrollMode
                      ? mobileLyricsFocusTransitionCurve
                      : active
                      ? Curves.easeOutCubic
                      : const Cubic(.16, 1, .3, 1),
                  style: style,
                  textAlign: textAlign,
                  child: Align(
                    alignment: _alignment,
                    child: SizedBox(
                      width: double.infinity,
                      child: effectiveLyric,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedLyricBlur extends ImplicitlyAnimatedWidget {
  const _AnimatedLyricBlur({
    required this.sigma,
    required super.duration,
    required this.child,
  }) : super(curve: mobileLyricsFocusTransitionCurve);

  final double sigma;
  final Widget child;

  @override
  ImplicitlyAnimatedWidgetState<_AnimatedLyricBlur> createState() =>
      _AnimatedLyricBlurState();
}

class _AnimatedLyricBlurState
    extends AnimatedWidgetBaseState<_AnimatedLyricBlur> {
  Tween<double>? _sigma;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _sigma =
        visitor(
              _sigma,
              widget.sigma,
              (value) => Tween<double>(begin: value as double),
            )
            as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) {
    final sigma = _sigma?.evaluate(animation) ?? widget.sigma;
    return ImageFiltered(
      key: const ValueKey('mobile_lyric_blur_filter'),
      enabled: sigma > .01,
      imageFilter: _cachedLyricBlur(sigma),
      child: widget.child,
    );
  }
}

/// Paints a line's glow independently from its animated foreground text.
///
/// Keeping this painter below its own repaint boundary lets scrolling and
/// elastic transforms reuse the rasterized blur instead of rebuilding a text
/// shadow on every foreground color or karaoke-progress frame.
class MobileLyricGlowPainter extends CustomPainter {
  const MobileLyricGlowPainter({
    required this.text,
    required this.style,
    required this.color,
    required this.blurRadius,
    required this.textAlign,
    required this.textDirection,
    required this.textScaler,
    required this.locale,
    this.primaryRowOnly = false,
  });

  final String text;
  final TextStyle style;
  final Color color;
  final double blurRadius;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final Locale? locale;
  final bool primaryRowOnly;

  @override
  void paint(Canvas canvas, Size size) {
    if (text.isEmpty || size.isEmpty || color.a <= 0 || blurRadius <= 0) {
      return;
    }
    final baseStyle = style.copyWith(color: Colors.transparent, shadows: null);
    final glowingStyle = baseStyle.copyWith(
      shadows: [Shadow(color: color, blurRadius: blurRadius)],
    );
    final firstNewline = text.indexOf('\n');
    final content = primaryRowOnly && firstNewline >= 0
        ? TextSpan(
            style: baseStyle,
            children: [
              TextSpan(
                text: text.substring(0, firstNewline),
                style: glowingStyle,
              ),
              TextSpan(text: text.substring(firstNewline), style: baseStyle),
            ],
          )
        : TextSpan(text: text, style: glowingStyle);
    final painter = TextPainter(
      text: content,
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
    )..layout(maxWidth: size.width);
    painter.paint(canvas, Offset(0, (size.height - painter.height) / 2));
  }

  @override
  bool shouldRepaint(covariant MobileLyricGlowPainter oldDelegate) =>
      oldDelegate.text != text ||
      oldDelegate.style != style ||
      oldDelegate.color != color ||
      oldDelegate.blurRadius != blurRadius ||
      oldDelegate.textAlign != textAlign ||
      oldDelegate.textDirection != textDirection ||
      oldDelegate.textScaler != textScaler ||
      oldDelegate.locale != locale ||
      oldDelegate.primaryRowOnly != primaryRowOnly;
}

class _LyricDebugSnapshot {
  const _LyricDebugSnapshot({
    this.currentIndex = -1,
    this.targetOffset = 0,
    this.currentOffset = 0,
    this.velocity = 0,
    this.userScrolling = false,
    this.fps = 0,
    this.frameTimeMs = 0,
    this.recompositionCount = 0,
  });

  final int currentIndex;
  final double targetOffset;
  final double currentOffset;
  final double velocity;
  final bool userScrolling;
  final double fps;
  final double frameTimeMs;
  final int recompositionCount;
}

class _LyricDebugPanel extends StatelessWidget {
  const _LyricDebugPanel({required this.snapshot});

  final _LyricDebugSnapshot snapshot;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .78),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        child: Text(
          'Index ${snapshot.currentIndex}\n'
          'Target ${snapshot.targetOffset.toStringAsFixed(1)}\n'
          'Offset ${snapshot.currentOffset.toStringAsFixed(1)}\n'
          'Velocity ${snapshot.velocity.toStringAsFixed(1)} px/s\n'
          'User ${snapshot.userScrolling}\n'
          'FPS ${snapshot.fps.toStringAsFixed(1)}\n'
          'Frame ${snapshot.frameTimeMs.toStringAsFixed(2)} ms\n'
          'Builds ${snapshot.recompositionCount}',
        ),
      ),
    ),
  );
}

class _KaraokeLyricText extends StatefulWidget {
  const _KaraokeLyricText({
    required this.cacheIdentity,
    required this.line,
    required this.position,
    required this.positionListenable,
    required this.isPlaying,
    required this.normalExit,
    required this.playbackRate,
    required this.playbackRateListenable,
    required this.actualPlaybackListenable,
    required this.seekPositionListenable,
    required this.playedColor,
    required this.unplayedColor,
    required this.textAlign,
  });

  final Object cacheIdentity;
  final LyricLine line;
  final Duration position;
  final ValueListenable<Duration>? positionListenable;
  final bool isPlaying;
  final bool normalExit;
  final double playbackRate;
  final ValueListenable<double>? playbackRateListenable;
  final ValueListenable<bool>? actualPlaybackListenable;
  final ValueListenable<Duration?>? seekPositionListenable;
  final Color playedColor;
  final Color unplayedColor;
  final TextAlign textAlign;

  @override
  State<_KaraokeLyricText> createState() => _KaraokeLyricTextState();
}

class _KaraokeLyricTextState extends State<_KaraokeLyricText>
    with TickerProviderStateMixin {
  late String _text;
  late List<_KaraokeTokenRange> _ranges;
  late final Ticker _positionTicker;
  late final KaraokeMediaClock _clock;
  late final AnimationController _exitController;
  bool _isExiting = false;
  double _measureWidth = -1;
  double _measuredHeight = 0;
  TextStyle? _measureStyle;
  TextAlign? _measureTextAlign;
  TextDirection? _measureTextDirection;
  TextScaler? _measureTextScaler;
  Locale? _measureLocale;

  @override
  void initState() {
    super.initState();
    final initialPosition = widget.positionListenable?.value ?? widget.position;
    _clock = KaraokeMediaClock(initialPosition, rate: _playbackRate);
    _exitController =
        AnimationController(
          vsync: this,
          duration: karaokeDefaultMotion.exitDuration,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            _isExiting = false;
            _clock.seek(
              widget.line.timestamp - const Duration(milliseconds: 120),
            );
            _exitController.value = 0;
          }
        });
    _positionTicker = createTicker(_clock.tick);
    widget.positionListenable?.addListener(_readSourcePosition);
    widget.actualPlaybackListenable?.addListener(_syncTickerState);
    widget.playbackRateListenable?.addListener(_readPlaybackRate);
    widget.seekPositionListenable?.addListener(_readExplicitSeek);
    _rebuildCache();
    _syncTickerState();
  }

  @override
  void didUpdateWidget(covariant _KaraokeLyricText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionListenable != widget.positionListenable) {
      oldWidget.positionListenable?.removeListener(_readSourcePosition);
      widget.positionListenable?.addListener(_readSourcePosition);
      if (oldWidget.positionListenable != null &&
          widget.positionListenable == null &&
          widget.normalExit &&
          oldWidget.cacheIdentity == widget.cacheIdentity) {
        _isExiting = true;
        _exitController.forward(from: 0);
      } else {
        _isExiting = false;
        _exitController.stop();
        _exitController.value = 0;
        _resetVisualPosition();
      }
    } else if (widget.positionListenable == null &&
        oldWidget.position != widget.position) {
      _resetVisualPosition();
    }
    if (oldWidget.actualPlaybackListenable != widget.actualPlaybackListenable) {
      oldWidget.actualPlaybackListenable?.removeListener(_syncTickerState);
      widget.actualPlaybackListenable?.addListener(_syncTickerState);
      _syncTickerState();
    }
    if (oldWidget.playbackRateListenable != widget.playbackRateListenable) {
      oldWidget.playbackRateListenable?.removeListener(_readPlaybackRate);
      widget.playbackRateListenable?.addListener(_readPlaybackRate);
      _readPlaybackRate();
    }
    if (oldWidget.seekPositionListenable != widget.seekPositionListenable) {
      oldWidget.seekPositionListenable?.removeListener(_readExplicitSeek);
      widget.seekPositionListenable?.addListener(_readExplicitSeek);
    }
    if (oldWidget.playbackRate != widget.playbackRate) {
      _readPlaybackRate();
    }
    if (oldWidget.cacheIdentity != widget.cacheIdentity) {
      _isExiting = false;
      _exitController.stop();
      _exitController.value = 0;
      _rebuildCache();
      _resetVisualPosition();
    }
    if (oldWidget.isPlaying != widget.isPlaying) _syncTickerState();
  }

  @override
  void dispose() {
    widget.positionListenable?.removeListener(_readSourcePosition);
    widget.actualPlaybackListenable?.removeListener(_syncTickerState);
    widget.playbackRateListenable?.removeListener(_readPlaybackRate);
    widget.seekPositionListenable?.removeListener(_readExplicitSeek);
    _positionTicker.dispose();
    _exitController.dispose();
    _clock.dispose();
    super.dispose();
  }

  Duration get _sourcePosition =>
      widget.positionListenable?.value ?? widget.position;

  double get _playbackRate =>
      widget.playbackRateListenable?.value ?? widget.playbackRate;

  void _readPlaybackRate() {
    _clock.changeRate(_playbackRate, _sourcePosition);
  }

  void _readExplicitSeek() {
    final target = widget.seekPositionListenable?.value;
    if (target == null) return;
    _clock.seek(target);
  }

  void _resetVisualPosition() => _clock.seek(_sourcePosition);

  void _readSourcePosition() => _clock.readSource(_sourcePosition);

  void _syncTickerState() {
    if (_isExiting) {
      if (_positionTicker.isActive) _positionTicker.stop();
      _clock.freeze();
      return;
    }
    // A static position is primarily used by previews and tests. Only keep a
    // frame clock alive when a real playback position source can correct it.
    if (widget.isPlaying &&
        (widget.actualPlaybackListenable?.value ?? true) &&
        widget.positionListenable != null) {
      if (!_positionTicker.isActive) {
        _clock.setRunning(true, _sourcePosition);
        _positionTicker.start();
      }
      return;
    }
    if (_positionTicker.isActive) _positionTicker.stop();
    _clock.setRunning(false, _sourcePosition);
  }

  void _rebuildCache() {
    _text = widget.line.texts.join('\n');
    _ranges = <_KaraokeTokenRange>[];
    _measureWidth = -1;
    final tokenRows = widget.line.tokens ?? const <List<LyricToken>>[];
    var rowOffset = 0;
    for (var rowIndex = 0; rowIndex < widget.line.texts.length; rowIndex++) {
      final rowText = widget.line.texts[rowIndex];
      var searchOffset = 0;
      if (karaokeRowCanHighlight(rowIndex) && rowIndex < tokenRows.length) {
        for (final token in tokenRows[rowIndex]) {
          if (token.text == '\u200B') continue;
          var localStart = rowText.indexOf(token.text, searchOffset);
          if (localStart < 0 &&
              searchOffset + token.text.length <= rowText.length) {
            localStart = searchOffset;
          }
          if (localStart < 0) continue;
          final localEnd = (localStart + token.text.length).clamp(
            localStart,
            rowText.length,
          );
          final visibleBounds = karaokeVisibleTokenBounds(token.text);
          if (visibleBounds == null) {
            searchOffset = localEnd;
            continue;
          }
          _ranges.add(
            _KaraokeTokenRange(
              token: token,
              start: rowOffset + localStart + visibleBounds.start,
              end: rowOffset + localStart + visibleBounds.end,
            ),
          );
          searchOffset = localEnd;
        }
      }
      rowOffset +=
          rowText.length + (rowIndex + 1 < widget.line.texts.length ? 1 : 0);
    }
  }

  double _measureHeight({
    required double width,
    required TextStyle style,
    required TextAlign textAlign,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required Locale? locale,
  }) {
    final cachedStyle = _measureStyle;
    final styleNeedsLayout =
        cachedStyle == null ||
        style.compareTo(cachedStyle) == RenderComparison.layout;
    final unchanged =
        (_measureWidth - width).abs() < .1 &&
        !styleNeedsLayout &&
        _measureTextAlign == textAlign &&
        _measureTextDirection == textDirection &&
        _measureTextScaler == textScaler &&
        _measureLocale == locale;
    if (unchanged) return _measuredHeight;
    final measure = TextPainter(
      text: TextSpan(text: _text, style: style),
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
    )..layout(maxWidth: width);
    _measureWidth = width;
    _measuredHeight = measure.height;
    _measureStyle = style;
    _measureTextAlign = textAlign;
    _measureTextDirection = textDirection;
    _measureTextScaler = textScaler;
    _measureLocale = locale;
    return _measuredHeight;
  }

  @override
  Widget build(BuildContext context) {
    final inheritedStyle = DefaultTextStyle.of(context).style;
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final measuredHeight = _measureHeight(
          width: maxWidth,
          style: inheritedStyle,
          textAlign: widget.textAlign,
          textDirection: textDirection,
          textScaler: textScaler,
          locale: locale,
        );
        return Semantics(
          label: _text,
          child: SizedBox(
            width: maxWidth,
            height: measuredHeight,
            child: CustomPaint(
              key: const ValueKey('mobile_karaoke_single_pass_paint'),
              painter: _SinglePassKaraokePainter(
                text: _text,
                ranges: _ranges,
                position: _clock.value,
                positionListenable: _clock,
                exitAnimation: _exitController,
                isExiting: _isExiting,
                playedStyle: inheritedStyle.copyWith(color: widget.playedColor),
                unplayedStyle: inheritedStyle.copyWith(
                  color: widget.unplayedColor,
                ),
                textAlign: widget.textAlign,
                textDirection: textDirection,
                textScaler: textScaler,
                locale: locale,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _KaraokePaintRange {
  const _KaraokePaintRange({required this.start, required this.end});

  final int start;
  final int end;
}

class _KaraokeTokenRange extends _KaraokePaintRange {
  const _KaraokeTokenRange({
    required this.token,
    required super.start,
    required super.end,
  });

  final LyricToken token;
}

class _KaraokeGlyphRange extends _KaraokePaintRange {
  const _KaraokeGlyphRange({
    required this.tokenRange,
    required this.index,
    required this.count,
    required super.start,
    required super.end,
  });

  final _KaraokeTokenRange tokenRange;
  final int index;
  final int count;
}

// One-release internal A/B escape hatch. The old pure helpers remain for
// comparison tests; the mobile painter uses the new plan by default.
const bool _useLegacyKaraokeMotion = false;

// Debug-only instrumentation for verifying that animation repaints reuse the
// shaped text and glyph geometry. It is not incremented in release builds.
int debugKaraokeLayoutBuildCount = 0;

class _SinglePassKaraokePainter extends CustomPainter {
  _SinglePassKaraokePainter({
    required this.text,
    required this.ranges,
    required this.position,
    required this.positionListenable,
    required this.exitAnimation,
    required this.isExiting,
    required this.playedStyle,
    required this.unplayedStyle,
    required this.textAlign,
    required this.textDirection,
    required this.textScaler,
    required this.locale,
  }) : super(repaint: Listenable.merge([positionListenable, exitAnimation]));

  final String text;
  final List<_KaraokeTokenRange> ranges;
  final Duration position;
  final ValueListenable<Duration>? positionListenable;
  final Animation<double> exitAnimation;
  final bool isExiting;
  final TextStyle playedStyle;
  final TextStyle unplayedStyle;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final Locale? locale;
  TextPainter? _layoutPainter;
  TextPainter? _staticPainter;
  TextPainter? _completedPainter;
  TextPainter? _futurePainter;
  List<int> _paintGroups = const [];
  double _layoutWidth = -1;
  double _liftReferenceHeight = 0;
  double _lineCadenceUs = 80000;
  List<_KaraokeTokenRange> _drawableRanges = const [];
  List<_KaraokeGlyphRange> _orderedGlyphs = const [];
  List<double> _glyphLiftStartTimesUs = const [];
  List<KaraokeGlyphTiming> _glyphTimings = const [];
  List<double> _highlightFactorBuffer = const [];
  List<double> _glyphCadencesUs = const [];
  List<bool> _breakBeforeGlyph = const [];
  List<double?> _nextTokenStarts = const [];
  List<int> _glyphTokenIndices = const [];
  List<int> _tokenGlyphStarts = const [];
  List<double> _rawProgressBuffer = const [];
  List<double> _ownFactorBuffer = const [];
  List<double> _liftFactorBuffer = const [];
  List<int> _groupBuffer = const [];
  List<double> _glyphLiftScratch = const [];
  List<double> _glyphProgressScratch = const [];
  final List<_KaraokeTokenRange> _completedBuffer = [];
  final List<_KaraokeTokenRange> _futureBuffer = [];
  Map<_KaraokeTokenRange, double> _leadInByToken = const {};
  Map<_KaraokeTokenRange, List<_KaraokeGlyphRange>> _glyphsByToken = const {};
  Map<_KaraokeGlyphRange, List<ui.TextBox>> _glyphBoxes = const {};
  Map<_KaraokeTokenRange, Rect> _tokenBounds = const {};
  Map<_KaraokeTokenRange, TextDirection> _tokenDirections = const {};
  Map<_KaraokeGlyphRange, TextPainter> _unplayedGlyphPainters = {};
  Map<_KaraokeGlyphRange, TextPainter> _maskGlyphPainters = {};
  Map<_KaraokeGlyphRange, TextPainter> _playedGlyphPainters = {};

  Duration get _currentPosition => positionListenable?.value ?? position;

  TextPainter _layout(TextStyle style, double width) => TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: textAlign,
    textDirection: textDirection,
    textScaler: textScaler,
    locale: locale,
  )..layout(maxWidth: width);

  TextPainter _layoutSelected(
    Iterable<_KaraokePaintRange> selected,
    TextStyle style,
    double width,
  ) {
    final visibleRanges = selected.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final transparentStyle = style.copyWith(
      color: Colors.transparent,
      shadows: null,
    );
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final range in visibleRanges) {
      final start = math.max(cursor, range.start);
      final end = math.min(text.length, range.end);
      if (start > cursor) {
        spans.add(
          TextSpan(
            text: text.substring(cursor, start),
            style: transparentStyle,
          ),
        );
      }
      if (end > start) {
        spans.add(TextSpan(text: text.substring(start, end)));
        cursor = end;
      }
    }
    if (cursor < text.length) {
      spans.add(
        TextSpan(text: text.substring(cursor), style: transparentStyle),
      );
    }
    return TextPainter(
      text: TextSpan(style: style, children: spans),
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
    )..layout(maxWidth: width);
  }

  TextPainter _layoutWithoutSelected(
    Iterable<_KaraokePaintRange> hidden,
    double width,
  ) {
    final hiddenRanges = hidden.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final transparentStyle = unplayedStyle.copyWith(
      color: Colors.transparent,
      shadows: null,
    );
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final range in hiddenRanges) {
      final start = math.max(cursor, range.start);
      final end = math.min(text.length, range.end);
      if (start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, start)));
      }
      if (end > start) {
        spans.add(
          TextSpan(text: text.substring(start, end), style: transparentStyle),
        );
        cursor = end;
      }
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return TextPainter(
      text: TextSpan(style: unplayedStyle, children: spans),
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
    )..layout(maxWidth: width);
  }

  void _ensureLayout(double width) {
    if (_layoutWidth == width && _layoutPainter != null) return;
    assert(() {
      debugKaraokeLayoutBuildCount++;
      return true;
    }());
    _layoutWidth = width;
    _layoutPainter = _layout(unplayedStyle, width);
    _liftReferenceHeight = _layoutPainter!.preferredLineHeight;
    final glyphsByToken = <_KaraokeTokenRange, List<_KaraokeGlyphRange>>{};
    final glyphBoxes = <_KaraokeGlyphRange, List<ui.TextBox>>{};
    final tokenBounds = <_KaraokeTokenRange, Rect>{};
    final tokenDirections = <_KaraokeTokenRange, TextDirection>{};
    for (final range in ranges) {
      if (range.start < 0 ||
          range.end > text.length ||
          range.end <= range.start) {
        continue;
      }
      final offsets = karaokeGraphemeRanges(
        text.substring(range.start, range.end),
        startOffset: range.start,
      );
      if (offsets.isEmpty) continue;
      final glyphs = <_KaraokeGlyphRange>[];
      var allGlyphsDrawable = true;
      for (var index = 0; index < offsets.length; index++) {
        final offset = offsets[index];
        final glyph = _KaraokeGlyphRange(
          tokenRange: range,
          index: index,
          count: offsets.length,
          start: offset.start,
          end: offset.end,
        );
        final selectionBoxes = _layoutPainter!
            .getBoxesForSelection(
              TextSelection(baseOffset: glyph.start, extentOffset: glyph.end),
            )
            .where((box) {
              final rect = box.toRect();
              return rect.width > 0 && rect.height > 0;
            })
            .toList(growable: false);
        if (selectionBoxes.isEmpty) {
          allGlyphsDrawable = false;
          break;
        }
        glyphs.add(glyph);
        glyphBoxes[glyph] = selectionBoxes;
      }
      // If even one grapheme cannot be mapped by the platform shaper, leave
      // the complete token in the static fallback. This avoids losing half a
      // ligature or emoji while still animating all ordinary text per glyph.
      if (allGlyphsDrawable && glyphs.length == offsets.length) {
        glyphsByToken[range] = glyphs;
        final allBoxes = glyphs
            .expand((glyph) => glyphBoxes[glyph] ?? const <ui.TextBox>[])
            .toList(growable: false);
        var bounds = allBoxes.first.toRect();
        for (final box in allBoxes.skip(1)) {
          bounds = bounds.expandToInclude(box.toRect());
        }
        tokenBounds[range] = bounds;
        tokenDirections[range] = allBoxes.first.direction;
      } else {
        for (final glyph in glyphs) {
          glyphBoxes.remove(glyph);
        }
      }
    }
    _glyphsByToken = glyphsByToken;
    _glyphBoxes = glyphBoxes;
    _tokenBounds = tokenBounds;
    _tokenDirections = tokenDirections;
    _drawableRanges = glyphsByToken.keys.toList(growable: false);
    _orderedGlyphs = _drawableRanges
        .expand((range) => glyphsByToken[range] ?? const <_KaraokeGlyphRange>[])
        .toList(growable: false);
    _tokenGlyphStarts = <int>[];
    _glyphTokenIndices = <int>[];
    _breakBeforeGlyph = <bool>[];
    _nextTokenStarts = <double?>[];
    var glyphOffset = 0;
    for (
      var tokenIndex = 0;
      tokenIndex < _drawableRanges.length;
      tokenIndex++
    ) {
      final range = _drawableRanges[tokenIndex];
      final glyphs = glyphsByToken[range]!;
      _tokenGlyphStarts.add(glyphOffset);
      final breaks =
          tokenIndex > 0 &&
          !karaokeTokensShareLiftChain(
            _drawableRanges[tokenIndex - 1].token,
            range.token,
          );
      for (var local = 0; local < glyphs.length; local++) {
        _glyphTokenIndices.add(tokenIndex);
        _breakBeforeGlyph.add(local == 0 && breaks);
        final nextToken = tokenIndex + 1 < _drawableRanges.length
            ? _drawableRanges[tokenIndex + 1].token
            : null;
        _nextTokenStarts.add(
          local == glyphs.length - 1 &&
                  nextToken != null &&
                  range.token.end == nextToken.start
              ? karaokeNextTokenStartProgress(range.token, nextToken)
              : null,
        );
        glyphOffset++;
      }
    }
    _lineCadenceUs = karaokeLineGlyphCadenceUs(
      _drawableRanges.map((range) => range.token),
      _orderedGlyphs.length,
    );
    _glyphCadencesUs = karaokeLocalGlyphCadencesUs(
      [for (final range in _drawableRanges) range.token],
      [for (final range in _drawableRanges) glyphsByToken[range]!.length],
    );
    _glyphTimings = List<KaraokeGlyphTiming>.generate(_orderedGlyphs.length, (
      index,
    ) {
      final glyph = _orderedGlyphs[index];
      final token = glyph.tokenRange.token;
      final count = glyph.count;
      return KaraokeGlyphTiming.fromToken(
        sourceTokenStartUs: token.start.inMicroseconds,
        sourceTokenEndUs: token.end.inMicroseconds,
        visualTokenStartUs: karaokeVisualTokenStart(token).inMicroseconds,
        highlightStartProgress: karaokeGlyphHighlightStart(glyph.index, count),
        highlightWindowProgress: count <= 1
            ? 1
            : math.min(.48, 1.8 / (count + .8)),
        estimatedCadenceUs: _glyphCadencesUs[index],
      );
    });
    _rawProgressBuffer = List<double>.filled(_drawableRanges.length, 0);
    _highlightFactorBuffer = List<double>.filled(_orderedGlyphs.length, 0);
    _ownFactorBuffer = List<double>.filled(_orderedGlyphs.length, 0);
    _liftFactorBuffer = List<double>.filled(_orderedGlyphs.length, 0);
    _groupBuffer = List<int>.filled(_drawableRanges.length, 0);
    final longestToken = _drawableRanges.fold<int>(
      0,
      (longest, range) => math.max(longest, glyphsByToken[range]!.length),
    );
    _glyphLiftScratch = List<double>.filled(longestToken, 0);
    _glyphProgressScratch = List<double>.filled(longestToken, 0);
    _paintGroups = const [];
    _leadInByToken = <_KaraokeTokenRange, double>{
      for (final range in _drawableRanges)
        range: karaokeGlyphLiftLeadInProgress(
          range.token,
          glyphsByToken[range]?.length ?? 0,
        ),
    };
    _glyphLiftStartTimesUs = [
      for (final glyph in _orderedGlyphs)
        karaokeVisualTokenStart(
              glyph.tokenRange.token,
            ).inMicroseconds.toDouble() +
            karaokeGlyphLiftStartProgress(
                  glyph.index,
                  glyph.count,
                  _leadInByToken[glyph.tokenRange] ?? 0,
                ) *
                (glyph.tokenRange.token.end.inMicroseconds -
                    karaokeVisualTokenStart(
                      glyph.tokenRange.token,
                    ).inMicroseconds),
    ];
    _staticPainter = _layoutWithoutSelected(_drawableRanges, width);
    _completedPainter = null;
    _futurePainter = null;
    _unplayedGlyphPainters.clear();
    _maskGlyphPainters.clear();
    _playedGlyphPainters.clear();
  }

  void _ensurePaintCache(double width) {
    if (_staticPainter != null) return;
    _staticPainter = _layoutWithoutSelected(_drawableRanges, width);
    _completedPainter = null;
    _futurePainter = null;
    _unplayedGlyphPainters.clear();
    _maskGlyphPainters.clear();
    _playedGlyphPainters.clear();
  }

  @override
  void paint(Canvas canvas, Size size) {
    _ensureLayout(size.width);
    _ensurePaintCache(size.width);
    if (_drawableRanges.isEmpty) {
      _layoutPainter!.paint(canvas, Offset.zero);
      return;
    }
    _staticPainter!.paint(canvas, Offset.zero);
    final current = _currentPosition;
    for (var index = 0; index < _drawableRanges.length; index++) {
      _rawProgressBuffer[index] = karaokeRawVisualTokenProgress(
        _drawableRanges[index].token,
        current,
      );
    }
    if (_useLegacyKaraokeMotion) {
      for (var index = 0; index < _orderedGlyphs.length; index++) {
        final glyph = _orderedGlyphs[index];
        _ownFactorBuffer[index] = karaokeLiftCurve(
          karaokeGlyphLiftProgress(
            _rawProgressBuffer[_glyphTokenIndices[index]],
            glyphIndex: glyph.index,
            glyphCount: glyph.count,
            nextTokenStartProgress: _nextTokenStarts[index],
            leadInProgress: _leadInByToken[glyph.tokenRange] ?? 0,
          ),
        );
        _highlightFactorBuffer[index] = karaokeGlyphProgress(
          _rawProgressBuffer[_glyphTokenIndices[index]].clamp(0.0, 1.0),
          glyphIndex: glyph.index,
          glyphCount: glyph.count,
        );
      }
      karaokeChainedLiftFactors(
        _ownFactorBuffer,
        sourceStartTimesUs: _glyphLiftStartTimesUs,
        positionUs: current.inMicroseconds.toDouble(),
        lineCadenceUs: _lineCadenceUs,
        sourceCadencesUs: _glyphCadencesUs,
        breakBeforeFlags: _breakBeforeGlyph,
        resultBuffer: _liftFactorBuffer,
      );
    } else {
      final retention = isExiting
          ? karaokeExitRetention(
              Duration(
                microseconds:
                    (exitAnimation.value *
                            karaokeDefaultMotion.exitDuration.inMicroseconds)
                        .round(),
              ),
              karaokeDefaultMotion,
            )
          : 1.0;
      for (var index = 0; index < _orderedGlyphs.length; index++) {
        final frame = karaokeGlyphFrame(
          current.inMicroseconds,
          _glyphTimings[index],
          karaokeDefaultMotion,
        );
        _highlightFactorBuffer[index] = frame.highlightProgress;
        _liftFactorBuffer[index] = frame.liftProgress * retention;
      }
    }
    final factors = _liftFactorBuffer;
    _completedBuffer.clear();
    _futureBuffer.clear();
    var groupsChanged = _paintGroups.length != _drawableRanges.length;
    for (
      var tokenIndex = 0;
      tokenIndex < _drawableRanges.length;
      tokenIndex++
    ) {
      final range = _drawableRanges[tokenIndex];
      final progress = _rawProgressBuffer[tokenIndex].clamp(0.0, 1.0);
      var group = 2;
      if (progress <= 0) {
        final start = _tokenGlyphStarts[tokenIndex];
        final end = start + _glyphsByToken[range]!.length;
        var anticipates = false;
        for (var index = start; index < end; index++) {
          if (factors[index] > .0001) {
            anticipates = true;
            break;
          }
        }
        if (!anticipates) {
          group = 0;
          _futureBuffer.add(range);
        }
      } else if (progress >= 1 && !isExiting) {
        final start = _tokenGlyphStarts[tokenIndex];
        final end = start + _glyphsByToken[range]!.length;
        var allAtTop = true;
        for (var index = start; index < end; index++) {
          if (factors[index] < .9999) {
            allAtTop = false;
            break;
          }
        }
        if (allAtTop) {
          group = 1;
          _completedBuffer.add(range);
        }
      }
      _groupBuffer[tokenIndex] = group;
      if (!groupsChanged && _paintGroups[tokenIndex] != group) {
        groupsChanged = true;
      }
    }
    if (groupsChanged) {
      _paintGroups = List<int>.of(_groupBuffer);
      _completedPainter = _completedBuffer.isEmpty
          ? null
          : _layoutSelected(_completedBuffer, playedStyle, size.width);
      _futurePainter = _futureBuffer.isEmpty
          ? null
          : _layoutSelected(_futureBuffer, unplayedStyle, size.width);
    }
    _futurePainter?.paint(canvas, Offset.zero);
    final completedPainter = _completedPainter;
    if (completedPainter != null) {
      completedPainter.paint(
        canvas,
        Offset(
          0,
          _useLegacyKaraokeMotion
              ? karaokeHighlightLift(1, _liftReferenceHeight)
              : karaokeLiftPixels(
                  1,
                  _liftReferenceHeight,
                  karaokeDefaultMotion,
                ),
        ),
      );
    }
    for (var index = 0; index < _drawableRanges.length; index++) {
      if (_groupBuffer[index] == 2) {
        _paintPartialToken(
          canvas,
          _drawableRanges[index],
          size,
          factors,
          _tokenGlyphStarts[index],
        );
      }
    }
  }

  void _paintPartialToken(
    Canvas canvas,
    _KaraokeTokenRange range,
    Size size,
    List<double> glyphLiftFactors,
    int firstGlyphIndex,
  ) {
    final glyphs = _glyphsByToken[range];
    if (glyphs == null || glyphs.isEmpty) return;
    final tokenBounds = _tokenBounds[range];
    final direction = _tokenDirections[range];
    if (tokenBounds == null || direction == null) return;
    final glyphLifts = _glyphLiftScratch;
    final glyphProgresses = _glyphProgressScratch;
    Rect? layerBounds;
    for (var index = 0; index < glyphs.length; index++) {
      final glyph = glyphs[index];
      final liftProgress = _highlightFactorBuffer[firstGlyphIndex + index];
      final liftFactor = glyphLiftFactors[firstGlyphIndex + index];
      final lift = _useLegacyKaraokeMotion
          ? karaokeHighlightLift(1, _liftReferenceHeight) * liftFactor
          : karaokeLiftPixels(
              liftFactor,
              _liftReferenceHeight,
              karaokeDefaultMotion,
            );
      glyphLifts[index] = lift;
      glyphProgresses[index] = liftProgress;
      final boxes = _glyphBoxes[glyph];
      if (boxes == null) continue;
      for (final box in boxes) {
        final shifted = box.toRect().shift(Offset(0, lift));
        layerBounds = layerBounds?.expandToInclude(shifted) ?? shifted;
      }
    }
    if (layerBounds == null) return;
    final safeOverflow = (_liftReferenceHeight * .2).clamp(3.0, 16.0);
    final safeLayerBounds = layerBounds.inflate(safeOverflow);
    final playedColor = playedStyle.color ?? Colors.white;
    final unplayedColor =
        unplayedStyle.color ?? Colors.white.withValues(alpha: .36);
    final highlightPaint = Paint()..blendMode = BlendMode.srcIn;
    for (var index = 0; index < glyphs.length; index++) {
      final glyph = glyphs[index];
      final glyphProgress = glyphProgresses[index];
      if (glyphProgress <= 0 || glyphProgress >= 1) {
        final completed = glyphProgress >= 1;
        final painters = completed
            ? _playedGlyphPainters
            : _unplayedGlyphPainters;
        final painter = painters.putIfAbsent(
          glyph,
          () => _layoutSelected(
            [glyph],
            completed ? playedStyle : unplayedStyle,
            size.width,
          ),
        );
        painter.paint(canvas, Offset(0, glyphLifts[index]));
        continue;
      }
      final boxes = _glyphBoxes[glyph];
      if (boxes == null || boxes.isEmpty) continue;
      final lift = glyphLifts[index];
      var glyphBounds = boxes.first.toRect().shift(Offset(0, lift));
      for (final box in boxes.skip(1)) {
        glyphBounds = glyphBounds.expandToInclude(
          box.toRect().shift(Offset(0, lift)),
        );
      }
      final gradient = karaokeGlyphHighlightGradient(
        glyphBounds,
        direction,
        glyphProgresses[index],
        featherFraction: karaokeDefaultMotion.highlightFeatherFraction,
      );
      highlightPaint.shader = ui.Gradient.linear(
        gradient.start,
        gradient.end,
        [
          playedColor,
          Color.lerp(unplayedColor, playedColor, .72)!,
          Color.lerp(unplayedColor, playedColor, .18)!,
          unplayedColor,
        ],
        const [0, .38, .78, 1],
        TileMode.clamp,
      );
      // An opaque coverage mask allows BOTH colour and alpha to change.
      // srcATop over translucent text preserves the grey alpha and previously
      // kept every active letter dim until the whole token was completed.
      final bounds = glyphBounds
          .inflate(safeOverflow)
          .intersect(safeLayerBounds);
      final mask = _maskGlyphPainters.putIfAbsent(
        glyph,
        () => _layoutSelected(
          [glyph],
          unplayedStyle.copyWith(color: Colors.white, shadows: null),
          size.width,
        ),
      );
      canvas.saveLayer(bounds, Paint());
      mask.paint(canvas, Offset(0, lift));
      canvas.drawRect(bounds, highlightPaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _SinglePassKaraokePainter oldDelegate) {
    final playedComparison = playedStyle.compareTo(oldDelegate.playedStyle);
    final unplayedComparison = unplayedStyle.compareTo(
      oldDelegate.unplayedStyle,
    );
    final layoutChanged =
        text != oldDelegate.text ||
        !identical(ranges, oldDelegate.ranges) ||
        playedComparison == RenderComparison.layout ||
        unplayedComparison == RenderComparison.layout ||
        textAlign != oldDelegate.textAlign ||
        textDirection != oldDelegate.textDirection ||
        textScaler != oldDelegate.textScaler ||
        locale != oldDelegate.locale;
    final paintChanged =
        playedStyle != oldDelegate.playedStyle ||
        unplayedStyle != oldDelegate.unplayedStyle;
    if (!layoutChanged) {
      // Colour changes during an active-line jump must not reshape every
      // grapheme. Preserve geometry and only rebuild the inexpensive paint
      // spans; ordinary playback frames retain both geometry and paint caches.
      _layoutWidth = oldDelegate._layoutWidth;
      _layoutPainter = oldDelegate._layoutPainter;
      _liftReferenceHeight = oldDelegate._liftReferenceHeight;
      _lineCadenceUs = oldDelegate._lineCadenceUs;
      _drawableRanges = oldDelegate._drawableRanges;
      _orderedGlyphs = oldDelegate._orderedGlyphs;
      _glyphLiftStartTimesUs = oldDelegate._glyphLiftStartTimesUs;
      _glyphTimings = oldDelegate._glyphTimings;
      _highlightFactorBuffer = oldDelegate._highlightFactorBuffer;
      _glyphCadencesUs = oldDelegate._glyphCadencesUs;
      _breakBeforeGlyph = oldDelegate._breakBeforeGlyph;
      _nextTokenStarts = oldDelegate._nextTokenStarts;
      _glyphTokenIndices = oldDelegate._glyphTokenIndices;
      _tokenGlyphStarts = oldDelegate._tokenGlyphStarts;
      _rawProgressBuffer = oldDelegate._rawProgressBuffer;
      _ownFactorBuffer = oldDelegate._ownFactorBuffer;
      _liftFactorBuffer = oldDelegate._liftFactorBuffer;
      _groupBuffer = oldDelegate._groupBuffer;
      _glyphLiftScratch = oldDelegate._glyphLiftScratch;
      _glyphProgressScratch = oldDelegate._glyphProgressScratch;
      _leadInByToken = oldDelegate._leadInByToken;
      _glyphsByToken = oldDelegate._glyphsByToken;
      _glyphBoxes = oldDelegate._glyphBoxes;
      _tokenBounds = oldDelegate._tokenBounds;
      _tokenDirections = oldDelegate._tokenDirections;
      if (!paintChanged) {
        _staticPainter = oldDelegate._staticPainter;
        _completedPainter = oldDelegate._completedPainter;
        _futurePainter = oldDelegate._futurePainter;
        _paintGroups = oldDelegate._paintGroups;
        _unplayedGlyphPainters = oldDelegate._unplayedGlyphPainters;
        _maskGlyphPainters = oldDelegate._maskGlyphPainters;
        _playedGlyphPainters = oldDelegate._playedGlyphPainters;
      }
    }
    return layoutChanged ||
        paintChanged ||
        isExiting != oldDelegate.isExiting ||
        exitAnimation != oldDelegate.exitAnimation ||
        position != oldDelegate.position ||
        positionListenable != oldDelegate.positionListenable;
  }
}

final Map<double, ui.ImageFilter> _lyricBlurFilters = {};

ui.ImageFilter _cachedLyricBlur(double sigma) {
  final cacheKey = (sigma * 4).round() / 4;
  return _lyricBlurFilters.putIfAbsent(
    cacheKey,
    () => ui.ImageFilter.blur(
      sigmaX: cacheKey,
      sigmaY: cacheKey,
      tileMode: TileMode.decal,
    ),
  );
}
