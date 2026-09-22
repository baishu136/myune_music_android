import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/widgets/interlude_animation_widget.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';

void main() {
  test('visual clock advances uniformly at 60 and 120 Hz without drift', () {
    for (final step in [8333, 16667]) {
      var current = Duration.zero;
      for (var frame = 1; frame <= 120; frame++) {
        final target = Duration(microseconds: step * frame);
        current = karaokeAdvanceVisualClock(
          current,
          target,
          Duration(microseconds: step),
        );
        expect(current, target);
      }
    }
  });
  test('ordinary clock correction never reverses or stalls glyph motion', () {
    const current = Duration(seconds: 2);
    const step = Duration(milliseconds: 16);
    for (final drift in [-80000, -20000, 20000, 80000]) {
      final next = karaokeAdvanceVisualClock(
        current,
        current + step + Duration(microseconds: drift),
        step,
      );
      expect((next - current).inMicroseconds, inInclusiveRange(14720, 17280));
    }
  });
  test('visual clock re-anchors continuously across playback rates', () {
    for (final rate in [.75, 1.0, 1.5, 2.0]) {
      const anchor = Duration(seconds: 10);
      const anchorElapsed = Duration(milliseconds: 300);
      final target = karaokeVisualClockTarget(
        anchor,
        const Duration(milliseconds: 500),
        anchorElapsed,
        rate,
      );
      expect(target.inMicroseconds, 10000000 + (200000 * rate).round());
      expect(
        karaokeVisualClockTarget(
          target,
          const Duration(milliseconds: 500),
          const Duration(milliseconds: 500),
          1,
        ),
        target,
      );
    }
    // Pausing freezes the anchor; resuming at a new ticker origin is continuous.
    const pausedAt = Duration(milliseconds: 10750);
    expect(
      karaokeVisualClockTarget(pausedAt, Duration.zero, Duration.zero, 1.5),
      pausedAt,
    );
    expect(
      karaokeVisualClockTarget(
        pausedAt,
        const Duration(milliseconds: 100),
        Duration.zero,
        1.5,
      ),
      const Duration(milliseconds: 10900),
    );
  });
  test(
    'fractional and double speed motion stays monotonic over many frames',
    () {
      for (final rate in [.75, 1.0, 1.5, 2.0]) {
        var visual = const Duration(seconds: 4);
        final anchor = visual;
        for (var frame = 1; frame <= 600; frame++) {
          final elapsed = Duration(microseconds: frame * 16667);
          final target = karaokeVisualClockTarget(
            anchor,
            elapsed,
            Duration.zero,
            rate,
          );
          final next = karaokeAdvanceVisualClock(
            visual,
            target,
            const Duration(microseconds: 16667),
            playbackRate: rate,
          );
          expect(next, greaterThan(visual));
          visual = next;
        }
        final target = karaokeVisualClockTarget(
          anchor,
          const Duration(microseconds: 600 * 16667),
          Duration.zero,
          rate,
        );
        expect((visual - target).inMicroseconds.abs(), lessThan(15000));
      }
    },
  );
  test('all-lyrics karaoke timing follows most of the next line interval', () {
    final line = LyricLine(
      timestamp: const Duration(seconds: 10),
      texts: const ['逐字显示', 'translation'],
    );
    final synthesized = synthesizeKaraokeTiming(
      line,
      nextTimestamp: const Duration(seconds: 15),
    );

    expect(synthesized.isKaraoke, isTrue);
    expect(synthesized.tokens, hasLength(2));
    expect(synthesized.tokens!.first.map((token) => token.text).join(), '逐字显示');
    expect(
      synthesized.tokens!.first.last.end,
      const Duration(milliseconds: 14600),
    );
    expect(synthesized.tokens!.first, hasLength(4));
    expect(synthesized.tokens![1], isEmpty);
    expect(karaokeRowCanHighlight(0), isTrue);
    expect(karaokeRowCanHighlight(1), isFalse);
  });

  test('translation-only timing never enables karaoke highlighting', () {
    final line = LyricLine(
      timestamp: Duration.zero,
      texts: const ['Original', '翻译'],
      tokens: [
        const <LyricToken>[],
        [
          LyricToken(
            text: '翻译',
            start: Duration.zero,
            end: const Duration(seconds: 1),
          ),
        ],
      ],
    );
    expect(hasUsableKaraokeTiming(line), isFalse);
  });

  test('karaoke token progress is continuous and bounded', () {
    final token = LyricToken(
      text: 'word',
      start: const Duration(seconds: 1),
      end: const Duration(seconds: 3),
    );
    expect(karaokeTokenProgress(token, Duration.zero), 0);
    expect(
      karaokeTokenProgress(token, const Duration(seconds: 2)),
      closeTo(.5, .0001),
    );
    expect(karaokeTokenProgress(token, const Duration(seconds: 4)), 1);
  });

  test('karaoke tokens receive a bounded lead-in and finish on time', () {
    final shortToken = LyricToken(
      text: 'Time',
      start: const Duration(seconds: 1),
      end: const Duration(milliseconds: 1100),
    );
    expect(
      karaokeVisualTokenProgress(shortToken, const Duration(milliseconds: 820)),
      0,
    );
    expect(
      karaokeVisualTokenProgress(
        shortToken,
        const Duration(milliseconds: 1050),
      ),
      closeTo(.6, .001),
    );
    expect(
      karaokeVisualTokenProgress(
        shortToken,
        const Duration(milliseconds: 1100),
      ),
      1,
    );

    final longToken = LyricToken(
      text: 'progress',
      start: const Duration(seconds: 2),
      end: const Duration(seconds: 3),
    );
    expect(
      karaokeVisualTokenProgress(longToken, const Duration(milliseconds: 2250)),
      closeTo(295 / 1045, .001),
    );
    expect(
      karaokeVisualTokenProgress(longToken, const Duration(milliseconds: 1954)),
      0,
    );
    expect(
      karaokeVisualTokenProgress(longToken, longToken.start),
      greaterThan(0),
    );
    expect(karaokeVisualTokenProgress(longToken, longToken.end), 1);
  });

  test('rapid tokens and their final glyph finish exactly on time', () {
    for (final durationMs in [40, 80, 100, 180, 300, 519]) {
      final token = LyricToken(
        text: 'quick',
        start: const Duration(seconds: 1),
        end: Duration(milliseconds: 1000 + durationMs),
      );
      final progress = karaokeVisualTokenProgress(token, token.end);
      expect(progress, 1);
      expect(karaokeGlyphProgress(progress, glyphIndex: 4, glyphCount: 5), 1);
      expect(
        karaokeVisualTokenProgress(token, const Duration(milliseconds: 939)),
        0,
      );
    }
  });

  test(
    'karaoke glyph progress creates a smooth overlapping character wave',
    () {
      final progresses = List.generate(
        4,
        (index) => karaokeGlyphProgress(.5, glyphIndex: index, glyphCount: 4),
      );
      expect(progresses[0], 1);
      expect(progresses[1], greaterThan(progresses[2]));
      expect(progresses[2], greaterThan(progresses[3]));
      expect(progresses[3], 0);
      expect(
        karaokeGlyphProgress(.2, glyphIndex: 0, glyphCount: 4),
        greaterThan(0),
      );
      expect(karaokeGlyphProgress(.2, glyphIndex: 3, glyphCount: 4), 0);
      for (var index = 0; index < 4; index++) {
        expect(karaokeGlyphProgress(0, glyphIndex: index, glyphCount: 4), 0);
        expect(karaokeGlyphProgress(1, glyphIndex: index, glyphCount: 4), 1);
      }
    },
  );

  test('long words keep the highlight wave limited to adjacent glyphs', () {
    final progresses = List.generate(
      9,
      (index) => karaokeGlyphProgress(.5, glyphIndex: index, glyphCount: 9),
    );
    final transitioning = progresses.where((value) => value > 0 && value < 1);
    expect(transitioning.length, lessThanOrEqualTo(2));
    expect(progresses.take(3), everyElement(1));
    expect(progresses.skip(6), everyElement(0));
  });

  test(
    'each glyph finishes rising when the next glyph starts highlighting',
    () {
      for (final count in [2, 4, 9, 16]) {
        for (var index = 0; index < count - 1; index++) {
          final ownStart = karaokeGlyphHighlightStart(index, count);
          final start = index == 0
              ? 0.0
              : karaokeGlyphHighlightStart(index - 1, count);
          final nextStart = karaokeGlyphHighlightStart(index + 1, count);
          expect(
            karaokeGlyphProgress(
              nextStart,
              glyphIndex: index + 1,
              glyphCount: count,
            ),
            0,
          );
          expect(
            karaokeGlyphLiftProgress(
              ownStart,
              glyphIndex: index,
              glyphCount: count,
            ),
            index == 0 ? 0 : greaterThan(0),
          );
          expect(
            karaokeGlyphLiftProgress(
              start,
              glyphIndex: index,
              glyphCount: count,
            ),
            0,
          );
          expect(
            karaokeGlyphLiftProgress(
              nextStart,
              glyphIndex: index,
              glyphCount: count,
            ),
            1,
          );
          expect(
            karaokeGlyphLiftFactor(
              nextStart,
              glyphIndex: index,
              glyphCount: count,
            ),
            1,
          );
          expect(
            karaokeGlyphLiftProgress(
              (start + nextStart) / 2,
              glyphIndex: index,
              glyphCount: count,
            ),
            closeTo(.5, 1e-9),
          );
          expect(
            karaokeGlyphLiftProgress(
              nextStart - (nextStart - start) / 100,
              glyphIndex: index,
              glyphCount: count,
            ),
            lessThan(1),
          );
        }
      }
    },
  );

  test('word and sentence tails finish at their own highlight pace', () {
    for (final count in [1, 2, 4, 9]) {
      final last = count - 1;
      final start = count == 1
          ? 0.0
          : karaokeGlyphHighlightStart(last - 1, count);
      expect(
        karaokeGlyphLiftProgress(
          (start + 1) / 2,
          glyphIndex: last,
          glyphCount: count,
        ),
        closeTo(.5, 1e-9),
      );
      expect(
        karaokeGlyphLiftProgress(1, glyphIndex: last, glyphCount: count),
        1,
      );
    }
  });

  test('a longer lift window makes the character wave slow and continuous', () {
    const count = 9;
    const index = 4;
    final previousStart = karaokeGlyphHighlightStart(index - 1, count);
    final ownStart = karaokeGlyphHighlightStart(index, count);
    final nextStart = karaokeGlyphHighlightStart(index + 1, count);
    expect(
      nextStart - previousStart,
      closeTo(2 * (nextStart - ownStart), 1e-9),
    );
    expect(
      karaokeGlyphLiftProgress(ownStart, glyphIndex: index, glyphCount: count),
      closeTo(.5, 1e-9),
    );
    final token = LyricToken(
      text: 'continuous',
      start: const Duration(seconds: 1),
      end: const Duration(seconds: 2),
    );
    final lead = karaokeGlyphLiftLeadInProgress(token, count);
    expect(lead, greaterThan(0));
    expect(lead, lessThanOrEqualTo(karaokeGlyphHighlightStart(1, count)));
    expect(
      karaokeGlyphLiftProgress(
        -lead,
        glyphIndex: 0,
        glyphCount: count,
        leadInProgress: lead,
      ),
      0,
    );
    expect(
      karaokeGlyphLiftProgress(
        0,
        glyphIndex: 0,
        glyphCount: count,
        leadInProgress: lead,
      ),
      greaterThan(0),
    );
    expect(
      karaokeGlyphLiftProgress(
        karaokeGlyphHighlightStart(1, count),
        glyphIndex: 0,
        glyphCount: count,
        leadInProgress: lead,
      ),
      1,
    );
  });

  test('adjacent Chinese token finishes as the next character begins', () {
    final current = LyricToken(
      text: '你',
      start: const Duration(milliseconds: 100),
      end: const Duration(milliseconds: 300),
    );
    final next = LyricToken(
      text: '好',
      start: const Duration(milliseconds: 300),
      end: const Duration(milliseconds: 500),
    );
    final boundary = karaokeNextTokenStartProgress(current, next)!;
    expect(boundary, greaterThan(0));
    expect(boundary, lessThan(1));
    final nextHighlight = karaokeVisualTokenProgress(
      next,
      karaokeVisualTokenStart(next),
    );
    expect(nextHighlight, 0);
    expect(
      karaokeGlyphLiftProgress(
        boundary,
        glyphIndex: 0,
        glyphCount: 1,
        nextTokenStartProgress: boundary,
      ),
      1,
    );
    expect(
      karaokeGlyphLiftProgress(
        boundary / 2,
        glyphIndex: 0,
        glyphCount: 1,
        nextTokenStartProgress: boundary,
      ),
      closeTo(.5, 1e-9),
    );
  });

  test('karaoke relay ends after five followers instead of lifting a row', () {
    expect(karaokeFollowerLiftHeights, [.20, .15, .10, .05, .02]);
    final own = [1.0, ...List.filled(18, 0.0)];
    final factors = karaokeChainedLiftFactors(
      own,
      sourceStartTimesUs: List.filled(own.length, 0),
      positionUs: 1000000,
      lineCadenceUs: 100000,
    );
    expect(factors.take(7), [1, .20, .15, .10, .05, .02, 0]);
    expect(factors.skip(6), everyElement(0));
    expect(karaokeFollowerLiftFactor(1000000, 6, 100000), 0);
    expect(karaokeFollowerLiftFactor(0, 1, 100000), 0);
  });

  test('karaoke relay uses own progress only and respects token breaks', () {
    expect(
      karaokeChainedLiftFactors(
        [1, 0, 0, 0, 0, 0, 0],
        sourceStartTimesUs: List.filled(7, 0),
        positionUs: 1000000,
        lineCadenceUs: 100000,
        breakBefore: {3},
      ),
      [1, .20, .15, 0, 0, 0, 0],
    );
    final overlapping = karaokeChainedLiftFactors(
      [.5, .25, 0, 0, 0, 0, 0, 0],
      sourceStartTimesUs: List.filled(8, 0),
      positionUs: 1000000,
      lineCadenceUs: 100000,
    );
    expect(overlapping[2], greaterThan(0));
    expect(overlapping[7], 0, reason: 'a relay must never relay itself');
  });

  test('follower delay tracks the lyric line character cadence', () {
    final fastToken = LyricToken(
      text: 'fastline',
      start: Duration.zero,
      end: const Duration(milliseconds: 400),
    );
    final slowToken = LyricToken(
      text: 'slowline',
      start: Duration.zero,
      end: const Duration(milliseconds: 1600),
    );
    final fastCadence = karaokeLineGlyphCadenceUs([fastToken], 8);
    final slowCadence = karaokeLineGlyphCadenceUs([slowToken], 8);
    expect(fastCadence, 50000);
    expect(slowCadence, 200000);
    expect(karaokeFollowerLiftFactor(20000, 1, fastCadence), greaterThan(0));
    expect(karaokeFollowerLiftFactor(20000, 1, slowCadence), 0);
    expect(
      karaokeFollowerLiftFactor(20000, 1, fastCadence),
      greaterThan(karaokeFollowerLiftFactor(20000, 1, slowCadence)),
    );
    expect(
      karaokeFollowerLiftFactor(fastCadence * 1.27, 1, fastCadence),
      closeTo(.20, 1e-9),
    );
    expect(
      karaokeFollowerLiftFactor(slowCadence * 1.27, 1, slowCadence),
      closeTo(.20, 1e-9),
    );
  });

  test('local token cadence responds to mixed pace without tail drag', () {
    final tokens = [
      LyricToken(
        text: '快速',
        start: Duration.zero,
        end: const Duration(milliseconds: 100),
      ),
      LyricToken(
        text: '慢慢',
        start: const Duration(milliseconds: 100),
        end: const Duration(milliseconds: 500),
      ),
      LyricToken(
        text: '快',
        start: const Duration(milliseconds: 500),
        end: const Duration(milliseconds: 550),
      ),
      LyricToken(
        text: '啊',
        start: const Duration(milliseconds: 550),
        end: const Duration(milliseconds: 3000),
      ),
    ];
    final local = karaokeLocalGlyphCadencesUs(tokens, [2, 2, 1, 1]);
    expect(local.length, 6);
    expect(local[0], lessThan(local[2]));
    expect(local[3], greaterThan(local[4]));
    expect(
      local[4],
      lessThan(120000),
      reason: 'a sustained tail must not slow the preceding fast glyph',
    );
    expect(local.last, lessThan(260000));
    final firstAt20ms = karaokeFollowerLiftFactor(20000, 1, local.first);
    final slowAt20ms = karaokeFollowerLiftFactor(20000, 1, local[2]);
    expect(firstAt20ms, greaterThan(slowAt20ms));
    for (var i = 1; i < local.length; i++) {
      expect(local[i] / local[i - 1], lessThan(3));
    }
  });

  test(
    'local cadence preserves bounded non-recursive relay and pause break',
    () {
      final tokens = [
        LyricToken(
          text: 'AB',
          start: Duration.zero,
          end: const Duration(milliseconds: 100),
        ),
        LyricToken(
          text: 'CD',
          start: const Duration(milliseconds: 100),
          end: const Duration(milliseconds: 500),
        ),
        LyricToken(
          text: 'EFGH',
          start: const Duration(milliseconds: 900),
          end: const Duration(milliseconds: 1300),
        ),
      ];
      final cadence = karaokeLocalGlyphCadencesUs(tokens, [2, 2, 4]);
      final factors = karaokeChainedLiftFactors(
        [1, 0, 0, 0, 0, 0, 0, 0],
        sourceStartTimesUs: List.filled(8, 0),
        positionUs: 1000000,
        lineCadenceUs: 100000,
        sourceCadencesUs: cadence,
        breakBeforeFlags: [
          false,
          false,
          false,
          false,
          true,
          false,
          false,
          false,
        ],
      );
      expect(factors, [1, .20, .15, .10, 0, 0, 0, 0]);
      final five = karaokeChainedLiftFactors(
        [1, ...List<double>.filled(7, 0)],
        sourceStartTimesUs: List.filled(8, 0),
        positionUs: 1000000,
        lineCadenceUs: 100000,
        sourceCadencesUs: cadence,
      );
      expect(five[5], .02);
      expect(five[6], 0);
    },
  );

  test('local follower motion remains continuous through a pace change', () {
    final cadence = karaokeLocalGlyphCadencesUs(
      [
        LyricToken(
          text: '快',
          start: Duration.zero,
          end: const Duration(milliseconds: 50),
        ),
        LyricToken(
          text: '慢',
          start: const Duration(milliseconds: 50),
          end: const Duration(milliseconds: 250),
        ),
      ],
      [1, 1],
    );
    for (final pace in cadence) {
      var prior = 0.0;
      for (var elapsed = 0; elapsed <= 400000; elapsed += 1000) {
        final next = karaokeFollowerLiftFactor(elapsed.toDouble(), 1, pace);
        expect(next, greaterThanOrEqualTo(prior));
        expect(next - prior, lessThan(.01));
        prior = next;
      }
      expect(prior, closeTo(.20, 1e-9));
    }
  });
  test('karaoke glyph relay is continuous and every glyph reaches the top', () {
    for (final glyphCount in [1, 2, 4, 9]) {
      for (var glyph = 0; glyph < glyphCount; glyph++) {
        var previous = 0.0;
        for (var frame = 0; frame <= 1000; frame++) {
          final tokenProgress = frame / 1000;
          final lift = karaokeGlyphLiftFactor(
            tokenProgress,
            glyphIndex: glyph,
            glyphCount: glyphCount,
          );
          expect(lift, greaterThanOrEqualTo(previous - 1e-9));
          expect(lift - previous, lessThan(.03));
          previous = lift;
        }
        expect(previous, 1);
      }
    }
  });

  test('short words and Chinese glyphs receive a delayed relay', () {
    expect(karaokeGlyphLiftFactor(0, glyphIndex: 0, glyphCount: 1), 0);
    expect(
      karaokeGlyphLiftFactor(.5, glyphIndex: 0, glyphCount: 1),
      closeTo(karaokeLiftCurve(.5), 1e-12),
    );
    expect(karaokeGlyphLiftFactor(1, glyphIndex: 0, glyphCount: 1), 1);

    final firstChinese = karaokeGlyphLiftFactor(
      .35,
      glyphIndex: 0,
      glyphCount: 2,
    );
    final nextChinese = karaokeGlyphLiftFactor(
      .35,
      glyphIndex: 1,
      glyphCount: 2,
    );
    expect(firstChinese, greaterThan(0));
    expect(
      nextChinese,
      greaterThan(0),
      reason: 'a later glyph follows before its own highlight',
    );
    expect(nextChinese, lessThan(firstChinese));
  });

  test('the relay crosses nearby tokens but stops at a lyric pause', () {
    final first = LyricToken(
      text: '你',
      start: const Duration(milliseconds: 100),
      end: const Duration(milliseconds: 300),
    );
    final nearby = LyricToken(
      text: '好',
      start: const Duration(milliseconds: 450),
      end: const Duration(milliseconds: 650),
    );
    final afterPause = LyricToken(
      text: '吗',
      start: const Duration(milliseconds: 900),
      end: const Duration(milliseconds: 1100),
    );
    expect(karaokeTokensShareLiftChain(first, nearby), isTrue);
    expect(karaokeTokensShareLiftChain(nearby, afterPause), isFalse);
  });

  test('karaoke highlight is one continuous gradient across glyphs', () {
    expect(
      karaokeContinuousHighlightProgress(
        .5,
        precedingExtent: 0,
        glyphExtent: 10,
        totalExtent: 40,
      ),
      1,
    );
    expect(
      karaokeContinuousHighlightProgress(
        .5,
        precedingExtent: 10,
        glyphExtent: 20,
        totalExtent: 40,
      ),
      .5,
    );
    expect(
      karaokeContinuousHighlightProgress(
        .5,
        precedingExtent: 30,
        glyphExtent: 10,
        totalExtent: 40,
      ),
      0,
    );
    expect(karaokeContinuousGradientFeather(40), closeTo(62, .001));
    final gradient = karaokeContinuousGradient(
      const Rect.fromLTWH(10, 20, 100, 40),
      TextDirection.ltr,
      .5,
      40,
    );
    expect(gradient.start, const Offset(40, 40));
    expect(gradient.end, const Offset(80, 40));
    final startGradient = karaokeContinuousGradient(
      const Rect.fromLTWH(10, 20, 100, 40),
      TextDirection.ltr,
      0,
      40,
    );
    final endGradient = karaokeContinuousGradient(
      const Rect.fromLTWH(10, 20, 100, 40),
      TextDirection.ltr,
      1,
      40,
    );
    expect(startGradient.end.dx, 10);
    expect(endGradient.start.dx, 110);
  });

  test('each karaoke glyph owns an independent local fade gradient', () {
    const bounds = Rect.fromLTWH(10, 20, 20, 40);
    final start = karaokeGlyphHighlightGradient(bounds, TextDirection.ltr, 0);
    final middle = karaokeGlyphHighlightGradient(bounds, TextDirection.ltr, .5);
    final end = karaokeGlyphHighlightGradient(bounds, TextDirection.ltr, 1);
    expect(start.end.dx, bounds.left);
    expect(middle.start.dx, lessThan(bounds.center.dx));
    expect(middle.end.dx, greaterThan(bounds.center.dx));
    expect(end.start.dx, closeTo(bounds.right, .0001));

    final rtlMiddle = karaokeGlyphHighlightGradient(
      bounds,
      TextDirection.rtl,
      .5,
    );
    expect(rtlMiddle.start.dx, greaterThan(rtlMiddle.end.dx));
  });

  test('karaoke character splitting preserves Unicode grapheme clusters', () {
    final combining = karaokeGraphemeRanges('e\u0301你');
    expect(combining, [(start: 0, end: 2), (start: 2, end: 3)]);

    const family = '👨‍👩‍👧‍👦';
    expect(karaokeGraphemeRanges(family), [(start: 0, end: family.length)]);
    expect(karaokeGraphemeRanges(' A ', startOffset: 5), [(start: 6, end: 7)]);
  });

  test('karaoke visual clock correction and highlight edge stay bounded', () {
    expect(karaokePositionBlend(Duration.zero), 0);
    expect(
      karaokePositionBlend(const Duration(milliseconds: 16)),
      inExclusiveRange(.2, .4),
    );
    expect(
      karaokePositionBlend(const Duration(milliseconds: 120)),
      greaterThan(.9),
    );
    expect(karaokeHighlightFeather(10), 4.5);
    expect(karaokeHighlightFeather(50), 8);
    expect(karaokeHighlightFeather(200), 12);
    final ltrGradient = karaokeHighlightGradient(
      const Rect.fromLTWH(10, 20, 100, 30),
      TextDirection.ltr,
      .4,
      8,
    );
    expect(ltrGradient.start, const Offset(50, 35));
    expect(ltrGradient.end, const Offset(58, 35));
    final rtlGradient = karaokeHighlightGradient(
      const Rect.fromLTWH(10, 20, 100, 30),
      TextDirection.rtl,
      .4,
      8,
    );
    expect(rtlGradient.start, const Offset(70, 35));
    expect(rtlGradient.end, const Offset(62, 35));
    expect(
      karaokePlayedClipRect(
        const Rect.fromLTWH(10, 20, 100, 30),
        TextDirection.ltr,
        .4,
      ),
      const Rect.fromLTRB(10, 20, 50, 50),
    );
    expect(
      karaokePlayedClipRect(
        const Rect.fromLTWH(10, 20, 100, 30),
        TextDirection.rtl,
        .4,
      ),
      const Rect.fromLTRB(70, 20, 110, 50),
    );
    expect(karaokeHighlightLift(0, 40), closeTo(0, .001));
    expect(karaokeHighlightLift(.25, 40), closeTo(-.439472, .001));
    expect(karaokeHighlightLift(.5, 40), closeTo(-1.98, .001));
    expect(karaokeHighlightLift(.75, 40), closeTo(-3.294528, .001));
    expect(karaokeHighlightLift(1, 40), closeTo(-3.6, .001));
    expect(
      karaokeHighlightLift(.75, 40),
      lessThan(karaokeHighlightLift(.5, 40)),
    );
    expect(karaokeHighlightLift(.01, 40).abs(), lessThan(.01));
    expect(
      karaokeHighlightLift(.99, 40) - karaokeHighlightLift(1, 40),
      lessThan(.01),
    );
    expect(
      karaokeLiftCurve(.9) - karaokeLiftCurve(.8),
      lessThan(karaokeLiftCurve(.8) - karaokeLiftCurve(.7)),
    );
  });

  test('karaoke clock distinguishes playback ticks from lyric jumps', () {
    expect(
      karaokePlaybackPositionDiscontinuity(
        previousSource: const Duration(seconds: 10),
        source: const Duration(milliseconds: 10400),
        elapsedSinceSource: const Duration(milliseconds: 200),
        playbackRate: 2,
      ),
      isFalse,
    );
    expect(
      karaokePlaybackPositionDiscontinuity(
        previousSource: const Duration(seconds: 10),
        source: const Duration(milliseconds: 10216),
        elapsedSinceSource: const Duration(milliseconds: 200),
      ),
      isFalse,
    );
    expect(
      karaokePlaybackPositionDiscontinuity(
        previousSource: const Duration(seconds: 10),
        source: const Duration(seconds: 42),
        elapsedSinceSource: const Duration(milliseconds: 16),
      ),
      isTrue,
    );
    expect(
      karaokePlaybackPositionDiscontinuity(
        previousSource: const Duration(seconds: 42),
        source: const Duration(seconds: 10),
        elapsedSinceSource: const Duration(milliseconds: 16),
      ),
      isTrue,
    );
  });

  test(
    'karaoke paint excludes token spacing and synthetic timing is natural',
    () {
      expect(karaokeVisibleTokenBounds('  word  '), (start: 2, end: 6));
      expect(karaokeVisibleTokenBounds('   '), isNull);

      final line = LyricLine(
        timestamp: Duration.zero,
        texts: const ["I couldn't wait"],
      );
      final synthesized = synthesizeKaraokeTiming(
        line,
        nextTimestamp: const Duration(seconds: 10),
      );
      final tokens = synthesized.tokens!.single;
      final shortDuration = tokens.first.end - tokens.first.start;
      final longDuration = tokens[1].end - tokens[1].start;
      expect(longDuration, greaterThan(shortDuration * 2));
      expect(tokens.last.end, const Duration(seconds: 8));
    },
  );

  test('zero-duration lyric markers are not treated as usable word timing', () {
    final line = LyricLine(
      timestamp: const Duration(seconds: 2),
      texts: const ['整行标记'],
      tokens: [
        [
          LyricToken(
            text: '整行标记',
            start: const Duration(seconds: 2),
            end: const Duration(seconds: 2),
          ),
        ],
      ],
    );

    expect(hasUsableKaraokeTiming(line), isFalse);
    expect(
      hasUsableKaraokeTiming(
        synthesizeKaraokeTiming(
          line,
          nextTimestamp: const Duration(seconds: 5),
        ),
      ),
      isTrue,
    );
  });

  test('active lyric scale reserves its full paint bounds', () {
    expect(mobileLyricScaleSafeExtent(40), closeTo(44, .001));
    expect(mobileLyricScaleSafeContentWidth(220), closeTo(200, .001));
    expect(mobileLyricsKaraokeLineShift(-1), -.16);
    expect(mobileLyricsKaraokeLineShift(0), 0);
    expect(mobileLyricsKaraokeLineShift(1), .22);
  });

  test('large lyric jumps use a bounded elastic correction', () {
    expect(clampLyricElasticDisplacement(800, 300), closeTo(108, .001));
    expect(clampLyricElasticDisplacement(-800, 300), closeTo(-108, .001));
    expect(clampLyricElasticDisplacement(36, 300), 36);
    expect(clampLyricElasticDisplacement(800, 1000), 156);
    expect(lyricSeekVisibleTravel(220), closeTo(92.4, .001));
    expect(lyricSeekVisibleTravel(1000), 180);
    expect(boundedLyricAnimationStart(0, 900, 300), closeTo(774, .001));
    expect(boundedLyricAnimationStart(100, 150, 300), 100);
    expect(
      boundedLyricAnimationStart(0, 900, 300, fontSize: 36),
      closeTo(804, .001),
    );
    expect(clampLyricElasticDisplacement(800, 1000, fontSize: 36), 140);
  });

  test('stable lyric glow parameters reuse the cached raster layer', () {
    const style = TextStyle(fontSize: 20, height: 1.2);
    const painter = MobileLyricGlowPainter(
      text: '缓存外发光',
      style: style,
      color: Color(0x4DFFFFFF),
      blurRadius: 8,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      locale: Locale('zh', 'CN'),
    );
    const unchanged = MobileLyricGlowPainter(
      text: '缓存外发光',
      style: style,
      color: Color(0x4DFFFFFF),
      blurRadius: 8,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      locale: Locale('zh', 'CN'),
    );
    const changed = MobileLyricGlowPainter(
      text: '缓存外发光',
      style: style,
      color: Color(0x66FFFFFF),
      blurRadius: 8,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      locale: Locale('zh', 'CN'),
    );
    const primaryOnly = MobileLyricGlowPainter(
      text: '缓存外发光\n翻译',
      style: style,
      color: Color(0x4DFFFFFF),
      blurRadius: 8,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      locale: Locale('zh', 'CN'),
      primaryRowOnly: true,
    );

    expect(unchanged.shouldRepaint(painter), isFalse);
    expect(changed.shouldRepaint(painter), isTrue);
    expect(primaryOnly.primaryRowOnly, isTrue);
    expect(primaryOnly.shouldRepaint(painter), isTrue);
  });

  testWidgets(
    'regular mode follows the lyric target without a sticky restart',
    (tester) async {
      final hostKey = GlobalKey<_LyricsHostState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final nextLine = find.byKey(const ValueKey('mobile_lyric_1'));
      final initialY = tester.getCenter(nextLine).dy;
      hostKey.currentState!.setActive(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final earlyY = tester.getCenter(nextLine).dy;
      expect(earlyY, lessThan(initialY));
      expect(earlyY, greaterThan(88));

      await tester.pump(const Duration(milliseconds: 240));
      final middleY = tester.getCenter(nextLine).dy;
      expect(middleY, lessThan(earlyY));
      expect(middleY, greaterThan(88));

      // Advance with real frame-sized ticks: the motion intentionally caps a
      // single frame gap so a resumed app cannot leap after a UI-thread stall.
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(tester.getCenter(nextLine).dy, closeTo(88, 12));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'mobile_lyric_active_hop_',
              ),
        ),
        findsNothing,
      );
    },
  );

  test('lyric blur grows gently with visual distance', () {
    expect(
      mobileLyricsFocusTransitionDuration,
      const Duration(milliseconds: 520),
    );
    expect(mobileLyricBlurSigmaForDistance(0), 0);
    expect(mobileLyricBlurSigmaForDistance(1), .9);
    expect(mobileLyricBlurSigmaForDistance(2), 1.65);
    expect(mobileLyricBlurSigmaForDistance(4), 3);
    expect(mobileLyricBlurSigmaForDistance(20), 3.4);
  });

  test('default lyric motion matches the 620 ms reference cadence', () {
    expect(
      mobileLyricsDefaultScrollTransitionDuration,
      const Duration(milliseconds: 620),
    );
    expect(mobileLyricsDefaultScrollFrequency, 8.8);
    expect(mobileLyricsScrollFrequencyForFontSize(20), 8.8);
    expect(mobileLyricsScrollFrequencyForFontSize(28), closeTo(8, .001));
    expect(mobileLyricsScrollFrequencyForFontSize(36), 7.2);
  });

  testWidgets('next-song lyrics clear an in-flight elastic displacement', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 220,
            child: _LyricsHost(key: hostKey, elasticScrollEnabled: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    hostKey.currentState!.setActive(5);
    await tester.pump();

    hostKey.currentState!.replaceLinesAt(0);
    await tester.pump();
    await tester.pump();

    final visibleTransforms = find.byWidgetPredicate(
      (widget) =>
          widget is Transform &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'mobile_lyric_elastic_transform_',
          ),
    );
    expect(visibleTransforms, findsWidgets);
    for (final transform in tester.widgetList<Transform>(visibleTransforms)) {
      expect(transform.transform.storage[13], 0);
    }
  });

  testWidgets('a played line follows the synchronized reference exit', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(1);
    await tester.pumpAndSettle();

    hostKey.currentState!.setActive(2);
    await tester.pump();

    final playedLine = find.byKey(const ValueKey('mobile_lyric_1'));
    final scale = tester.widget<AnimatedScale>(
      find.descendant(of: playedLine, matching: find.byType(AnimatedScale)),
    );
    final style = tester.widget<AnimatedDefaultTextStyle>(
      find.descendant(
        of: playedLine,
        matching: find.byType(AnimatedDefaultTextStyle),
      ),
    );
    expect(scale.duration, mobileLyricsDefaultScrollTransitionDuration);
    expect(scale.curve, mobileLyricsFocusTransitionCurve);
    expect(style.duration, mobileLyricsDefaultScrollTransitionDuration);
    expect(style.curve, mobileLyricsFocusTransitionCurve);

    final slide = tester.widget<AnimatedSlide>(
      find.descendant(
        of: playedLine,
        matching: find.byKey(const ValueKey('mobile_lyric_karaoke_line_shift')),
      ),
    );
    expect(slide.offset, const Offset(0, -.16));
    expect(slide.duration, mobileLyricsKaraokeLineShiftDuration);
    expect(slide.curve, mobileLyricsFocusTransitionCurve);

    final scaleSafeContent = tester.widget<FractionallySizedBox>(
      find.descendant(
        of: playedLine,
        matching: find.byKey(const ValueKey('mobile_lyric_scale_safe_content')),
      ),
    );
    expect(scaleSafeContent.widthFactor, 1 / mobileLyricsActiveScale);
    expect(scaleSafeContent.heightFactor, 1 / mobileLyricsActiveScale);
  });

  testWidgets('default lyrics retain the reference line displacement', (
    tester,
  ) async {
    var active = 0;
    late StateSetter update;
    final lines = List.generate(
      4,
      (index) => LyricLine(
        timestamp: Duration(seconds: index),
        texts: ['默认歌词 ${index + 1}'],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return SizedBox(
                height: 240,
                child: MobileLyricsList(
                  lines: lines,
                  active: active,
                  karaokeLyricsEnabled: false,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    update(() => active = 1);
    await tester.pump();

    AnimatedSlide lineSlide(int index) => tester.widget<AnimatedSlide>(
      find.descendant(
        of: find.byKey(ValueKey('mobile_lyric_$index')),
        matching: find.byKey(const ValueKey('mobile_lyric_karaoke_line_shift')),
      ),
    );
    expect(lineSlide(0).offset, const Offset(0, -.16));
    expect(lineSlide(1).offset, Offset.zero);
    expect(lineSlide(2).offset, const Offset(0, .22));
    expect(lineSlide(0).duration, mobileLyricsKaraokeLineShiftDuration);
    expect(lineSlide(0).curve, mobileLyricsFocusTransitionCurve);
  });

  testWidgets('scaled lyric paint stays inside its retained sliver extent', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 220,
            child: _LyricsHost(key: hostKey),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Rect rowRect(int index) =>
        tester.getRect(find.byKey(ValueKey('mobile_lyric_$index')));
    Rect paintRect(int index) => tester.getRect(
      find.descendant(
        of: find.byKey(ValueKey('mobile_lyric_$index')),
        matching: find.byKey(const ValueKey('mobile_lyric_scaled_paint')),
      ),
    );
    void expectContained(int index) {
      final row = rowRect(index);
      final paint = paintRect(index);
      final motionAllowance =
          row.height *
          math.max(
            mobileLyricsKaraokeLineShift(-1).abs(),
            mobileLyricsKaraokeLineShift(1).abs(),
          );
      expect(paint.left, greaterThanOrEqualTo(row.left - .01));
      expect(paint.top, greaterThanOrEqualTo(row.top - motionAllowance - .01));
      expect(paint.right, lessThanOrEqualTo(row.right + .01));
      expect(
        paint.bottom,
        lessThanOrEqualTo(row.bottom + motionAllowance + .01),
      );
    }

    expectContained(0);
    hostKey.currentState!.setActive(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expectContained(0);
    expectContained(1);
  });

  testWidgets('dense line changes retarget one bounded list animation', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final index in [1, 2, 3]) {
      hostKey.currentState!.setActive(index);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 55));
    }

    await tester.pumpAndSettle();
    final active = find.byKey(const ValueKey('mobile_lyric_3'));
    expect(active, findsOneWidget);
    expect(tester.getCenter(active).dy, closeTo(88, 12));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.contains('active_hop'),
      ),
      findsNothing,
    );
  });

  testWidgets('active lyric automatically scrolls into the visible area', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mobile_lyric_0')), findsOneWidget);

    hostKey.currentState!.setActive(35);
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('mobile_lyric_35'));
    expect(active, findsOneWidget);
    expect(tester.getCenter(active).dy, closeTo(88, 12));

    hostKey.currentState!.setActive(49);
    await tester.pumpAndSettle();

    final finalLine = find.byKey(const ValueKey('mobile_lyric_49'));
    expect(finalLine, findsOneWidget);
    expect(tester.getCenter(finalLine).dy, closeTo(88, 12));
  });

  testWidgets('first async lyric batch starts with the active line centered', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 220,
            child: _LyricsHost(key: hostKey, initiallyEmpty: true),
          ),
        ),
      ),
    );

    hostKey.currentState!.loadLinesAt(25);
    await tester.pump();

    final active = find.byKey(const ValueKey('mobile_lyric_25'));
    expect(active, findsOneWidget);
    expect(tester.getCenter(active).dy, closeTo(88, 12));
  });

  testWidgets(
    'left-aligned next-song lyrics use the new position on their first frame',
    (tester) async {
      final hostKey = GlobalKey<_LyricsHostState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 220,
              child: _LyricsHost(
                key: hostKey,
                elasticScrollEnabled: true,
                textAlign: TextAlign.left,
              ),
            ),
          ),
        ),
      );
      hostKey.currentState!.setActive(35);
      await tester.pumpAndSettle();

      hostKey.currentState!.switchSongAt(4);
      await tester.pump();

      final active = find.byKey(const ValueKey('mobile_lyric_4'));
      expect(active, findsOneWidget);
      expect(tester.getCenter(active).dy, closeTo(88, 12));
    },
  );

  testWidgets('uses the configured lyric font size', (tester) async {
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['当前歌词']),
      LyricLine(timestamp: const Duration(seconds: 1), texts: const ['下一行']),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileLyricsList(lines: lines, active: 0, fontSize: 26),
        ),
      ),
    );

    final activeStyle = tester.widget<AnimatedDefaultTextStyle>(
      find
          .ancestor(
            of: find.text('当前歌词'),
            matching: find.byType(AnimatedDefaultTextStyle),
          )
          .first,
    );
    final inactiveStyle = tester.widget<AnimatedDefaultTextStyle>(
      find
          .ancestor(
            of: find.text('下一行'),
            matching: find.byType(AnimatedDefaultTextStyle),
          )
          .first,
    );
    expect(activeStyle.style.fontSize, 26);
    expect(inactiveStyle.style.fontSize, 26);
  });

  testWidgets('keeps the active lyric centered while font size changes', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(25);
    await tester.pumpAndSettle();

    hostKey.currentState!.setFontSize(32);
    await tester.pumpAndSettle();
    final enlarged = find.byKey(const ValueKey('mobile_lyric_25'));
    expect(tester.getCenter(enlarged).dy, closeTo(88, 12));

    hostKey.currentState!.setFontSize(12);
    await tester.pumpAndSettle();
    final reduced = find.byKey(const ValueKey('mobile_lyric_25'));
    expect(tester.getCenter(reduced).dy, closeTo(88, 12));
  });

  testWidgets('rapid font growth reanchors without a spring twitch', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(25);
    await tester.pumpAndSettle();

    for (final fontSize in <double>[22, 24, 26, 28, 30, 32]) {
      hostKey.currentState!.setFontSize(fontSize);
      await tester.pump();
      final active = find.byKey(const ValueKey('mobile_lyric_25'));
      expect(
        tester.getCenter(active).dy,
        closeTo(88, 12),
        reason: 'font size $fontSize must not retain the previous spring',
      );
    }
  });

  testWidgets('multiline lyrics retain the 40 percent visual anchor', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            width: 260,
            child: _LyricsHost(key: hostKey),
          ),
        ),
      ),
    );
    hostKey.currentState!.setLineText(
      24,
      '这是一句会自动换行的很长歌词，用于验证真实文本高度不会造成累计定位漂移',
    );
    hostKey.currentState!.setActive(24);
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('mobile_lyric_24'));
    expect(active, findsOneWidget);
    expect(tester.getCenter(active).dy, closeTo(120, 12));
  });

  testWidgets('applies the selected font family to lyrics', (tester) async {
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['自定义字体歌词']),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileLyricsList(
            lines: lines,
            active: 0,
            fontFamily: 'TestLyricsFont',
          ),
        ),
      ),
    );

    final style = tester.widget<AnimatedDefaultTextStyle>(
      find
          .ancestor(
            of: find.text('自定义字体歌词'),
            matching: find.byType(AnimatedDefaultTextStyle),
          )
          .first,
    );
    expect(style.style.fontFamily, 'TestLyricsFont');
  });

  testWidgets('manual lyric browsing resumes follow after three idle seconds', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(20);
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('mobile_lyrics_scroll_view')),
      const Offset(0, -140),
    );
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    hostKey.currentState!.setActive(40);
    await tester.pump();

    final active = find.byKey(const ValueKey('mobile_lyric_40'));
    expect(active, findsNothing);

    await tester.pump(const Duration(seconds: 2));
    expect(active, findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(active, findsOneWidget);
    expect(tester.getCenter(active).dy, closeTo(88, 12));
  });

  testWidgets('a new lyric pointer hold cancels the pending follow timer', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    final scrollView = find.byKey(const ValueKey('mobile_lyrics_scroll_view'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(20);
    await tester.pumpAndSettle();
    await tester.drag(scrollView, const Offset(0, -140));
    await tester.pump(const Duration(milliseconds: 300));
    hostKey.currentState!.setActive(40);
    await tester.pump(const Duration(milliseconds: 2500));

    final heldGesture = await tester.startGesture(tester.getCenter(scrollView));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('mobile_lyric_40')), findsNothing);

    await heldGesture.up();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('mobile_lyric_40')), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile_lyric_40')), findsOneWidget);
  });

  testWidgets('controller recenters the active lyric immediately', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(25);
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('mobile_lyrics_scroll_view')),
      const Offset(0, -160),
    );
    await tester.pump(const Duration(milliseconds: 300));

    hostKey.currentState!.recenter();
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('mobile_lyric_25'));
    expect(active, findsOneWidget);
    expect(tester.getCenter(active).dy, closeTo(88, 12));
  });

  testWidgets('entry recenter cancels an in-flight lyric scroll', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    hostKey.currentState!.setActive(3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 64));
    final active = find.byKey(const ValueKey('mobile_lyric_3'));
    expect(active, findsOneWidget);
    expect((tester.getCenter(active).dy - 88).abs(), greaterThan(1));

    hostKey.currentState!.recenter();
    await tester.pump();
    await tester.pump();
    expect(tester.getCenter(active).dy, closeTo(88, 12));

    final centeredY = tester.getCenter(active).dy;
    await tester.pump(const Duration(milliseconds: 240));
    expect(tester.getCenter(active).dy, closeTo(centeredY, .01));
  });

  testWidgets('an immediate lyric drag owns a pending entry recenter', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(20);
    await tester.pumpAndSettle();

    hostKey.currentState!.recenter();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('mobile_lyrics_scroll_view'))),
    );
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump(const Duration(milliseconds: 16));

    final active = find.byKey(const ValueKey('mobile_lyric_20'));
    expect(active, findsOneWidget);
    expect((tester.getCenter(active).dy - 88).abs(), greaterThan(30));
    await gesture.up();
  });

  testWidgets('pointer down freezes an in-flight automatic scroll', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scrollView = find.byKey(const ValueKey('mobile_lyrics_scroll_view'));
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: scrollView, matching: find.byType(Scrollable)),
    );

    hostKey.currentState!.setActive(35);
    await tester.pump(const Duration(milliseconds: 80));
    final gesture = await tester.startGesture(tester.getCenter(scrollView));
    await tester.pump();
    final frozenOffset = scrollable.position.pixels;
    await tester.pump(const Duration(milliseconds: 300));
    expect(scrollable.position.pixels, closeTo(frozenOffset, .01));
    await gesture.up();
  });

  testWidgets('same-song lyric refresh does not end an active drag', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(20);
    await tester.pumpAndSettle();
    final scrollView = find.byKey(const ValueKey('mobile_lyrics_scroll_view'));
    final gesture = await tester.startGesture(tester.getCenter(scrollView));
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump(const Duration(milliseconds: 16));

    hostKey.currentState!.replaceLinesAt(40);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('mobile_lyric_40')), findsNothing);
    await gesture.up();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('mobile_lyric_40')), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile_lyric_40')), findsOneWidget);
  });

  testWidgets('controller settles smoothly on a selected lyric timestamp', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(8);
    await tester.pumpAndSettle();

    hostKey.currentState!.settleOn(const Duration(seconds: 35));
    await tester.pump();
    final prepositioned = find.byKey(const ValueKey('mobile_lyric_35'));
    expect(prepositioned, findsOneWidget);
    expect(tester.getCenter(prepositioned).dy, greaterThan(88));

    hostKey.currentState!.setActive(35);
    await tester.pumpAndSettle();
    final selected = find.byKey(const ValueKey('mobile_lyric_35'));
    expect(tester.getCenter(selected).dy, closeTo(88, 12));
  });

  testWidgets('a lyric refresh preserves an in-flight seek timestamp', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(10);
    await tester.pumpAndSettle();
    hostKey.currentState!.settleOn(const Duration(seconds: 20));
    await tester.pumpAndSettle();

    hostKey.currentState!.replaceLinesAt(19);
    await tester.pumpAndSettle();
    final target = find.byKey(const ValueKey('mobile_lyric_20'));
    expect(target, findsOneWidget);
    expect(tester.getCenter(target).dy, closeTo(88, 12));

    hostKey.currentState!.setActive(20);
    await tester.pumpAndSettle();
    expect(tester.getCenter(target).dy, closeTo(88, 12));
  });

  testWidgets('a transient previous-line seek event keeps the target locked', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(10);
    await tester.pumpAndSettle();
    hostKey.currentState!.settleOn(const Duration(seconds: 20));
    await tester.pumpAndSettle();

    hostKey.currentState!.setActive(20);
    await tester.pump(const Duration(milliseconds: 200));
    hostKey.currentState!.setActive(19);
    await tester.pump(const Duration(milliseconds: 400));
    final target = find.byKey(const ValueKey('mobile_lyric_20'));
    expect(target, findsOneWidget);
    expect(tester.getCenter(target).dy, closeTo(88, 12));

    hostKey.currentState!.setActive(20);
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.getCenter(target).dy, closeTo(88, 12));
  });

  testWidgets('seeking inside the active lyric keeps the list stable', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(8);
    await tester.pumpAndSettle();

    hostKey.currentState!.settleOn(const Duration(seconds: 8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final active = find.byKey(const ValueKey('mobile_lyric_8'));
    expect(active, findsOneWidget);
    expect(tester.getCenter(active).dy, closeTo(88, 12));
  });

  testWidgets('far controller seek reaches a newly mounted elastic line', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 220,
            child: _LyricsHost(key: hostKey, elasticScrollEnabled: true),
          ),
        ),
      ),
    );
    hostKey.currentState!.setActive(2);
    await tester.pumpAndSettle();

    hostKey.currentState!.settleOn(const Duration(seconds: 40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final target = tester.widget<Transform>(
      find.byKey(const ValueKey('mobile_lyric_elastic_transform_40')),
    );
    expect(target.transform.storage[13].abs(), greaterThan(1));
  });

  testWidgets('manual browsing reports the lyric nearest the visual anchor', (
    tester,
  ) async {
    Duration? target;
    final lines = List.generate(
      30,
      (index) => LyricLine(
        timestamp: Duration(seconds: index * 5),
        texts: ['第 ${index + 1} 行'],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 220,
            child: MobileLyricsList(
              lines: lines,
              active: 0,
              onBrowseTargetChanged: (value) => target = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('mobile_lyrics_scroll_view')),
      const Offset(0, -150),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(target, isNotNull);
    expect(target, isNot(Duration.zero));

    await tester.pump(const Duration(seconds: 2));
    expect(target, isNotNull);

    await tester.pump(const Duration(seconds: 1));
    expect(target, isNull);
  });

  testWidgets('manual browsing highlights and selects the candidate row', (
    tester,
  ) async {
    const browseColor = Color(0xFF4A90E2);
    final controller = MobileLyricsListController();
    Duration? target;
    Duration? selected;
    var coverToggleCount = 0;
    final lines = List.generate(
      30,
      (index) => LyricLine(
        timestamp: Duration(seconds: index * 5),
        texts: ['第 ${index + 1} 行'],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => coverToggleCount++,
            child: SizedBox(
              height: 220,
              child: MobileLyricsList(
                controller: controller,
                lines: lines,
                active: 0,
                activeColor: browseColor,
                onBrowseTargetChanged: (value) => target = value,
                onBrowseTargetSelected: (value) {
                  selected = value;
                  controller.settleOn(value);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile_lyrics_progress_guide')),
      findsNothing,
    );
    await tester.drag(
      find.byKey(const ValueKey('mobile_lyrics_scroll_view')),
      const Offset(0, -150),
    );
    await tester.pump(const Duration(milliseconds: 180));

    expect(target, isNotNull);
    expect(
      find.byKey(const ValueKey('mobile_lyrics_progress_guide')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_lyrics_progress_time')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_lyrics_progress_line')),
      findsNothing,
    );
    expect(mobileLyricsBrowseGuideColor, const Color(0xB3FFFFFF));
    expect(formatMobileLyricsBrowseTime(const Duration(seconds: 65)), '1:05');
    expect(
      find.byKey(const ValueKey('mobile_lyrics_browse_highlight')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('mobile_lyrics_browse_highlight')),
          )
          .opacity,
      0,
    );
    expect(
      find.byKey(const ValueKey('mobile_lyrics_browse_tap_target')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('mobile_lyrics_browse_reset')),
      findsNothing,
    );
    expect(
      tester
          .widget<TweenAnimationBuilder<double>>(
            find.byKey(const ValueKey('mobile_lyrics_browse_highlight_scale')),
          )
          .tween
          .end,
      .86,
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('mobile_lyrics_browse_highlight')),
          )
          .opacity,
      1,
    );
    await tester.pump(mobileLyricsBrowseMaskRevealDuration);
    expect(mobileLyricsBrowseMaskColor, const Color(0x4DFFFFFF));
    expect(
      find.byKey(const ValueKey('mobile_lyrics_browse_tap_target')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TweenAnimationBuilder<double>>(
            find.byKey(const ValueKey('mobile_lyrics_browse_highlight_scale')),
          )
          .tween
          .end,
      1,
    );
    final selectedTarget = target;
    final targetIndex = selectedTarget!.inSeconds ~/ 5;
    final targetRow = tester.getRect(
      find.byKey(ValueKey('mobile_lyric_$targetIndex')),
    );
    final tapTarget = tester.getRect(
      find.byKey(const ValueKey('mobile_lyrics_browse_tap_target')),
    );
    final lyricsArea = tester.getRect(
      find.byKey(const ValueKey('mobile_lyrics_viewport')),
    );
    final browseStyle = tester
        .widget<AnimatedDefaultTextStyle>(
          find.descendant(
            of: find.byKey(ValueKey('mobile_lyric_$targetIndex')),
            matching: find.byType(AnimatedDefaultTextStyle),
          ),
        )
        .style;
    final browseSlide = tester.widget<AnimatedSlide>(
      find.descendant(
        of: find.byKey(ValueKey('mobile_lyric_$targetIndex')),
        matching: find.byKey(const ValueKey('mobile_lyric_karaoke_line_shift')),
      ),
    );
    expect(browseStyle.color, browseColor);
    expect(browseSlide.offset, Offset.zero);
    expect(tapTarget.height, greaterThan(targetRow.height));
    expect(tapTarget.center.dy, closeTo(targetRow.center.dy, .01));
    await tester.tapAt(Offset(tapTarget.left + 4, tapTarget.center.dy));
    await tester.pump();
    expect(selected, selectedTarget);
    expect(coverToggleCount, 0);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.contains('active_hop'),
      ),
      findsNothing,
    );

    selected = null;
    await tester.drag(
      find.byKey(const ValueKey('mobile_lyrics_scroll_view')),
      const Offset(0, -60),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(mobileLyricsBrowseMaskRevealDuration);
    final rightEdgeTarget = tester.getRect(
      find.byKey(const ValueKey('mobile_lyrics_browse_tap_target')),
    );
    final expectedRightTarget = target;
    await tester.tapAt(
      Offset(rightEdgeTarget.right - 4, rightEdgeTarget.center.dy),
    );
    await tester.pump();
    expect(selected, expectedRightTarget);
    expect(coverToggleCount, 0);

    selected = null;
    await tester.tapAt(Offset(tapTarget.center.dx, lyricsArea.top + 2));
    await tester.pump();
    expect(selected, isNull);
    expect(coverToggleCount, 1);
  });

  testWidgets('edge fade is opt-in', (tester) async {
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['第一行']),
      LyricLine(timestamp: const Duration(seconds: 1), texts: const ['第二行']),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MobileLyricsList(lines: lines, active: 0)),
      ),
    );
    expect(find.byKey(const ValueKey('mobile_lyrics_edge_fade')), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileLyricsList(
            lines: lines,
            active: 0,
            edgeFadeEnabled: true,
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('mobile_lyrics_edge_fade')),
      findsOneWidget,
    );
    final fade = tester.widget<ShaderMask>(
      find.byKey(const ValueKey('mobile_lyrics_edge_fade')),
    );
    expect(fade.blendMode, BlendMode.dstIn);
    expect(mobileLyricsTopEdgeAlpha, 0);
    expect(mobileLyricsTopFadeSoftAlpha, greaterThan(mobileLyricsTopEdgeAlpha));
    expect(mobileLyricsTopFadeMidAlpha, greaterThan(mobileLyricsTopEdgeAlpha));
    expect(
      mobileLyricsTopFadeNearAlpha,
      greaterThan(mobileLyricsTopFadeMidAlpha),
    );
    expect(mobileLyricsBottomFadeMidAlpha, greaterThan(0));
    final stops = mobileLyricsEdgeFadeStops(800);
    expect(stops.length, 11);
    expect(stops[4], closeTo(.25, .0001));
    expect(stops[5], closeTo(.72, .0001));
    for (var index = 1; index < stops.length; index++) {
      expect(stops[index], greaterThan(stops[index - 1]));
    }
  });

  testWidgets('karaoke lyric uses one segmented custom paint surface', (
    tester,
  ) async {
    final line = LyricLine(
      timestamp: Duration.zero,
      texts: const ['Hello世界'],
      tokens: [
        [
          LyricToken(
            text: 'Hello',
            start: Duration.zero,
            end: const Duration(seconds: 1),
          ),
          LyricToken(
            text: '世界',
            start: const Duration(seconds: 1),
            end: const Duration(seconds: 2),
          ),
        ],
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: MobileLyricsList(
            lines: [line],
            active: 0,
            position: const Duration(milliseconds: 500),
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_0')),
        matching: find.byKey(
          const ValueKey('mobile_karaoke_single_pass_paint'),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('inactive karaoke rows stay prewarmed across a line jump', (
    tester,
  ) async {
    final lines = List.generate(
      2,
      (index) => LyricLine(
        timestamp: Duration(seconds: index * 2),
        texts: ['Line $index', '翻译 $index'],
        tokens: [
          [
            LyricToken(
              text: 'Line $index',
              start: Duration(seconds: index * 2),
              end: Duration(seconds: index * 2 + 1),
            ),
          ],
          [
            LyricToken(
              text: '翻译 $index',
              start: Duration(seconds: index * 2),
              end: Duration(seconds: index * 2 + 1),
            ),
          ],
        ],
      ),
    );

    Widget build(int active) => MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SizedBox(
          height: 360,
          child: MobileLyricsList(
            lines: lines,
            active: active,
            position: Duration(seconds: active * 2),
          ),
        ),
      ),
    );

    await tester.pumpWidget(build(0));
    await tester.pump();
    final inactivePaint = find.descendant(
      of: find.byKey(const ValueKey('mobile_lyric_1')),
      matching: find.byKey(const ValueKey('mobile_karaoke_single_pass_paint')),
    );
    expect(inactivePaint, findsOneWidget);
    final warmedElement = tester.element(inactivePaint);

    await tester.pumpWidget(build(1));
    await tester.pump();
    expect(tester.element(inactivePaint), same(warmedElement));
  });

  testWidgets('normal line advance retains the old pose while it exits', (
    tester,
  ) async {
    final position = ValueNotifier(const Duration(milliseconds: 800));
    final lines = List.generate(
      2,
      (index) => LyricLine(
        timestamp: Duration(seconds: index * 2),
        texts: ['唱词$index'],
        tokens: [
          [
            LyricToken(
              text: '唱词$index',
              start: Duration(seconds: index * 2),
              end: Duration(seconds: index * 2 + 1),
            ),
          ],
        ],
      ),
    );
    Widget build(int active) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 360,
          child: MobileLyricsList(
            lines: lines,
            active: active,
            position: position.value,
            positionListenable: position,
            isPlaying: true,
          ),
        ),
      ),
    );

    CustomPaint oldPaint() => tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_0')),
        matching: find.byKey(
          const ValueKey('mobile_karaoke_single_pass_paint'),
        ),
      ),
    );

    await tester.pumpWidget(build(0));
    await tester.pump();
    final before = (oldPaint().painter as dynamic).positionListenable.value;
    expect(before, greaterThan(const Duration(milliseconds: 500)));

    await tester.pumpWidget(build(1));
    expect((oldPaint().painter as dynamic).isExiting, isTrue);
    expect((oldPaint().painter as dynamic).positionListenable.value, before);
    await tester.pump(const Duration(milliseconds: 120));
    final retention = (oldPaint().painter as dynamic).exitAnimation.value;
    expect(retention, inExclusiveRange(0.0, 1.0));
    await tester.pump(const Duration(milliseconds: 140));
    expect(
      (oldPaint().painter as dynamic).positionListenable.value,
      const Duration(milliseconds: -120),
    );
    position.dispose();
  });

  testWidgets('animation ticks reuse layout; width invalidates it', (
    tester,
  ) async {
    final position = ValueNotifier(const Duration(milliseconds: 100));
    final line = LyricLine(
      timestamp: Duration.zero,
      texts: const ['连续运动文字'],
      tokens: [
        [
          LyricToken(
            text: '连续运动文字',
            start: Duration.zero,
            end: const Duration(seconds: 2),
          ),
        ],
      ],
    );
    Widget build(double width) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: 300,
          child: MobileLyricsList(
            lines: [line],
            active: 0,
            position: position.value,
            positionListenable: position,
            isPlaying: true,
          ),
        ),
      ),
    );

    await tester.pumpWidget(build(320));
    await tester.pump();
    final initialBuilds = debugKaraokeLayoutBuildCount;
    expect(initialBuilds, greaterThan(0));
    for (var i = 0; i < 5; i++) {
      position.value = Duration(milliseconds: 150 + i * 60);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(debugKaraokeLayoutBuildCount, initialBuilds);
    await tester.pumpWidget(build(220));
    await tester.pump();
    expect(debugKaraokeLayoutBuildCount, greaterThan(initialBuilds));
    position.dispose();
  });

  testWidgets('an explicit seek never uses the normal-line exit', (
    tester,
  ) async {
    final position = ValueNotifier(const Duration(milliseconds: 800));
    final intent = ValueNotifier(0);
    final lines = List.generate(
      2,
      (index) => LyricLine(
        timestamp: Duration(seconds: index * 2),
        texts: ['文字$index'],
        tokens: [
          [
            LyricToken(
              text: '文字$index',
              start: Duration(seconds: index * 2),
              end: Duration(seconds: index * 2 + 1),
            ),
          ],
        ],
      ),
    );
    Widget build(int active) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 360,
          child: MobileLyricsList(
            lines: lines,
            active: active,
            position: position.value,
            positionListenable: position,
            seekIntentListenable: intent,
            isPlaying: true,
          ),
        ),
      ),
    );

    await tester.pumpWidget(build(0));
    await tester.pump();
    intent.value++;
    position.value = const Duration(seconds: 2);
    await tester.pumpWidget(build(1));
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_0')),
        matching: find.byKey(
          const ValueKey('mobile_karaoke_single_pass_paint'),
        ),
      ),
    );
    expect((paint.painter as dynamic).isExiting, isFalse);
    expect(
      (paint.painter as dynamic).positionListenable.value,
      const Duration(milliseconds: -120),
    );
    intent.dispose();
    position.dispose();
  });

  testWidgets('highlight reaches full brightness before the token completes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final bytes = await File('assets/fonts/MiSansVF.ttf').readAsBytes();
      await (FontLoader(
        'KaraokePixelTest',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    });
    final captureKey = GlobalKey();
    final line = LyricLine(
      timestamp: Duration.zero,
      texts: const ['MMMM'],
      tokens: [
        [
          LyricToken(
            text: 'MMMM',
            start: Duration.zero,
            end: const Duration(seconds: 2),
          ),
        ],
      ],
    );
    Future<int> peakAt(int milliseconds) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 180,
                child: RepaintBoundary(
                  key: captureKey,
                  child: ColoredBox(
                    color: Colors.black,
                    child: MobileLyricsList(
                      lines: [line],
                      active: 0,
                      position: Duration(milliseconds: milliseconds),
                      fontSize: 32,
                      fontFamily: 'KaraokePixelTest',
                      activeColor: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return (await tester.runAsync(() async {
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        image.dispose();
        var peak = 0;
        for (var i = 0; i < data.lengthInBytes; i += 4) {
          if ((i ~/ 4) % 320 >= 240) continue;
          if (data.getUint8(i) > peak) peak = data.getUint8(i);
        }
        return peak;
      }))!;
    }

    final initial = await peakAt(0);
    final partial = await peakAt(1500);
    final completed = await peakAt(2000);
    expect(partial, greaterThan(initial + 50));
    expect(
      (partial - completed).abs(),
      lessThan(12),
      reason:
          'completed letters must already be bright inside a still-playing token',
    );
  });

  testWidgets('single-pass karaoke remains visibly painted at every phase', (
    tester,
  ) async {
    const background = Color(0xFF123456);
    final captureKey = GlobalKey();
    final line = LyricLine(
      timestamp: Duration.zero,
      texts: const ['Visible karaoke'],
      tokens: [
        [
          LyricToken(
            text: 'Visible karaoke',
            start: Duration.zero,
            end: const Duration(seconds: 2),
          ),
        ],
      ],
    );

    Future<int> changedPixels() async {
      final boundary =
          captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      var changed = 0;
      for (var offset = 0; offset < bytes!.lengthInBytes; offset += 4) {
        if (bytes.getUint8(offset) != 0x12 ||
            bytes.getUint8(offset + 1) != 0x34 ||
            bytes.getUint8(offset + 2) != 0x56) {
          changed++;
        }
      }
      return changed;
    }

    Future<void> showAt(
      Duration position, {
      LyricLine? shownLine,
      double fontSize = 20,
      TextDirection textDirection = TextDirection.ltr,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 140,
                child: RepaintBoundary(
                  key: captureKey,
                  child: ColoredBox(
                    color: background,
                    child: Directionality(
                      textDirection: textDirection,
                      child: MobileLyricsList(
                        lines: [shownLine ?? line],
                        active: 0,
                        position: position,
                        fontSize: fontSize,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    for (final position in [
      Duration.zero,
      const Duration(seconds: 1),
      const Duration(seconds: 2),
    ]) {
      await showAt(position);
      final visiblePixelCount = await tester.runAsync(changedPixels);
      expect(visiblePixelCount, greaterThan(100), reason: '$position');
    }

    await showAt(
      const Duration(seconds: 1),
      shownLine: LyricLine(
        timestamp: Duration.zero,
        texts: const ['Fallback visible'],
        tokens: [
          [
            LyricToken(
              text: 'metadata that cannot map into the displayed lyric',
              start: Duration.zero,
              end: const Duration(seconds: 2),
            ),
          ],
        ],
      ),
    );
    final fallbackPixelCount = await tester.runAsync(changedPixels);
    expect(fallbackPixelCount, greaterThan(100));

    await showAt(
      const Duration(seconds: 1),
      fontSize: 42,
      textDirection: TextDirection.rtl,
      shownLine: LyricLine(
        timestamp: Duration.zero,
        texts: const ['مرحبا بالعالم مرحبا بالعالم'],
        tokens: [
          [
            LyricToken(
              text: 'مرحبا بالعالم مرحبا بالعالم',
              start: Duration.zero,
              end: const Duration(seconds: 2),
            ),
          ],
        ],
      ),
    );
    final largeRtlPixelCount = await tester.runAsync(changedPixels);
    expect(largeRtlPixelCount, greaterThan(200));
  });

  testWidgets('active lyric highlight keeps the whole karaoke line white', (
    tester,
  ) async {
    final line = LyricLine(
      timestamp: Duration.zero,
      texts: const ['高亮歌词'],
      tokens: [
        [
          LyricToken(
            text: '高亮',
            start: Duration.zero,
            end: const Duration(seconds: 1),
          ),
          LyricToken(
            text: '歌词',
            start: const Duration(seconds: 1),
            end: const Duration(seconds: 2),
          ),
        ],
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileLyricsList(
            lines: [line],
            active: 0,
            position: const Duration(milliseconds: 500),
            highlightActiveLine: true,
            karaokeLyricsEnabled: false,
          ),
        ),
      ),
    );

    final highlightedText = tester.widget<Text>(
      find
          .descendant(
            of: find.byKey(const ValueKey('mobile_lyric_0')),
            matching: find.byType(Text),
          )
          .last,
    );
    expect(highlightedText.data, '高亮歌词');
    expect(highlightedText.textSpan, isNull);
    final animatedStyle = tester.widget<AnimatedDefaultTextStyle>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_0')),
        matching: find.byType(AnimatedDefaultTextStyle),
      ),
    );
    expect(animatedStyle.style.color, Colors.white);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_0')),
        matching: find.byType(ValueListenableBuilder<Duration>),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_0')),
        matching: find.byType(RichText),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'all-lyrics karaoke remains active when whole-line highlight is enabled',
    (tester) async {
      final position = ValueNotifier(const Duration(milliseconds: 900));
      addTearDown(position.dispose);
      final lines = [
        LyricLine(timestamp: Duration.zero, texts: const ['普通歌词逐字显示']),
        LyricLine(timestamp: const Duration(seconds: 4), texts: const ['下一行']),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: MobileLyricsList(
              lines: lines,
              active: 0,
              positionListenable: position,
              karaokeLyricsMode: KaraokeLyricsMode.all,
              highlightActiveLine: true,
            ),
          ),
        ),
      );

      final karaokePaint = find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_0')),
        matching: find.byKey(
          const ValueKey('mobile_karaoke_single_pass_paint'),
        ),
      );
      expect(karaokePaint, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('mobile_lyric_0')),
          matching: find.byType(ValueListenableBuilder<Duration>),
        ),
        findsNothing,
      );
      final before = tester.widget<CustomPaint>(karaokePaint).painter;

      position.value = const Duration(milliseconds: 2800);
      await tester.pump();

      final after = tester.widget<CustomPaint>(karaokePaint).painter;
      expect(after, same(before));
    },
  );

  testWidgets('karaoke progress can update without rebuilding the lyric list', (
    tester,
  ) async {
    final position = ValueNotifier(const Duration(milliseconds: 500));
    addTearDown(position.dispose);
    final line = LyricLine(
      timestamp: Duration.zero,
      texts: const ['Hello世界'],
      tokens: [
        [
          LyricToken(
            text: 'Hello',
            start: Duration.zero,
            end: const Duration(seconds: 1),
          ),
          LyricToken(
            text: '世界',
            start: const Duration(seconds: 1),
            end: const Duration(seconds: 2),
          ),
        ],
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: MobileLyricsList(
            lines: [line],
            active: 0,
            positionListenable: position,
          ),
        ),
      ),
    );

    final karaokePaint = find.descendant(
      of: find.byKey(const ValueKey('mobile_lyric_0')),
      matching: find.byKey(const ValueKey('mobile_karaoke_single_pass_paint')),
    );
    final painterBefore = tester.widget<CustomPaint>(karaokePaint).painter;

    position.value = const Duration(milliseconds: 1500);
    await tester.pump();

    expect(
      tester.widget<CustomPaint>(karaokePaint).painter,
      same(painterBefore),
    );
  });

  testWidgets('light lyrics use stronger unplayed text and optional glow', (
    tester,
  ) async {
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['正在播放']),
      LyricLine(timestamp: const Duration(seconds: 1), texts: const ['尚未播放']),
      LyricLine(timestamp: const Duration(seconds: 2), texts: const ['稍后播放']),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Scaffold(
          body: MobileLyricsList(
            lines: lines,
            active: 0,
            glowEnabled: true,
            glowRadius: 14,
          ),
        ),
      ),
    );

    final inactiveStyle = tester
        .widget<AnimatedDefaultTextStyle>(
          find.descendant(
            of: find.byKey(const ValueKey('mobile_lyric_1')),
            matching: find.byType(AnimatedDefaultTextStyle),
          ),
        )
        .style;
    expect(inactiveStyle.color, const Color(0xFF757575).withValues(alpha: .68));
    final fartherInactiveStyle = tester
        .widget<AnimatedDefaultTextStyle>(
          find.descendant(
            of: find.byKey(const ValueKey('mobile_lyric_2')),
            matching: find.byType(AnimatedDefaultTextStyle),
          ),
        )
        .style;
    expect(fartherInactiveStyle.color, inactiveStyle.color);
    expect(inactiveStyle.shadows, isNull);
    final inactiveGlow =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byKey(const ValueKey('mobile_lyric_1')),
                    matching: find.byKey(
                      const ValueKey('mobile_lyric_glow_layer'),
                    ),
                  ),
                )
                .painter!
            as MobileLyricGlowPainter;
    expect(inactiveGlow.color, inactiveStyle.color!.withValues(alpha: .30));
    expect(inactiveGlow.blurRadius, 14);
    final inactiveGlowOpacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_1')),
        matching: find.byKey(const ValueKey('mobile_lyric_glow_opacity')),
      ),
    );
    expect(inactiveGlowOpacity.opacity, inactiveStyle.color!.a);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Scaffold(body: MobileLyricsList(lines: lines, active: 0)),
      ),
    );
    final defaultStyle = tester
        .widget<AnimatedDefaultTextStyle>(
          find.descendant(
            of: find.byKey(const ValueKey('mobile_lyric_1')),
            matching: find.byType(AnimatedDefaultTextStyle),
          ),
        )
        .style;
    expect(defaultStyle.shadows, isNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_1')),
        matching: find.byKey(const ValueKey('mobile_lyric_glow_layer')),
      ),
      findsNothing,
    );
  });

  testWidgets('light playback backgrounds use dark-mode lyric treatment', (
    tester,
  ) async {
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['正在播放']),
      LyricLine(timestamp: const Duration(seconds: 1), texts: const ['尚未播放']),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Scaffold(
          body: MobileLyricsList(
            lines: lines,
            active: 0,
            brightForeground: true,
            glowEnabled: true,
          ),
        ),
      ),
    );

    final style = tester
        .widget<AnimatedDefaultTextStyle>(
          find.descendant(
            of: find.byKey(const ValueKey('mobile_lyric_1')),
            matching: find.byType(AnimatedDefaultTextStyle),
          ),
        )
        .style;
    expect(style.color, Colors.white.withValues(alpha: .36));
    expect(style.shadows, isNull);
    final glow =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byKey(const ValueKey('mobile_lyric_1')),
                    matching: find.byKey(
                      const ValueKey('mobile_lyric_glow_layer'),
                    ),
                  ),
                )
                .painter!
            as MobileLyricGlowPainter;
    expect(glow.color, style.color!.withValues(alpha: .30));
    final glowOpacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_1')),
        matching: find.byKey(const ValueKey('mobile_lyric_glow_opacity')),
      ),
    );
    expect(glowOpacity.opacity, style.color!.a);
  });

  testWidgets('lyric glow follows the rendered line color and opacity', (
    tester,
  ) async {
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['正在播放']),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: MobileLyricsList(lines: lines, active: 0, glowEnabled: true),
        ),
      ),
    );

    final style = tester
        .widget<AnimatedDefaultTextStyle>(
          find.descendant(
            of: find.byKey(const ValueKey('mobile_lyric_0')),
            matching: find.byType(AnimatedDefaultTextStyle),
          ),
        )
        .style;
    expect(style.shadows, isNull);
    final glow =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byKey(const ValueKey('mobile_lyric_0')),
                    matching: find.byKey(
                      const ValueKey('mobile_lyric_glow_layer'),
                    ),
                  ),
                )
                .painter!
            as MobileLyricGlowPainter;
    expect(glow.color, style.color!.withValues(alpha: .30));
    final glowOpacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_0')),
        matching: find.byKey(const ValueKey('mobile_lyric_glow_opacity')),
      ),
    );
    expect(glowOpacity.opacity, style.color!.a);
    final glowPaint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_0')),
        matching: find.byKey(const ValueKey('mobile_lyric_glow_layer')),
      ),
    );
    expect(glowPaint.isComplex, isTrue);
    expect(glowPaint.willChange, isFalse);
    expect(
      find.ancestor(
        of: find.descendant(
          of: find.byKey(const ValueKey('mobile_lyric_0')),
          matching: find.byKey(const ValueKey('mobile_lyric_glow_layer')),
        ),
        matching: find.byType(RepaintBoundary),
      ),
      findsWidgets,
    );
  });

  testWidgets('regular centered lyrics are the default presentation', (
    tester,
  ) async {
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['当前歌词']),
      LyricLine(timestamp: const Duration(seconds: 1), texts: const ['下一行']),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MobileLyricsList(lines: lines, active: 0)),
      ),
    );

    final list = tester.widget<MobileLyricsList>(find.byType(MobileLyricsList));
    final textStyle = tester.widget<AnimatedDefaultTextStyle>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_0')),
        matching: find.byType(AnimatedDefaultTextStyle),
      ),
    );
    expect(list.elasticScrollEnabled, isFalse);
    expect(list.lineBlurEnabled, isFalse);
    expect(textStyle.textAlign, TextAlign.center);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_1')),
        matching: find.byType(ImageFiltered),
      ),
      findsNothing,
    );
  });

  testWidgets('alignment and distance blur are applied per lyric line', (
    tester,
  ) async {
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['当前歌词']),
      LyricLine(timestamp: const Duration(seconds: 1), texts: const ['下一行']),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileLyricsList(
            lines: lines,
            active: 0,
            textAlign: TextAlign.left,
            lineBlurEnabled: true,
          ),
        ),
      ),
    );

    final textStyle = tester.widget<AnimatedDefaultTextStyle>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_1')),
        matching: find.byType(AnimatedDefaultTextStyle),
      ),
    );
    expect(textStyle.textAlign, TextAlign.left);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_0')),
        matching: find.byType(ImageFiltered),
      ),
      findsOneWidget,
    );
    final currentFilter = tester.widget<ImageFiltered>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_0')),
        matching: find.byType(ImageFiltered),
      ),
    );
    expect(currentFilter.enabled, isFalse);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_1')),
        matching: find.byType(ImageFiltered),
      ),
      findsOneWidget,
    );
    final safeArea = tester.widget<Padding>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_1')),
        matching: find.byKey(const ValueKey('mobile_lyric_filter_safe_area')),
      ),
    );
    expect(safeArea.padding, const EdgeInsets.symmetric(vertical: 5));
  });

  testWidgets('blur sharpness crossfades with the active lyric', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 220,
            child: _LyricsHost(key: hostKey, lineBlurEnabled: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    hostKey.currentState!.setActive(1);
    await tester.pump();
    final incomingAtStart = tester.widget<ImageFiltered>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_1')),
        matching: find.byType(ImageFiltered),
      ),
    );
    expect(incomingAtStart.enabled, isTrue);

    await tester.pump(const Duration(milliseconds: 100));
    final outgoingDuringTransition = tester.widget<ImageFiltered>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_0')),
        matching: find.byType(ImageFiltered),
      ),
    );
    expect(outgoingDuringTransition.enabled, isTrue);

    await tester.pump(mobileLyricsFocusTransitionDuration);
    final incomingSettled = tester.widget<ImageFiltered>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_1')),
        matching: find.byType(ImageFiltered),
      ),
    );
    expect(incomingSettled.enabled, isFalse);
  });

  testWidgets('configured lyric weight and interlude dots are rendered', (
    tester,
  ) async {
    final position = ValueNotifier(const Duration(seconds: 2));
    addTearDown(position.dispose);
    final lines = [
      LyricLine(
        timestamp: Duration.zero,
        texts: const [],
        isInterlude: true,
        interludeDuration: const Duration(seconds: 8),
      ),
      LyricLine(timestamp: const Duration(seconds: 8), texts: const ['歌词']),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileLyricsList(
            lines: lines,
            active: 0,
            fontWeight: FontWeight.w800,
            positionListenable: position,
            isPlaying: false,
          ),
        ),
      ),
    );

    final style = tester.widget<AnimatedDefaultTextStyle>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_0')),
        matching: find.byType(AnimatedDefaultTextStyle),
      ),
    );
    expect(style.style.fontWeight, FontWeight.w800);
    expect(find.byType(InterludeAnimationWidget), findsOneWidget);
  });

  testWidgets('interlude waiting dots fade and slide in and out', (
    tester,
  ) async {
    var active = 1;
    late StateSetter update;
    final lines = [
      LyricLine(
        timestamp: Duration.zero,
        texts: const [],
        isInterlude: true,
        interludeDuration: const Duration(seconds: 8),
      ),
      LyricLine(timestamp: const Duration(seconds: 8), texts: const ['歌词']),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MobileLyricsList(lines: lines, active: active);
            },
          ),
        ),
      ),
    );

    FadeTransition visibility() => tester.widget<FadeTransition>(
      find.byKey(const ValueKey('interlude_visibility')),
    );

    expect(visibility().opacity.value, 0);
    update(() => active = 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(visibility().opacity.value, inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 260));
    expect(visibility().opacity.value, closeTo(1, .01));

    update(() => active = 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(visibility().opacity.value, inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 220));
    expect(visibility().opacity.value, closeTo(0, .01));
  });

  testWidgets('speaker prefixes follow the selected global alignment', (
    tester,
  ) async {
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['世界上的另一个我']),
      LyricLine(timestamp: const Duration(seconds: 1), texts: const ['肆：第一句']),
      LyricLine(timestamp: const Duration(seconds: 2), texts: const ['肆的下一句']),
      LyricLine(timestamp: const Duration(seconds: 3), texts: const ['郭：第二句']),
      LyricLine(timestamp: const Duration(seconds: 4), texts: const ['郭的下一句']),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: MobileLyricsList(
              lines: lines,
              active: 2,
              textAlign: TextAlign.right,
            ),
          ),
        ),
      ),
    );

    TextAlign alignmentAt(int index) => tester
        .widget<AnimatedDefaultTextStyle>(
          find.descendant(
            of: find.byKey(ValueKey('mobile_lyric_$index')),
            matching: find.byType(AnimatedDefaultTextStyle),
          ),
        )
        .textAlign!;

    expect(alignmentAt(0), TextAlign.right);
    expect(alignmentAt(1), TextAlign.right);
    expect(alignmentAt(2), TextAlign.right);
    expect(alignmentAt(3), TextAlign.right);
    expect(alignmentAt(4), TextAlign.right);
  });

  testWidgets('side-aligned lyrics use the compact safe edge inset', (
    tester,
  ) async {
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['靠近屏幕边缘']),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileLyricsList(
            lines: lines,
            active: 0,
            textAlign: TextAlign.left,
          ),
        ),
      ),
    );

    expect(mobileLyricsHorizontalInset(TextAlign.left), 4);
    expect(mobileLyricsHorizontalInset(TextAlign.right), 4);
    expect(mobileLyricsHorizontalInset(TextAlign.center), 24);
  });

  testWidgets('elastic mode produces a visible per-line spring displacement', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: _LyricsHost(key: hostKey, elasticScrollEnabled: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    hostKey.currentState!.setActive(5);
    await tester.pump();
    final firstFrameCenter = tester.getCenter(
      find.byKey(const ValueKey('mobile_lyric_5')),
    );
    expect((firstFrameCenter.dy - 120).abs(), greaterThan(8));
    final transform = tester.widget<Transform>(
      find.byKey(const ValueKey('mobile_lyric_elastic_transform_5')),
    );
    expect(transform.transform.storage[13].abs(), greaterThan(1));

    await tester.pumpAndSettle();
    final settled = tester.widget<Transform>(
      find.byKey(const ValueKey('mobile_lyric_elastic_transform_5')),
    );
    expect(settled.transform.storage[13], closeTo(0, .5));
  });
}

