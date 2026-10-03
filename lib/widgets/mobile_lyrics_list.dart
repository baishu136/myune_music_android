import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:characters/characters.dart' as characters;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable, kDebugMode;
import 'package:flutter/rendering.dart'
    show RenderComparison, ScrollCacheExtent;
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;

import '../page/playlist/playlist_models.dart';
import '../page/setting/settings_provider.dart';
import '../services/interaction_performance_controller.dart';
import 'interlude_animation_widget.dart';
import 'karaoke_motion.dart';
import 'lyric_seek_guide.dart';
import 'lyric_scroll_motion.dart';
import 'lyric_normalized_motion.dart';
import 'lyric_phase_transition.dart';
import 'lyric_frame_clock.dart';
import 'synthetic_karaoke_timing.dart';
import 'karaoke_sweep_path.dart';
import 'karaoke_sweep_timeline.dart';
import 'lyric_viewport_blur.dart';

export 'synthetic_karaoke_timing.dart';

part 'karaoke_media_clock.dart';
part 'karaoke_paint_cache.dart';
part 'karaoke_prewarm.dart';

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
const Duration mobileLyricsFocusTransitionDuration = lyricTransitionDuration;
const Curve mobileLyricsFocusTransitionCurve = lyricTransitionCurve;
const Duration mobileLyricsDefaultScrollTransitionDuration = Duration(
  milliseconds: 620,
);
const Duration mobileLyricsKaraokeLineShiftDuration =
    mobileLyricsFocusTransitionDuration;
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
  /// Diagnostic count of full-song text measurements (not ordinary layout).
  /// Height-only transitions must leave this unchanged.
  int get fullTextLayoutCount => _owner is _MobileLyricsListState
      ? (_owner as _MobileLyricsListState)._fullTextLayoutCount
      : 0;
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
  _ => 3,
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
  final drift = target.inMicroseconds - predicted;
  if (drift.abs() > 200000) return target;
  final correction = drift.abs() <= 30000
      ? (drift * karaokePositionBlend(frameDelta))
            .clamp(-step * .08, step * .08)
            .round()
      : (drift * .35).clamp(-step * .75, step * 3).round();
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
    this.scrollEffect = LyricScrollEffect.standard,
    this.elasticScrollEnabled = false,
    this.karaokeLyricsEnabled = true,
    this.karaokeLyricsMode = KaraokeLyricsMode.timedOnly,
    this.lineBlurEnabled = false,
    this.highlightActiveLine = false,
    this.isPlaying = true,
    this.entryPreparing = false,
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
  final LyricScrollEffect scrollEffect;
  // Kept for existing callers; the playback page uses [scrollEffect].
  final bool elasticScrollEnabled;
  final bool karaokeLyricsEnabled;
  final KaraokeLyricsMode karaokeLyricsMode;
  final bool lineBlurEnabled;
  final bool highlightActiveLine;
  final bool isPlaying;

  /// Hidden cover-to-lyrics preparation, not a seek or normal focus change.
  /// Resolve retained row poses without remounting text/layout/paint caches.
  final bool entryPreparing;
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
  // The karaoke switch changes glyph paint, never the row/list trajectory.
  // Keep the default font-adaptive spring and the optional elastic row driver.
  final LyricScrollMotion _springMotion = LyricScrollMotion(
    dampingRatio: .90,
    frequency: mobileLyricsDefaultScrollFrequency,
  );
  Duration _focusDuration = mobileLyricsFocusTransitionDuration;
  Curve _focusCurve = mobileLyricsFocusTransitionCurve;
  LyricScrollDriver get _motion => _springMotion;
  final ValueNotifier<_LyricDebugSnapshot> _debugSnapshot = ValueNotifier(
    const _LyricDebugSnapshot(),
  );
  final ValueNotifier<_LyricElasticPulse> _elasticPulse = ValueNotifier(
    const _LyricElasticPulse(),
  );
  final ValueNotifier<_LyricBrowseHighlightFrame> _browseHighlight =
      ValueNotifier(const _LyricBrowseHighlightFrame());
  final GlobalKey _browseTapTargetRenderKey = GlobalKey();
  late final LyricFrameClock _frameClock;
  final _prewarm = _KaraokePrewarmSlot();
  int _prewarmGeneration = 0;
  bool _prewarmPending = false;
  int _prewarmHandledIndex = -1;
  int _prewarmHandledGeneration = -1;
  TextStyle? _prewarmStyle;
  TextScaler _prewarmScaler = TextScaler.noScaling;
  Locale? _prewarmLocale;
  double _prewarmPixelRatio = 1;
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
  bool _hasInitialPosition = false;
  bool _layoutInvalid = true;
  int _fullTextLayoutCount = 0;
  bool _pendingTypographyReanchor = false;
  bool _debugOverlayEnabled = false;
  int _layoutRequestId = 0;
  int _lyricContentRevision = 0;
  bool _awaitingNextSongLyrics = false;
  int _recompositionCount = 0;
  int? _browseTargetIndex;
  int? _seekTargetIndex;
  int? _normalExitIndex;
  // Interlude exit styling must outlive a fast second lyric boundary. One
  // retained index is sufficient: parsed interludes last more than eight seconds.
  int? _interludeExitIndex;
  bool _explicitSeekPending = false;
  Timer? _explicitSeekTimer;
  Duration? _lastObservedPosition;
  Duration _lastObservedStamp = Duration.zero;
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

  // Elastic mode owns the row displacement; rigid mode owns the list offset.
  // Karaoke glyph lift is independent of either, with no local AnimatedSlide.
  bool get _usesRowElastic =>
      widget.scrollEffect == LyricScrollEffect.elastic ||
      widget.elasticScrollEnabled;

  @override
  void initState() {
    super.initState();
    _frameClock = LyricFrameClock(this, _onMotionTick);
    _configureMotion();
    widget.seekIntentListenable?.addListener(_markExplicitSeek);
    widget.seekPositionListenable?.addListener(_readCompletedSeek);
    widget.positionListenable?.addListener(_readListPosition);
    widget.playbackRateListenable?.addListener(_resetListPositionAnchor);
    widget.actualPlaybackListenable?.addListener(_resetListPositionAnchor);
    _resetListPositionAnchor();
    widget.controller?._attach(this, _recenterActive, _settleOnTimestamp);
  }

  void _markExplicitSeek() {
    _normalExitIndex = null;
    _interludeExitIndex = null;
    // Cancel pending jobs, not valid shaped geometry. A seek changes media
    // time, not the font/layout identity; throwing away the spare atlas here
    // forces a cold first-segment layout on every jump/replay.
    _prewarmGeneration++;
    _explicitSeekPending = true;
    _explicitSeekTimer?.cancel();
    _stopMotion();
    _motion.velocity = 0;
    final pulse = _elasticPulse.value;
    _elasticPulse.value = _LyricElasticPulse(id: pulse.id + 1);
    _explicitSeekTimer = Timer(const Duration(seconds: 2), () {
      _explicitSeekPending = false;
    });
  }

  void _resetListPositionAnchor() {
    _lastObservedPosition = widget.positionListenable?.value ?? widget.position;
    _lastObservedStamp = SchedulerBinding.instance.currentSystemFrameTimeStamp;
  }

  void _readCompletedSeek() {
    final target = widget.seekPositionListenable?.value;
    if (target != null) _snapPlaybackSeek(target);
  }

  void _readListPosition() {
    final source = widget.positionListenable?.value ?? widget.position;
    final previous = _lastObservedPosition;
    final stamp = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    final outputRunning =
        widget.isPlaying && (widget.actualPlaybackListenable?.value ?? true);
    final discontinuity =
        previous != null &&
        karaokePlaybackPositionDiscontinuity(
          previousSource: previous,
          source: source,
          // Pause/buffering has no expected media-time advance. Re-anchor on
          // output transitions so resumed updates cannot include the pause.
          elapsedSinceSource: outputRunning
              ? stamp - _lastObservedStamp
              : Duration.zero,
          playbackRate:
              widget.playbackRateListenable?.value ?? widget.playbackRate,
        );
    _lastObservedPosition = source;
    _lastObservedStamp = stamp;
    if (discontinuity && _seekTargetIndex == null) _snapPlaybackSeek(source);
    _maybePrewarmNext(source);
  }

  void _snapPlaybackSeek(Duration target) {
    if (widget.lines.isEmpty) return;
    var index = 0;
    // A media position belongs to the preceding LRC line, not the nearest
    // future timestamp. Controller lyric taps still use their exact timestamp.
    for (var i = 1; i < widget.lines.length; i++) {
      if (widget.lines[i].timestamp > target) break;
      index = i;
    }
    _settleOnTimestamp(target, targetIndexOverride: index);
    _resetListPositionAnchor();
  }

  @override
  void didUpdateWidget(covariant MobileLyricsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fontSize != widget.fontSize) {
      _configureMotion();
    }
    if (oldWidget.positionListenable != widget.positionListenable) {
      oldWidget.positionListenable?.removeListener(_readListPosition);
      widget.positionListenable?.addListener(_readListPosition);
      _resetListPositionAnchor();
    }
    if (oldWidget.seekPositionListenable != widget.seekPositionListenable) {
      oldWidget.seekPositionListenable?.removeListener(_readCompletedSeek);
      widget.seekPositionListenable?.addListener(_readCompletedSeek);
    }
    if (oldWidget.playbackRateListenable != widget.playbackRateListenable) {
      oldWidget.playbackRateListenable?.removeListener(
        _resetListPositionAnchor,
      );
      widget.playbackRateListenable?.addListener(_resetListPositionAnchor);
      _resetListPositionAnchor();
    }
    if (oldWidget.actualPlaybackListenable != widget.actualPlaybackListenable) {
      oldWidget.actualPlaybackListenable?.removeListener(
        _resetListPositionAnchor,
      );
      widget.actualPlaybackListenable?.addListener(_resetListPositionAnchor);
      _resetListPositionAnchor();
    }
    if (oldWidget.playbackRate != widget.playbackRate ||
        oldWidget.isPlaying != widget.isPlaying) {
      _resetListPositionAnchor();
    }
    if (oldWidget.seekIntentListenable != widget.seekIntentListenable) {
      oldWidget.seekIntentListenable?.removeListener(_markExplicitSeek);
      widget.seekIntentListenable?.addListener(_markExplicitSeek);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this, _recenterActive, _settleOnTimestamp);
    }
    // This also runs when lyrics/font replacement takes the layout branch
    // below. Entry preparation must cancel retained row springs in that case.
    if (widget.entryPreparing) {
      _normalExitIndex = null;
      _interludeExitIndex = null;
      if (!oldWidget.entryPreparing) {
        _stopMotion();
        _elasticPulse.value = _LyricElasticPulse(
          id: _elasticPulse.value.id + 1,
        );
      }
    }
    final linesChanged = oldWidget.lines != widget.lines;
    final contentChanged = oldWidget.contentIdentity != widget.contentIdentity;
    if (contentChanged) {
      _resetListPositionAnchor();
      _normalExitIndex = null;
      _interludeExitIndex = null;
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

    final wasRowElastic =
        oldWidget.scrollEffect == LyricScrollEffect.elastic ||
        oldWidget.elasticScrollEnabled;
    if (wasRowElastic != _usesRowElastic) {
      _stopMotion();
      _elasticPulse.value = _LyricElasticPulse(id: _elasticPulse.value.id + 1);
      _focusDuration = mobileLyricsFocusTransitionDuration;
      _focusCurve = mobileLyricsFocusTransitionCurve;
      if (_scrollControllerState?.hasClients ?? false) {
        _motion.sync(_scrollController.offset, viewportExtent: _viewportHeight);
      }
      if (!_isManuallyBrowsing && !_lyricsPointerDown) {
        _retargetIndex(widget.active, force: true, springLines: false);
      }
    }

    if (widget.entryPreparing) {
      if (oldWidget.active != widget.active && !_lyricsPointerDown) {
        _scheduleLayoutRetarget(jump: true);
      }
      return;
    }
    if (oldWidget.entryPreparing) {
      _focusDuration = mobileLyricsFocusTransitionDuration;
      _focusCurve = mobileLyricsFocusTransitionCurve;
      _resetListPositionAnchor();
    }

    final locked = _seekTargetIndex;
    final source = widget.positionListenable?.value ?? widget.position;
    if (locked != null &&
        widget.active == locked + 1 &&
        widget.active < widget.lines.length &&
        source >= widget.lines[widget.active].timestamp &&
        source >= (_seekTargetTimestamp ?? Duration.zero)) {
      // A seek near a line end may reach the next line before confirmation.
      // Valid forward playback releases the lock immediately, so fast phrases
      // are not held on the old row for the anti-jitter confirmation window.
      _clearSeekTarget();
    }
    if (oldWidget.active == widget.active) return;
    final seeking = _explicitSeekPending;
    _normalExitIndex =
        // -1 is the player's valid "before first timestamp" sentinel, not a
        // departing row. Reading lines[-1] here replaces the entire lyric
        // subtree with Flutter's solid grey ErrorWidget in release builds.
        oldWidget.active >= 0 &&
            oldWidget.active < widget.lines.length &&
            widget.active >= 0 &&
            widget.active < widget.lines.length &&
            widget.active > oldWidget.active &&
            _seekTargetIndex == null &&
            !_explicitSeekPending &&
            !_isManuallyBrowsing &&
            widget.isPlaying &&
            oldWidget.isPlaying
        ? oldWidget.active
        : null;
    if (_normalExitIndex case final index?) {
      if (widget.lines[index].isInterlude) _interludeExitIndex = index;
    }
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
    if (seeking) {
      _jumpToIndex(widget.active);
    } else {
      // Adjacent tall/translated rows are a normal transition, not a far seek.
      // Bounding their travel snaps the missing prefix at frame zero.
      _retargetIndex(
        widget.active,
        boundedTravel:
            widget.active >= 0 &&
            widget.active < _itemOffsets.length &&
            (_scrollControllerState?.hasClients ?? false) &&
            (_itemOffsets[widget.active] - _scrollController.offset).abs() >
                _viewportHeight * 1.5,
      );
    }
  }

  void _resetScrollPositionForNewContent() {
    _layoutRequestId++;
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

  void _maybePrewarmNext(Duration source) {
    final index = widget.active + 1;
    final style = _prewarmStyle;
    if (_prewarmPending ||
        style == null ||
        !widget.karaokeLyricsEnabled ||
        _isManuallyBrowsing ||
        index <= 0 ||
        index >= widget.lines.length ||
        (index == _prewarmHandledIndex &&
            _prewarmGeneration == _prewarmHandledGeneration)) {
      return;
    }
    final start = widget.lines[index - 1].timestamp;
    final end = widget.lines[index].timestamp;
    final span = (end - start).inMicroseconds;
    if (source >= end ||
        span <= 0 ||
        ((source - start).inMicroseconds < span * .8 &&
            (end - source).inMilliseconds > 400)) {
      return;
    }
    final line = widget.lines[index];
    if (line.isInterlude) return;
    final timed = hasUsableKaraokeTiming(line);
    if (!timed && widget.karaokeLyricsMode != KaraokeLyricsMode.all) return;
    final next = index + 1 < widget.lines.length
        ? widget.lines[index + 1].timestamp
        : null;
    final effective = timed
        ? line
        : synthesizeKaraokeTiming(line, nextTimestamp: next);
    final identity = (effective, next, widget.karaokeLyricsMode);
    if (_prewarm.mounted.contains(identity) || _prewarm.identity == identity) {
      _prewarm.warmers[identity]?.call();
      _prewarm.cache?.prepareImage();
      _prewarmHandledIndex = index;
      _prewarmHandledGeneration = _prewarmGeneration;
      return;
    }
    final generation = _prewarmGeneration;
    _prewarmPending = true;
    // After the current frame is painted, use a macrotask rather than adding
    // layout work to transient callbacks. A continuously ticking player would
    // starve a Priority.idle scheduler task. At most one spare is prepared.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Timer.run(() {
        _prewarmPending = false;
        if (!mounted ||
            generation != _prewarmGeneration ||
            widget.active + 1 != index ||
            _isManuallyBrowsing ||
            (widget.positionListenable?.value ?? widget.position) >= end ||
            _prewarm.mounted.contains(identity)) {
          return;
        }
        _prewarm.clear();
        _prewarm.identity = identity;
        _prewarm.cache = _KaraokePaintCache(
          text: effective.texts.join('\n'),
          ranges: _karaokeRanges(effective),
          synthetic: !timed,
          width: mobileLyricScaleSafeContentWidth(
            (_layoutWidth - mobileLyricsHorizontalInset(widget.textAlign) * 2)
                .clamp(1.0, double.infinity),
          ),
          style: style,
          textAlign: widget.textAlign,
          textDirection: _layoutDirection!,
          textScaler: _prewarmScaler,
          locale: _prewarmLocale,
          pixelRatio: _prewarmPixelRatio,
        );
        _prewarm.cache!.prepareImage();
        _prewarmHandledIndex = index;
        _prewarmHandledGeneration = generation;
      });
    });
  }

  void _onMotionTick(Duration elapsed) {
    if (!_scrollController.hasClients) {
      _stopMotion();
      return;
    }
    final previousTick = _lastTick;
    _lastTick = elapsed;
    if (previousTick == null) return;
    final frameSeconds =
        (elapsed - previousTick).inMicroseconds /
        Duration.microsecondsPerSecond;
    final maxOffset = _scrollController.position.maxScrollExtent;
    _motion.retarget(
      _motion.target.clamp(0.0, maxOffset),
      viewportExtent: _viewportHeight,
    );
    final nextOffset = _motion.advance(frameSeconds).clamp(0.0, maxOffset);
    // Keep the normalized tail subpixel-continuous too: a .05px gate can hold
    // several final frames then jump, even though the model is continuous.
    if (_scrollController.offset != nextOffset) {
      _scrollController.jumpTo(nextOffset);
    }
    _updateDebugSnapshot(elapsed, frameSeconds);
    if (_motion.isSettled) _stopMotion();
  }

  void _startMotion() {
    if (_frameClock.moving.value) return;
    // Playback may already own a running shared ticker. Anchor to its current
    // elapsed time, not zero, or a new line would inherit the song's uptime.
    _frameClock.setMoving(true);
    _lastTick = _frameClock.elapsed;
    InteractionPerformanceController.instance.pulse(
      InteractionPhase.visualAnimation,
      settleAfter: const Duration(milliseconds: 1500),
    );
  }

  void _stopMotion() {
    _frameClock.setMoving(false);
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
    if (_usesRowElastic && springLines) {
      _focusDuration = mobileLyricsFocusTransitionDuration;
      _focusCurve = mobileLyricsFocusTransitionCurve;
      final displacement = clampedTarget - _scrollController.offset;
      _stopMotion();
      if (displacement.abs() >= .35) {
        InteractionPerformanceController.instance.pulse(
          InteractionPhase.visualAnimation,
          settleAfter: const Duration(milliseconds: 1100),
        );
        final previous = _elasticPulse.value;
        final visualDisplacement = !boundedTravel && _normalExitIndex != null
            ? displacement
            : clampLyricElasticDisplacement(
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

    if (_usesRowElastic) {
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
    if (_frameClock.moving.value) {
      // Preserve the current velocity across dense or multi-line lyric
      // changes, while synchronizing any offset changed by a bounded seek.
      _motion.offset = animationStart;
    } else {
      _motion.sync(animationStart, viewportExtent: _viewportHeight);
    }
    _motion.retarget(
      clampedTarget,
      viewportExtent: _viewportHeight,
      launchFromRest: false,
    );
    _focusDuration = mobileLyricsDefaultScrollTransitionDuration;
    _focusCurve = mobileLyricsFocusTransitionCurve;
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
    _focusDuration = Duration.zero;
    _focusCurve = mobileLyricsFocusTransitionCurve;
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
          _jumpToIndex(seekTarget);
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
    _resumeFollowTimer = Timer(const Duration(milliseconds: 3500), () {
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
    if (_browseTargetIndex == null || _browseTargetIndex == widget.active) {
      return;
    }
    _browseHighlightRevealTimer = Timer(mobileLyricsBrowseMaskRevealDelay, () {
      if (!mounted ||
          !_isManuallyBrowsing ||
          _browseTargetIndex == null ||
          _browseTargetIndex == widget.active) {
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
        target == widget.active ||
        target < 0 ||
        target >= widget.lines.length) {
      return false;
    }
    widget.onBrowseTargetSelected?.call(widget.lines[target].timestamp);
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
      _browseTargetIndex != widget.active &&
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
    if (!_isManuallyBrowsing) _startManualInteraction();
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
    // The currently singing line is already selected for playback. Browsing
    // across it must not offer a redundant seek target or timestamp badge.
    final candidate = index == widget.active ? null : index;
    final changed = candidate != _browseTargetIndex;
    if (changed) {
      if (candidate == null) {
        _browseHighlightRevealTimer?.cancel();
        _browseHighlightRevealTimer = null;
        _browseHighlightVisible = false;
      }
      setState(() => _browseTargetIndex = candidate);
      widget.onBrowseTargetChanged?.call(
        candidate == null ? null : widget.lines[candidate].timestamp,
      );
    } else if (force) {
      widget.onBrowseTargetChanged?.call(
        candidate == null ? null : widget.lines[candidate].timestamp,
      );
    }
    _updateBrowseHighlightForOffset(_scrollController.offset);
  }

  void _recenterActive() {
    _clearSeekTarget();
    _resumeAutomaticFollow();
    _scheduleLayoutRetarget(jump: true);
  }

  void _settleOnTimestamp(Duration timestamp, {int? targetIndexOverride}) {
    if (widget.lines.isEmpty) return;
    _markExplicitSeek();
    _resumeAutomaticFollow();
    _normalExitIndex = null;
    final targetIndex = targetIndexOverride ?? _nearestLyricIndex(timestamp);
    _seekTargetTimer?.cancel();
    _seekTargetTimestamp = timestamp;
    setState(() {
      _seekTargetIndex = targetIndex;
    });
    if (_scrollControllerState?.hasClients ?? false) {
      _jumpToIndex(targetIndex);
    } else {
      _scheduleLayoutRetarget(jump: true);
    }
    _armSeekTargetTimeout(timestamp, targetIndex);
    if (widget.active == targetIndex) _armSeekTargetConfirmation(targetIndex);
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
    // A decoder can emit the previous row after its first target confirmation.
    // Protect one complete normalized transition, not just 120 ms. Forward
    // playback crossing a real next timestamp still releases the lock above.
    _seekTargetConfirmationTimer = Timer(const Duration(milliseconds: 500), () {
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
    if (hadTarget) {
      _explicitSeekPending = false;
      _explicitSeekTimer?.cancel();
    }
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
    final scaler = MediaQuery.textScalerOf(context);
    final textScale = scaler.scale(1);
    final textStyle = DefaultTextStyle.of(context).style.copyWith(
      fontFamily: widget.fontFamily,
      fontSize: widget.fontSize,
      fontWeight: widget.fontWeight,
      height: 1.2,
    );
    final textMetricsUnchanged =
        !_layoutInvalid &&
        identical(_layoutLines, widget.lines) &&
        (_layoutWidth - width).abs() < .5 &&
        (_layoutFontSize - widget.fontSize).abs() < .01 &&
        _layoutFontFamily == widget.fontFamily &&
        widget.textAlign == _layoutTextAlign &&
        _layoutDirection == direction &&
        _prewarmLocale == Localizations.maybeLocaleOf(context) &&
        _prewarmPixelRatio == MediaQuery.devicePixelRatioOf(context) &&
        _prewarmScaler == scaler &&
        _prewarmStyle?.compareTo(textStyle) != RenderComparison.layout &&
        (_layoutTextScale - textScale).abs() < .001;
    if (textMetricsUnchanged) {
      if ((_viewportHeight - viewport).abs() < .5) return false;
      // Immersive chrome changes HEIGHT each frame, not glyph geometry. Keep
      // Pictures, atlas warmup and measured line extents intact. Usually the
      // top-padding / anchor deltas cancel, so even offsets need no iteration.
      _updateViewportGeometry(viewport);
      return true;
    }

    _layoutInvalid = false;
    _fullTextLayoutCount++;
    _layoutLines = widget.lines;
    _layoutWidth = width;
    _viewportHeight = viewport;
    _layoutFontSize = widget.fontSize;
    _layoutFontFamily = widget.fontFamily;
    _layoutTextAlign = widget.textAlign;
    _layoutDirection = direction;
    _layoutTextScale = textScale;

    final horizontalInset = mobileLyricsHorizontalInset(widget.textAlign);
    final availableWidth = mobileLyricScaleSafeContentWidth(
      (width - horizontalInset * 2).clamp(1.0, double.infinity),
    );
    _prewarmGeneration++;
    _prewarm.clear();
    _prewarmStyle = textStyle;
    _prewarmScaler = scaler;
    _prewarmLocale = Localizations.maybeLocaleOf(context);
    _prewarmPixelRatio = MediaQuery.devicePixelRatioOf(context);
    final lineMetricPainter = TextPainter(
      text: TextSpan(text: 'M', style: textStyle),
      textDirection: direction,
      textScaler: scaler,
      locale: _prewarmLocale,
    )..layout(maxWidth: availableWidth);
    _browseMinimumHitHeight = lineMetricPainter.height * 3 + 10;
    lineMetricPainter.dispose();
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
        locale: _prewarmLocale,
      )..layout(maxWidth: availableWidth);
      final contentHeight = (painter.height + 10).clamp(
        widget.fontSize * 1.2 + 10,
        double.infinity,
      );
      painter.dispose();
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

  void _updateViewportGeometry(double viewport) {
    final oldAnchorBase = _topPadding - _viewportHeight * _focusAnchor;
    _viewportHeight = viewport;
    _topPadding = _itemHeights.isEmpty
        ? 0
        : (viewport * _focusAnchor - _itemHeights.first / 2).clamp(
            0.0,
            double.infinity,
          );
    _bottomPadding = _itemHeights.isEmpty
        ? 0
        : (viewport * (1 - _focusAnchor) - _itemHeights.last / 2).clamp(
            0.0,
            double.infinity,
          );
    final delta = _topPadding - viewport * _focusAnchor - oldAnchorBase;
    if (delta.abs() > .001) {
      for (var i = 0; i < _itemOffsets.length; i++) {
        _itemOffsets[i] += delta;
      }
      _scheduleLayoutRetarget(jump: true);
    }
    // Do NOT retarget a running scroll on each frame of a size transition.
  }

  void _configureMotion() => _springMotion.updateDynamics(
    frequency: mobileLyricsScrollFrequencyForFontSize(widget.fontSize),
    dampingRatio: .90,
  );

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
    widget.seekPositionListenable?.removeListener(_readCompletedSeek);
    widget.positionListenable?.removeListener(_readListPosition);
    widget.playbackRateListenable?.removeListener(_resetListPositionAnchor);
    widget.actualPlaybackListenable?.removeListener(_resetListPositionAnchor);
    _explicitSeekTimer?.cancel();
    InteractionPerformanceController.instance.endPhase(
      InteractionPhase.visualAnimation,
    );
    widget.controller?._detach(this);
    _frameClock.dispose();
    _prewarmGeneration++;
    _prewarm.clear();
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
                : _seekTargetTimestamp ?? widget.position;
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
                                index == _browseTargetIndex &&
                                index != widget.active;
                            final browseHighlighted =
                                browseTarget && _browseHighlightVisible;
                            Widget item = _LyricLineItem(
                              key: ValueKey('mobile_lyric_$index'),
                              line: widget.lines[index],
                              frameClock: _frameClock,
                              prewarm: _prewarm,
                              active: index == displayedActive,
                              distance: distance,
                              relativeDistance: index - displayedActive,
                              height: _itemHeights[index],
                              contentCenter:
                                  _itemOffsets[index] +
                                  _viewportHeight * _focusAnchor,
                              viewportHeight: _viewportHeight,
                              scrollController: _scrollController,
                              focusDuration:
                                  widget.entryPreparing ||
                                      _seekTargetIndex != null
                                  ? Duration.zero
                                  : _focusDuration,
                              focusCurve: _focusCurve,
                              entryPreparing: widget.entryPreparing,
                              seekTargetPosition: _seekTargetIndex == null
                                  ? null
                                  : _seekTargetTimestamp,
                              fontSize: widget.fontSize,
                              fontFamily: widget.fontFamily,
                              activeColor: widget.activeColor,
                              styleIdentity: widget.contentIdentity,
                              fontWeight: widget.fontWeight,
                              glowEnabled: widget.glowEnabled,
                              glowRadius: widget.glowRadius,
                              brightForeground: widget.brightForeground,
                              textAlign: widget.textAlign,
                              lineBlurEnabled: widget.lineBlurEnabled,
                              lineSpreadEnabled:
                                  widget.scrollEffect ==
                                  LyricScrollEffect.dynamic,
                              highlightActiveLine: widget.highlightActiveLine,
                              karaokeLyricsEnabled: widget.karaokeLyricsEnabled,
                              karaokeLyricsMode: widget.karaokeLyricsMode,
                              nextTimestamp: index + 1 < widget.lines.length
                                  ? widget.lines[index + 1].timestamp
                                  : null,
                              browseHighlighted: browseHighlighted,
                              lineBlurSuppressed: _isManuallyBrowsing,
                              isPlaying: widget.isPlaying,
                              normalExit:
                                  !widget.entryPreparing &&
                                  (index == _normalExitIndex ||
                                      index == _interludeExitIndex),
                              normalEntry:
                                  !widget.entryPreparing &&
                                  index == displayedActive &&
                                  _normalExitIndex != null,
                              playbackRate: widget.playbackRate,
                              playbackRateListenable:
                                  widget.playbackRateListenable,
                              actualPlaybackListenable:
                                  widget.actualPlaybackListenable,
                              seekPositionListenable:
                                  widget.seekPositionListenable,
                              seekIntentListenable: widget.seekIntentListenable,
                              position: displayedPosition,
                              positionListenable:
                                  (_seekTargetIndex == null ||
                                          widget.active == _seekTargetIndex) &&
                                      index == displayedActive
                                  ? widget.positionListenable
                                  : null,
                            );
                            if (_usesRowElastic) {
                              item = _ElasticLyricLine(
                                key: ValueKey(
                                  'mobile_lyric_elastic_${_lyricContentRevision}_$index',
                                ),
                                index: index,
                                pulse: _elasticPulse,
                                frameClock: _frameClock,
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
                    opacity:
                        _browseHighlightVisible &&
                            _browseTargetIndex != widget.active
                        ? 1
                        : 0,
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
                    child:
                        _isManuallyBrowsing &&
                            _browseTargetIndex != null &&
                            _browseTargetIndex != widget.active
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
                    _browseTargetIndex != widget.active &&
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
    required this.frameClock,
    required this.child,
  });

  final int index;
  final ValueListenable<_LyricElasticPulse> pulse;
  final LyricFrameClock frameClock;
  final Widget child;

  @override
  State<_ElasticLyricLine> createState() => _ElasticLyricLineState();
}

class _ElasticLyricLineState extends State<_ElasticLyricLine> {
  final _offset = ValueNotifier<double>(0);
  SpringSimulation? _simulation;
  Duration _origin = Duration.zero;
  double _delaySeconds = 0;
  bool _following = false;
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
    final elapsed = (widget.frameClock.elapsed - _origin).inMicroseconds / 1e6;
    final velocity =
        _following && _simulation != null && elapsed >= _delaySeconds
        ? _simulation!.dx(elapsed - _delaySeconds)
        : 0.0;
    _stopFrames();

    if (pulse.displacement.abs() < .35) {
      _offset.value = 0;
      return;
    }

    // A redirected list jump is added to the residual row offset, preserving
    // screen position and spring velocity instead of restarting from a snap.
    _offset.value += pulse.displacement;
    _pendingDurationSeconds = pulse.lineDurationSeconds;
    final distance = (widget.index - pulse.anchorIndex).abs();
    if (distance > 4) {
      // Cached rows outside the visible elastic wave must not keep their own
      // spring ticker alive. They cannot be seen, but collectively add raster
      // and scheduling pressure when glow is enabled.
      _offset.value = 0;
      return;
    }
    final delayStep = (_pendingDurationSeconds * 38).clamp(10.0, 44.0);
    _delaySeconds = distance * delayStep / 1000;
    _startSpring(velocity);
  }

  void _startSpring(double velocity) {
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
    _simulation = SpringSimulation(
      spring,
      _offset.value,
      0,
      velocity,
      tolerance: const Tolerance(distance: .5, velocity: .1),
    );
    _following = true;
    widget.frameClock.addListener(_tick);
    _origin = widget.frameClock.elapsed;
    widget.frameClock.beginElasticRow();
  }

  void _tick() {
    final time =
        (widget.frameClock.elapsed - _origin).inMicroseconds / 1e6 -
        _delaySeconds;
    if (time < 0) return;
    final simulation = _simulation!;
    if (simulation.isDone(time)) {
      _offset.value = 0;
      _stopFrames();
    } else {
      _offset.value = simulation.x(time);
    }
  }

  void _stopFrames() {
    if (!_following) return;
    _following = false;
    widget.frameClock.removeListener(_tick);
    widget.frameClock.endElasticRow();
  }

  @override
  void dispose() {
    widget.pulse.removeListener(_handlePulse);
    _stopFrames();
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _offset,
    child: widget.child,
    builder: (context, child) => Transform.translate(
      key: ValueKey('mobile_lyric_elastic_transform_${widget.index}'),
      offset: Offset(0, _offset.value),
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
    required this.frameClock,
    required this.prewarm,
    required this.active,
    required this.distance,
    required this.relativeDistance,
    required this.height,
    required this.contentCenter,
    required this.viewportHeight,
    required this.scrollController,
    required this.focusDuration,
    required this.focusCurve,
    required this.entryPreparing,
    required this.seekTargetPosition,
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
    required this.lineSpreadEnabled,
    required this.highlightActiveLine,
    required this.karaokeLyricsEnabled,
    required this.karaokeLyricsMode,
    required this.nextTimestamp,
    required this.browseHighlighted,
    required this.lineBlurSuppressed,
    required this.isPlaying,
    required this.normalExit,
    required this.normalEntry,
    required this.playbackRate,
    required this.playbackRateListenable,
    required this.actualPlaybackListenable,
    required this.seekPositionListenable,
    required this.seekIntentListenable,
    required this.position,
    required this.positionListenable,
  });

  final LyricLine line;
  final LyricFrameClock frameClock;
  final _KaraokePrewarmSlot prewarm;
  final bool active;
  final int distance;
  final int relativeDistance;
  final double height;
  final double contentCenter;
  final double viewportHeight;
  final ScrollController scrollController;
  final Duration focusDuration;
  final Curve focusCurve;
  final bool entryPreparing;
  final Duration? seekTargetPosition;
  bool get _snapPresentation => entryPreparing || seekTargetPosition != null;
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
  final bool lineSpreadEnabled;
  final bool highlightActiveLine;
  final bool karaokeLyricsEnabled;
  final KaraokeLyricsMode karaokeLyricsMode;
  final Duration? nextTimestamp;
  final bool browseHighlighted;
  final bool lineBlurSuppressed;
  final bool isPlaying;
  final bool normalExit;
  final bool normalEntry;
  final double playbackRate;
  final ValueListenable<double>? playbackRateListenable;
  final ValueListenable<bool>? actualPlaybackListenable;
  final ValueListenable<Duration?>? seekPositionListenable;
  final Listenable? seekIntentListenable;
  final Duration position;
  final ValueListenable<Duration>? positionListenable;

  double get _opacity => switch (distance) {
    0 => 1,
    1 => .68,
    2 => .52,
    3 => .40,
    _ => .32,
  };

  double get _scale => line.isInterlude && normalExit
      ? mobileLyricsActiveScale
      : switch (distance) {
          0 => mobileLyricsActiveScale,
          _ => 1,
        };

  Offset get _lyricLineOffset =>
      !lineSpreadEnabled || lineBlurSuppressed || browseHighlighted
      ? Offset.zero
      : Offset(0, mobileLyricsKaraokeLineShift(relativeDistance));

  Widget _withLineShift(Widget child) {
    // The dynamic preset adds the 341 focus gap in BOTH karaoke modes. The
    // standard and elastic presets retain the smooth 340 line geometry. Keep
    // the same State when switching presets so the spread can settle smoothly.
    return LyricPhaseSlide(
      snapToTarget: _snapPresentation,
      key: const ValueKey('mobile_lyric_karaoke_line_shift'),
      offset: _lyricLineOffset,
      duration: focusDuration == Duration.zero
          ? Duration.zero
          : mobileLyricsKaraokeLineShiftDuration,
      curve: mobileLyricsFocusTransitionCurve,
      child: child,
    );
  }

  Alignment get _alignment => switch (textAlign) {
    TextAlign.left || TextAlign.start => Alignment.centerLeft,
    TextAlign.right || TextAlign.end => Alignment.centerRight,
    _ => Alignment.center,
  };

  double get _blurSigma {
    if (!lineBlurEnabled ||
        lineBlurSuppressed ||
        active ||
        distance <= 0 ||
        (line.isInterlude && normalExit)) {
      return 0;
    }
    // Non-focus karaoke rows share a visual target; default lyrics retain
    // their existing distance hierarchy. Focus/interlude exits stay smooth.
    return mobileLyricBlurSigmaForDistance(karaokeLyricsEnabled ? 1 : distance);
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
    // Karaoke rows own their ink alpha, including static distant rows. Keep
    // one dim original/translation target, with no second distance alpha.
    final karaokeUnplayedColor = darkForeground
        ? Colors.white.withValues(alpha: .36)
        : const Color(0xFF757575).withValues(alpha: .68);
    // Distance opacity is composited outside the cached glyph masks.
    final inactiveColor = karaokeLyricsEnabled
        ? karaokeUnplayedColor
        : inactiveBase;
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
            presentationPreparing: _snapPresentation,
            isCurrent: active,
            baseColor: inactiveColor,
            highlightColor: resolvedActiveColor.withValues(alpha: .9),
            startTime: line.timestamp,
            interludeDuration: line.interludeDuration ?? Duration.zero,
            currentTime: currentPosition,
            isPlaying: isPlaying,
            normalExit: normalExit,
            positionListenable: active ? positionListenable : null,
            frameClock: frameClock,
            playbackRate: playbackRate,
            playbackRateListenable: playbackRateListenable,
            actualPlaybackListenable: actualPlaybackListenable,
            seekIntentListenable: seekIntentListenable,
            seekPositionListenable: seekPositionListenable,
          ),
        );
      }
      // Karaoke has priority over whole-line highlighting when explicitly
      // enabled. Previously highlight mode returned here first, which made the
      // new karaoke switch appear to do nothing for users who had kept the
      // older highlight option enabled.
      if (!karaokeWillAnimate || browseHighlighted) {
        if (karaokeLyricsEnabled && !browseHighlighted) {
          return _staticKaraokeLyric(inactiveColor);
        }
        return Text(line.texts.join('\n'), textAlign: textAlign);
      }
      // Distant rows have no changing glyph state. Keep a single shaped
      // paragraph instead of building hundreds of per-glyph Pictures while
      // several translated rows enter the sliver cache in the same frame.
      // Retain the active, exiting and immediate next line's paint caches.
      if (!active && !normalExit && relativeDistance != 1) {
        return _staticKaraokeLyric(inactiveColor);
      }
      final animatedPosition = active
          ? currentPosition
          : line.timestamp - const Duration(milliseconds: 120);
      return _KaraokeLyricText(
        entryPreparing: entryPreparing,
        seekTargetPosition: active ? seekTargetPosition : null,
        frameClock: frameClock,
        prewarm: prewarm,
        cacheIdentity: (effectiveLine, nextTimestamp, karaokeLyricsMode),
        line: effectiveLine,
        synthetic: !hasTimedKaraoke,
        active: active,
        position: animatedPosition,
        positionListenable: active ? positionListenable : null,
        isPlaying: active && isPlaying,
        normalExit: normalExit,
        normalEntry: normalEntry,
        playbackRate: playbackRate,
        playbackRateListenable: playbackRateListenable,
        actualPlaybackListenable: actualPlaybackListenable,
        seekPositionListenable: seekPositionListenable,
        playedColor: resolvedActiveColor,
        unplayedColor: karaokeUnplayedColor,
        textAlign: textAlign,
      );
    }

    // Karaoke listens directly from its painter, so playback ticks repaint
    // only its cached custom-paint surface and never rebuild the lyric row.
    // Interludes also subscribe inside their retained paint surface. Changing
    // between a ValueListenableBuilder and a direct child used to destroy the
    // active interlude State at exactly the frame its exit should start.
    final lyric = buildLyric(position);
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
    final blurredLyric = lineBlurEnabled
        // Cache the filtered result below animated alpha/scale as well as
        // the shaped source. Static distant rows can reuse the whole layer.
        ? RepaintBoundary(
            key: const ValueKey('mobile_lyric_cached_blur'),
            child: _AnimatedLyricBlur(
              contentCenter: contentCenter,
              viewportHeight: viewportHeight,
              scrollController: scrollController,
              edgeEnabled:
                  !active &&
                  !lineBlurSuppressed &&
                  !browseHighlighted &&
                  !(line.isInterlude && normalExit),
              snapToTarget: _snapPresentation,
              preservePhase: true,
              sigma: sigma,
              // All moving rows use cached discrete steps, including the focus
              // handoff. Dense bilingual boundaries must not rebuild blur
              // textures continuously on top of changing glyph paint.
              motion: frameClock.visualMoving,
              animateFocusHandoff: active && normalEntry,
              curve: focusCurve,
              duration: focusDuration,
              child: RepaintBoundary(child: lyricPaintLayer),
            ),
          )
        : lyricPaintLayer;
    final effectiveLyric = LyricPhaseOpacity(
      snapToTarget: _snapPresentation,
      preservePhase: true,
      key: const ValueKey('mobile_lyric_distance_opacity'),
      duration: focusDuration,
      curve: focusCurve,
      opacity: line.isInterlude && normalExit
          ? 1
          : karaokeLyricsEnabled && !browseHighlighted
          ? 1
          : !browseHighlighted
          ? _opacity
          : 1,
      child: blurredLyric,
    );
    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: mobileLyricsHorizontalInset(textAlign),
        ),
        child: _withLineShift(
          FractionallySizedBox(
            key: const ValueKey('mobile_lyric_scale_safe_content'),
            widthFactor: 1 / mobileLyricsActiveScale,
            heightFactor: 1 / mobileLyricsActiveScale,
            alignment: _alignment,
            child: LyricPhaseScale(
              snapToTarget: _snapPresentation,
              preservePhase: true,
              scale: _scale,
              duration: focusDuration,
              curve: focusCurve,
              alignment: _alignment,
              // Keep the expensive glyph and glow raster below the transform.
              // The scale-safe parent reserves the transformed paint bounds, so
              // sliver culling cannot remove a still-visible departing line.
              child: RepaintBoundary(
                key: const ValueKey('mobile_lyric_scaled_paint'),
                child: LyricPhaseTextStyle(
                  snapToTarget: _snapPresentation,
                  preservePhase: true,
                  key: ValueKey(styleIdentity),
                  duration: focusDuration,
                  curve: focusCurve,
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

  Widget _staticKaraokeLyric(Color inactiveColor) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: line.texts.isEmpty ? '' : line.texts.first),
        if (line.texts.length > 1)
          TextSpan(
            text: '\n${line.texts.skip(1).join('\n')}',
            style: TextStyle(
              color: inactiveColor.withValues(alpha: inactiveColor.a * .6),
            ),
          ),
      ],
    ),
    textAlign: textAlign,
  );
}

class _AnimatedLyricBlur extends ImplicitlyAnimatedWidget {
  const _AnimatedLyricBlur({
    required this.contentCenter,
    required this.viewportHeight,
    required this.scrollController,
    required this.edgeEnabled,
    required this.sigma,
    required super.duration,
    required this.child,
    this.motion,
    this.animateFocusHandoff = false,
    this.preservePhase = false,
    this.snapToTarget = false,
    super.curve = mobileLyricsFocusTransitionCurve,
  });

  final double sigma;
  final double contentCenter;
  final double viewportHeight;
  final ScrollController scrollController;
  final bool edgeEnabled;
  final Widget child;
  final ValueListenable<bool>? motion;
  final bool animateFocusHandoff;
  final bool preservePhase;
  final bool snapToTarget;

  @override
  ImplicitlyAnimatedWidgetState<_AnimatedLyricBlur> createState() =>
      _AnimatedLyricBlurState();
}

class _AnimatedLyricBlurState
    extends AnimatedWidgetBaseState<_AnimatedLyricBlur>
    with LyricPhaseRetarget<_AnimatedLyricBlur> {
  Tween<double>? _sigma;

  @override
  bool get preserveLyricPhase => widget.preservePhase;
  @override
  bool get snapLyricPhase => widget.snapToTarget;

  bool get _staticDuringMotion =>
      (widget.motion?.value ?? false) && !widget.animateFocusHandoff;

  @override
  void initState() {
    super.initState();
    widget.motion?.addListener(_motionChanged);
  }

  void _holdTarget() {
    if (!_staticDuringMotion) return;
    controller.stop();
    _sigma?.begin = widget.sigma;
    _sigma?.end = widget.sigma;
  }

  void _motionChanged() {
    _holdTarget();
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _AnimatedLyricBlur oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.motion != widget.motion) {
      oldWidget.motion?.removeListener(_motionChanged);
      widget.motion?.addListener(_motionChanged);
    }
    _holdTarget();
  }

  @override
  void dispose() {
    widget.motion?.removeListener(_motionChanged);
    super.dispose();
  }

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
    final sigma = _staticDuringMotion
        ? widget.sigma
        : _sigma?.evaluate(animation) ?? widget.sigma;
    return LyricViewportBlur(
      key: const ValueKey('mobile_lyric_blur_filter'),
      sigma: sigma,
      contentCenter: widget.contentCenter,
      viewportHeight: widget.viewportHeight,
      scrollController: widget.scrollController,
      edgeEnabled: widget.edgeEnabled,
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
    required this.entryPreparing,
    required this.seekTargetPosition,
    required this.cacheIdentity,
    required this.frameClock,
    required this.prewarm,
    required this.line,
    required this.synthetic,
    required this.active,
    required this.position,
    required this.positionListenable,
    required this.isPlaying,
    required this.normalExit,
    required this.normalEntry,
    required this.playbackRate,
    required this.playbackRateListenable,
    required this.actualPlaybackListenable,
    required this.seekPositionListenable,
    required this.playedColor,
    required this.unplayedColor,
    required this.textAlign,
  });

  final Object cacheIdentity;
  final bool entryPreparing;
  final Duration? seekTargetPosition;
  final LyricFrameClock frameClock;
  final _KaraokePrewarmSlot prewarm;
  final LyricLine line;
  final bool synthetic;
  final bool active;
  final Duration position;
  final ValueListenable<Duration>? positionListenable;
  final bool isPlaying;
  final bool normalExit;
  final bool normalEntry;
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
  bool _followingFrames = false;
  Duration _frameOrigin = Duration.zero;
  late final KaraokeMediaClock _clock;
  late final AnimationController _exitController;
  late final AnimationController _entryController;
  double _exitStartStrength = 1;
  bool _isExiting = false;
  _KaraokePaintCache? _paintCache;
  _KaraokePaintStyle? _paintStyle;
  bool _preparationScheduled = false;
  bool _imageRequested = false;
  int _cacheGeneration = 0;
  Timer? _preparationTimer;

  @override
  void initState() {
    super.initState();
    final initialPosition =
        widget.seekTargetPosition ??
        widget.positionListenable?.value ??
        widget.position;
    _clock = KaraokeMediaClock(initialPosition, rate: _playbackRate);
    if (widget.seekTargetPosition != null) {
      _clock.seek(initialPosition, protectFromStaleSource: true);
    }
    _entryController = AnimationController(
      vsync: this,
      duration: karaokeDefaultMotion.exitDuration,
      value: widget.active ? 1 : 0,
    );
    _exitController =
        AnimationController(
          vsync: this,
          duration: karaokeDefaultMotion.exitDuration,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            _isExiting = false;
            _entryController.value = 0;
            _clock.seek(
              widget.line.timestamp - const Duration(milliseconds: 120),
            );
            _exitController.value = 0;
          }
        });
    widget.prewarm.mounted.add(widget.cacheIdentity);
    widget.prewarm.warmers[widget.cacheIdentity] = _prepareImage;
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
    final sourceChanged =
        oldWidget.positionListenable != widget.positionListenable;
    if (sourceChanged) {
      oldWidget.positionListenable?.removeListener(_readSourcePosition);
      widget.positionListenable?.addListener(_readSourcePosition);
    }
    if (widget.entryPreparing || widget.seekTargetPosition != null) {
      // A retained exit/entry clock must not wake up after the page is visible.
      // Keep the shaped cache; only calibrate media time and ink envelopes.
      _isExiting = false;
      _exitController.stop();
      _exitController.value = 0;
      _entryController.stop();
      _entryController.value = widget.active ? 1 : 0;
      _stopFollowingFrames();
      _resetVisualPosition();
      _syncTickerState();
    } else if (oldWidget.active &&
        !widget.active &&
        widget.normalExit &&
        oldWidget.cacheIdentity == widget.cacheIdentity) {
      _exitStartStrength = Curves.easeOutCubic.transform(
        _entryController.value,
      );
      _entryController.stop();
      _isExiting = true;
      _clock.freeze();
      _exitController.forward(from: 0);
    } else if (!oldWidget.active && widget.active) {
      _isExiting = false;
      _exitController.stop();
      _exitController.value = 0;
      _resetVisualPosition();
      // Explicit seek positions already match the target; only normal focus
      // handoffs animate brightness, independently of the media sweep.
      if (widget.normalEntry) {
        _entryController.forward(from: 0);
      } else {
        _entryController.value = 1;
      }
    } else if (!_isExiting &&
        (sourceChanged ||
            (widget.positionListenable == null &&
                oldWidget.position != widget.position))) {
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
    if (oldWidget.prewarm != widget.prewarm ||
        oldWidget.cacheIdentity != widget.cacheIdentity) {
      oldWidget.prewarm.mounted.remove(oldWidget.cacheIdentity);
      oldWidget.prewarm.warmers.remove(oldWidget.cacheIdentity);
      widget.prewarm.mounted.add(widget.cacheIdentity);
      widget.prewarm.warmers[widget.cacheIdentity] = _prepareImage;
      _isExiting = false;
      _exitController.stop();
      _exitController.value = 0;
      _entryController.value = widget.active ? 1 : 0;
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
    if (_followingFrames) widget.frameClock.removeListener(_tickPosition);
    widget.prewarm.mounted.remove(widget.cacheIdentity);
    widget.prewarm.warmers.remove(widget.cacheIdentity);
    _preparationTimer?.cancel();
    _exitController.dispose();
    _entryController.dispose();
    _clock.dispose();
    _paintCache?.dispose();
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
    _isExiting = false;
    _exitController.stop();
    _exitController.value = 0;
    _entryController.stop();
    _entryController.value = widget.active ? 1 : 0;
    _clock.seek(
      widget.active
          ? target
          : widget.line.timestamp - const Duration(milliseconds: 120),
      protectFromStaleSource: widget.active,
    );
  }

  void _resetVisualPosition() => _clock.seek(
    widget.seekTargetPosition ?? _sourcePosition,
    protectFromStaleSource: widget.seekTargetPosition != null,
  );

  void _readSourcePosition() => _clock.readSource(_sourcePosition);

  void _syncTickerState() {
    if (_isExiting) {
      _stopFollowingFrames();
      _clock.freeze();
      return;
    }
    // A static position is primarily used by previews and tests. Only keep a
    // frame clock alive when a real playback position source can correct it.
    if (widget.isPlaying &&
        (widget.actualPlaybackListenable?.value ?? true) &&
        widget.positionListenable != null) {
      if (!_followingFrames) {
        _clock.setRunning(true, _sourcePosition);
        _followingFrames = true;
        widget.frameClock.addListener(_tickPosition);
        _frameOrigin = widget.frameClock.elapsed;
      }
      return;
    }
    _stopFollowingFrames();
    _clock.setRunning(false, _sourcePosition);
  }

  void _tickPosition() => _clock.tick(widget.frameClock.elapsed - _frameOrigin);

  void _stopFollowingFrames() {
    if (!_followingFrames) return;
    _followingFrames = false;
    widget.frameClock.removeListener(_tickPosition);
  }

  void _rebuildCache() {
    _preparationTimer?.cancel();
    _cacheGeneration++;
    _preparationScheduled = false;
    _imageRequested = false;
    _paintCache?.dispose();
    _paintCache = null;
    _text = widget.line.texts.join('\n');
    _ranges = _karaokeRanges(widget.line);
  }

  void _prepareImage() {
    _imageRequested = true;
    _paintCache?.prepareImage();
  }

  void _prepareNextAfterFrame(
    double width,
    TextStyle style,
    TextDirection direction,
    TextScaler scaler,
    Locale? locale,
    double pixelRatio,
  ) {
    if (_preparationScheduled) return;
    _preparationScheduled = true;
    final generation = _cacheGeneration;
    // Only the immediate next mounted row requests this job. Run after paint,
    // not in the scroll/layout callback; revalidate before adopting ownership.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _cacheGeneration) return;
      _preparationTimer = Timer(Duration.zero, () {
        _preparationTimer = null;
        if (!mounted || generation != _cacheGeneration) return;
        _preparationScheduled = false;
        if (_paintCache != null) return;
        final prepared =
            widget.prewarm.take(widget.cacheIdentity) ??
            _KaraokePaintCache(
              text: _text,
              ranges: _ranges,
              synthetic: widget.synthetic,
              width: width,
              style: style,
              textAlign: widget.textAlign,
              textDirection: direction,
              textScaler: scaler,
              locale: locale,
              pixelRatio: pixelRatio,
            );
        _paintCache = prepared;
        if (_imageRequested || !widget.active) prepared.prepareImage();
        setState(() {});
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final inheritedStyle = DefaultTextStyle.of(context).style;
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        var cache = _paintCache;
        if (cache == null &&
            !widget.active &&
            !_isExiting &&
            widget.frameClock.visualMoving.value) {
          _prepareNextAfterFrame(
            maxWidth,
            inheritedStyle,
            textDirection,
            textScaler,
            locale,
            pixelRatio,
          );
          return Text.rich(
            TextSpan(
              children: [
                TextSpan(text: widget.line.texts.first),
                if (widget.line.texts.length > 1)
                  TextSpan(
                    text: '\n${widget.line.texts.skip(1).join('\n')}',
                    style: TextStyle(
                      color: widget.unplayedColor.withValues(
                        alpha: widget.unplayedColor.a * .6,
                      ),
                    ),
                  ),
              ],
            ),
            textAlign: widget.textAlign,
          );
        }
        if (cache == null ||
            !cache.matches(
              maxWidth,
              inheritedStyle,
              widget.textAlign,
              textDirection,
              textScaler,
              locale,
              pixelRatio,
            )) {
          cache?.dispose();
          cache = widget.prewarm.take(widget.cacheIdentity);
          if (cache != null &&
              !cache.matches(
                maxWidth,
                inheritedStyle,
                widget.textAlign,
                textDirection,
                textScaler,
                locale,
                pixelRatio,
              )) {
            cache.dispose();
            cache = null;
          }
          cache ??= _KaraokePaintCache(
            text: _text,
            ranges: _ranges,
            synthetic: widget.synthetic,
            width: maxWidth,
            style: inheritedStyle,
            textAlign: widget.textAlign,
            textDirection: textDirection,
            textScaler: textScaler,
            locale: locale,
            pixelRatio: pixelRatio,
          );
          _paintCache = cache;
        }
        if (widget.active || _isExiting) cache.prepareImage();
        var colors = _paintStyle;
        if (colors == null ||
            colors.active != widget.playedColor ||
            colors.inactive != widget.unplayedColor) {
          colors = _KaraokePaintStyle(widget.playedColor, widget.unplayedColor);
          _paintStyle = colors;
        }
        return Semantics(
          label: _text,
          child: SizedBox(
            width: maxWidth,
            height: cache.height,
            child: CustomPaint(
              key: const ValueKey('mobile_karaoke_single_pass_paint'),
              isComplex: true,
              willChange: widget.active || _isExiting,
              painter: _SinglePassKaraokePainter(
                cache: cache,
                colors: colors,
                positionListenable: _clock,
                exitAnimation: _exitController,
                isExiting: _isExiting,
                entryAnimation: _entryController,
                exitStartStrength: _exitStartStrength,
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