class _LyricsHost extends StatefulWidget {
  const _LyricsHost({
    super.key,
    this.initiallyEmpty = false,
    this.elasticScrollEnabled = false,
    this.lineBlurEnabled = false,
    this.textAlign = TextAlign.center,
  });

  final bool initiallyEmpty;
  final bool elasticScrollEnabled;
  final bool lineBlurEnabled;
  final TextAlign textAlign;

  @override
  State<_LyricsHost> createState() => _LyricsHostState();
}

class _LyricsHostState extends State<_LyricsHost> {
  int active = 0;
  String contentIdentity = 'song-a';
  double fontSize = 20;
  final controller = MobileLyricsListController();
  late List<LyricLine> lines;

  List<LyricLine> _makeLines() => List.generate(
    50,
    (index) => LyricLine(
      timestamp: Duration(seconds: index),
      texts: ['第 ${index + 1} 行'],
    ),
  );

  @override
  void initState() {
    super.initState();
    lines = widget.initiallyEmpty ? [] : _makeLines();
  }

  void setActive(int value) => setState(() => active = value);

  void setFontSize(double value) => setState(() => fontSize = value);

  void setLineText(int index, String text) => setState(() {
    lines = List<LyricLine>.of(lines);
    lines[index] = LyricLine(timestamp: lines[index].timestamp, texts: [text]);
  });

  void loadLinesAt(int value) => setState(() {
    active = value;
    lines = _makeLines();
  });

  void replaceLinesAt(int value) => setState(() {
    active = value;
    lines = _makeLines();
  });

  void beginNextSong() => setState(() {
    contentIdentity = 'song-b';
    active = -1;
    lines = [];
  });

  void loadNextSongLyrics() => setState(() {
    active = 0;
    lines = _makeLines();
  });

  void switchSongAt(int value) => setState(() {
    contentIdentity = 'song-b';
    active = value;
    lines = List.generate(
      50,
      (index) => LyricLine(
        timestamp: Duration(seconds: index),
        texts: ['下一曲第 ${index + 1} 行'],
      ),
    );
  });

  void recenter() => controller.recenter();

  void settleOn(Duration target) => controller.settleOn(target);

  @override
  Widget build(BuildContext context) => MobileLyricsList(
    controller: controller,
    lines: lines,
    active: active,
    contentIdentity: contentIdentity,
    fontSize: fontSize,
    elasticScrollEnabled: widget.elasticScrollEnabled,
    lineBlurEnabled: widget.lineBlurEnabled,
    textAlign: widget.textAlign,
  );
}
