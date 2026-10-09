import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';
import 'package:myune_music/widgets/karaoke_motion.dart';

void main() {
  testWidgets(
    'slow real syllable retains feather and coverage across cold/hot rendering',
    (tester) async {
      await _fonts(tester);
      final line = LyricLine(
        timestamp: Duration.zero,
        texts: ['I'],
        tokens: [
          [
            LyricToken(
              text: 'I',
              start: const Duration(seconds: 1),
              end: const Duration(seconds: 9),
            ),
          ],
        ],
      );
      await tester.pumpWidget(_host('I', sourceLine: line));
      final dynamic painter = _painter(tester), cache = painter.cache;
      final dynamic fragment = cache.tokens.single.fragments.single;
      final double feather = fragment.feather;
      expect(feather, lessThan(cache.feather));
      final dynamic colors = painter.colors.withColors(
        Colors.white,
        Colors.white.withValues(alpha: .36),
      );
      late Uint8List cold;
      await tester.runAsync(() async {
        cold = await _render(
          cache,
          (canvas) => cache.paint(canvas, 5000000, 1.0, colors),
        );
      });
      await _warm(tester, cache);
      expect(fragment.feather, feather);
      final layouts = debugKaraokeTextLayoutCount;
      await tester.runAsync(() async {
        final warm = await _render(
          cache,
          (canvas) => cache.paint(canvas, 5000000, 1.0, colors),
        );
        var difference = 0, inkPixels = 0;
        for (var i = 0; i < cold.length; i += 4) {
          if (cold[i] > 10 || warm[i] > 10) {
            difference += (cold[i] - warm[i]).abs();
            inkPixels++;
          }
        }
        expect(inkPixels, greaterThan(20));
        expect(difference / inkPixels, lessThan(12));
        final sums = <int>[];
        for (final time in [
          4000000,
          4200000,
          4400000,
          4600000,
          4800000,
          5000000,
        ]) {
          final bytes = await _render(
            cache,
            (canvas) => cache.paint(canvas, time, 1.0, colors),
          );
          var sum = 0;
          for (var i = 0; i < bytes.length; i += 4) {
            sum += bytes[i];
          }
          sums.add(sum);
        }
        for (var i = 1; i < sums.length; i++) {
          expect(sums[i], greaterThan(sums[i - 1]));
        }
      });
      expect(debugKaraokeTextLayoutCount, layouts);
      final dynamic timing = cache.tokens.single.units.single.timing;
      expect(timing.sourceTokenStartUs, 1000000);
      expect(timing.sourceTokenEndUs, 9000000);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'synthetic contiguous relay shares fixed feather in every fragment',
    (tester) async {
      await _fonts(tester);
      final line = LyricLine(timestamp: Duration.zero, texts: ['slow words']);
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 600,
            child: MobileLyricsList(
              lines: [
                line,
                LyricLine(
                  timestamp: const Duration(seconds: 8),
                  texts: ['next'],
                ),
              ],
              active: 0,
              karaokeLyricsMode: KaraokeLyricsMode.all,
              fontFamily: 'Coverage',
              fontSize: 30,
            ),
          ),
        ),
      );
      final dynamic cache = tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byKey(const ValueKey('mobile_lyric_0')),
              matching: find.byKey(
                const ValueKey('mobile_karaoke_single_pass_paint'),
              ),
            ),
          )
          .painter;
      final dynamic ink = cache.cache;
      expect(ink.sweepRelays, isNotEmpty);
      for (final dynamic token in ink.tokens) {
        for (final dynamic fragment in token.fragments) {
          if (fragment.relay != null) {
            expect(fragment.feather, fragment.relay.feather);
          }
        }
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'symbol ink participates in the real cached sweep without relayout',
    (tester) async {
      await _fonts(tester);
      for (final text in ['*****', '✱✱✱✱✱', '＊＊＊＊＊']) {
        final line = LyricLine(
          timestamp: Duration.zero,
          texts: [text],
          tokens: [
            [
              LyricToken(
                text: text,
                start: const Duration(seconds: 1),
                end: const Duration(seconds: 3),
              ),
            ],
          ],
        );
        await tester.pumpWidget(_host(text, sourceLine: line));
        final dynamic painter = _painter(tester), cache = painter.cache;
        final dynamic colors = painter.colors.withColors(
          Colors.white,
          Colors.white.withValues(alpha: .36),
        );
        await _warm(tester, cache);
        final layouts = debugKaraokeTextLayoutCount;
        final counts = <int>[];
        await tester.runAsync(() async {
          for (final time in [0, 2000000, 4000000]) {
            final bytes = await _render(
              cache,
              (canvas) => cache.paint(canvas, time, 1.0, colors),
            );
            var white = 0;
            for (var i = 0; i < bytes.length; i += 4) {
              if (bytes[i] > 180 && bytes[i + 1] > 180 && bytes[i + 2] > 180) {
                white++;
              }
            }
            counts.add(white);
          }
        });
        expect(counts.first, 0);
        expect(
          counts[1],
          greaterThan(20),
          reason: '$text must have visible partial highlighting',
        );
        expect(counts.last, greaterThan(counts[1] * 1.2));
        expect(debugKaraokeTextLayoutCount, layouts);
        for (final dynamic token in cache.tokens) {
          for (final dynamic unit in token.units) {
            expect(unit.timing.sourceTokenStartUs, 1000000);
            expect(unit.timing.sourceTokenEndUs, 3000000);
          }
        }
      }
    },
  );
  testWidgets(
    'a single-letter word hands motion across a short space without changing timing',
    (tester) async {
      await _fonts(tester);
      const text = 'say I go';
      final line = LyricLine(
        timestamp: Duration.zero,
        texts: [text, '静态翻译'],
        tokens: [
          [
            LyricToken(
              text: 'say ',
              start: Duration.zero,
              end: const Duration(milliseconds: 600),
            ),
            LyricToken(
              text: 'I ',
              start: const Duration(milliseconds: 600),
              end: const Duration(milliseconds: 800),
            ),
            LyricToken(
              text: 'go',
              start: const Duration(milliseconds: 800),
              end: const Duration(milliseconds: 1400),
            ),
          ],
          const [],
        ],
      );
      await tester.pumpWidget(_host(text, sourceLine: line));
      final dynamic painter = _painter(tester), cache = painter.cache;
      await _warm(tester, cache);
      final all = <dynamic>[
        for (final dynamic token in cache.tokens) ...token.units as List,
      ];
      final int index = all.indexWhere(
        (u) => text.substring(u.range.start, u.range.end) == 'I',
      );
      expect(index, greaterThan(0));
      final int probe = all[index].timing.liftStartUs - 30000;
      expect(cache.followerTimeline.ownAt(index, probe), 0);
      final layouts = debugKaraokeTextLayoutCount;
      final buffer = cache.lifts;
      final recorder = ui.PictureRecorder();
      cache.paint(Canvas(recorder), probe, 1.0, painter.colors);
      recorder.endRecording().dispose();
      expect(cache.lifts[index], lessThan(-.01));
      expect(all[index].timing.sourceTokenStartUs, 600000);
      expect(all[index].timing.sourceTokenEndUs, 800000);
      for (final us in [550000, 600000, 700000, 800000]) {
        expect(
          karaokeGlyphHighlightAt(us, all[index].timing),
          ((us - 550000) / 250000).clamp(0.0, 1.0),
        );
      }
      for (final hz in [60, 90, 120]) {
        for (final rate in [.75, 1.0, 1.5, 2.0]) {
          final previous = List<double>.filled(all.length, 0);
          for (var frame = 0; frame < hz * 3; frame++) {
            final time = (frame * 1000000 / hz * rate).round();
            final recorder = ui.PictureRecorder();
            cache.paint(Canvas(recorder), time, 1.0, painter.colors);
            recorder.endRecording().dispose();
            for (var i = 0; i < all.length; i++) {
              final dy = cache.lifts[i] as double;
              expect((dy - previous[i]).abs(), lessThan(.35));
              expect(dy, inInclusiveRange(-cache.liftHeight * 1.1, 0));
              expect(
                cache.highlights[i],
                karaokeGlyphHighlightAt(time, all[i].timing),
              );
              previous[i] = dy;
            }
          }
        }
      }
      expect(identical(cache.lifts, buffer), isTrue);
      expect(debugKaraokeTextLayoutCount, layouts);
      expect(cache.drawTranslation, isTrue);
    },
  );
  testWidgets(
    'Chinese and Japanese followers bridge short token gaps without moving highlight',
    (tester) async {
      await _fonts(tester);
      for (final text in ['中文歌词', 'かなカナ', 'か\u3099くせい', '中か文ナ']) {
        final ranges = karaokeGraphemeRanges(text);
        final source = LyricLine(
          timestamp: Duration.zero,
          texts: [text, 'static translation'],
          tokens: [
            [
              for (var i = 0; i < ranges.length; i++)
                LyricToken(
                  text: text.substring(ranges[i].start, ranges[i].end),
                  start: Duration(milliseconds: i * 220),
                  end: Duration(milliseconds: i * 220 + 190),
                ),
            ],
            const [],
          ],
        );
        await tester.pumpWidget(_host(text, sourceLine: source));
        final dynamic painter = _painter(tester);
        final dynamic cache = painter.cache;
        await _warm(tester, cache);
        final all = <dynamic>[
          for (final dynamic token in cache.tokens) ...token.units as List,
        ];
        expect(all.length, ranges.length);
        final int probe = all[1].timing.liftStartUs - 20000;
        expect(cache.followerTimeline.ownAt(1, probe), 0);
        final layouts = debugKaraokeTextLayoutCount;
        final buffer = cache.lifts;
        for (final hz in [60, 90, 120]) {
          double previous = 0;
          for (var frame = 0; frame < hz * 2; frame++) {
            final us = (frame * 1000000 / hz).round();
            final recorder = ui.PictureRecorder();
            cache.paint(Canvas(recorder), us, 1.0, painter.colors);
            recorder.endRecording().dispose();
            expect(cache.lifts[1], lessThanOrEqualTo(previous + 1e-12));
            expect((cache.lifts[1] - previous).abs(), lessThan(.2));
            previous = cache.lifts[1] as double;
            for (var i = 0; i < all.length; i++) {
              expect(
                cache.highlights[i],
                karaokeGlyphHighlightAt(us, all[i].timing),
              );
              expect(all[i].timing.sourceTokenStartUs, i * 220000);
              expect(all[i].timing.sourceTokenEndUs, i * 220000 + 190000);
            }
          }
        }
        final recorder = ui.PictureRecorder();
        cache.paint(Canvas(recorder), probe, 1.0, painter.colors);
        recorder.endRecording().dispose();
        expect(
          cache.lifts[1],
          lessThan(0),
          reason: '$text follows across a 30ms token gap',
        );
        expect(cache.lifts[1].abs(), lessThan(cache.liftHeight * .25));
        expect(cache.drawTranslation, isTrue);
        expect(identical(cache.lifts, buffer), isTrue);
        expect(debugKaraokeTextLayoutCount, layouts);
      }
    },
  );

  testWidgets(
    'gentle followers precede own motion in every script without relayout',
    (tester) async {
      await _fonts(tester);
      for (final text in ['中文歌词', 'Follow', 'かなカナ', '中aか文']) {
        await tester.pumpWidget(_host(text));
        final dynamic painter = _painter(tester);
        final dynamic cache = painter.cache;
        await _warm(tester, cache);
        final dynamic units = cache.tokens.first.units;
        // CJK may have one token per character; flatten only outside paint.
        final all = <dynamic>[
          for (final dynamic token in cache.tokens) ...token.units as List,
        ];
        expect(all.length, greaterThanOrEqualTo(4));
        final probe =
            ((all[0].timing.liftStartUs as int) +
                (all[1].timing.liftStartUs as int)) ~/
            2;
        expect(
          karaokeGlyphLiftAt(probe, all[1].timing, karaokeDefaultMotion),
          0,
        );
        final layouts = debugKaraokeTextLayoutCount;
        final buffer = cache.lifts;
        final recorder = ui.PictureRecorder();
        cache.paint(Canvas(recorder), probe, 1.0, painter.colors);
        recorder.endRecording().dispose();
        expect(
          cache.lifts[1],
          lessThan(0),
          reason: '$text: next glyph follows before own onset',
        );
        expect(
          cache.lifts[1],
          greaterThan(cache.lifts[0]),
          reason: 'Follower is smaller than its leader',
        );
        expect(cache.lifts[1].abs(), lessThan(cache.liftHeight * .25));
        expect(identical(cache.lifts, buffer), isTrue);
        expect(debugKaraokeTextLayoutCount, layouts);
        expect(units, isNotEmpty);
      }
    },
  );
  testWidgets(
    'supplied Chinese timestamps and real pauses are not synthesized away',
    (tester) async {
      await _fonts(tester);
      final source = LyricLine(
        timestamp: const Duration(seconds: 1),
        texts: ['中文'],
        tokens: [
          [
            LyricToken(
              text: '中',
              start: const Duration(seconds: 1),
              end: const Duration(seconds: 2),
            ),
            LyricToken(
              text: '文',
              start: const Duration(seconds: 3),
              end: const Duration(seconds: 4),
            ),
          ],
        ],
      );
      await tester.pumpWidget(_host('中文', sourceLine: source));
      final dynamic cache = _painter(tester).cache;
      expect(cache.synthetic, isFalse);
      expect(cache.sweepRelays, isEmpty);
      expect(cache.tokens[0].units.first.timing.sourceTokenEndUs, 2000000);
      expect(cache.tokens[1].units.first.timing.sourceTokenStartUs, 3000000);
      expect(
        cache.tokens[1].units.first.timing.highlightStartUs,
        greaterThan(2900000),
      );
    },
  );
  testWidgets(
    'production follower chains break at gaps, wraps and real pauses',
    (tester) async {
      await _fonts(tester);
      for (final text in [
        'Following  softly',
        'supercalifragilisticexpialidocious',
        '中文 歌词',
        'かな カナ',
        '中文歌词中文歌词中文歌词中文歌词中文歌词',
        'かなカナかなカナかなカナかなカナかなカナ',
      ]) {
        await tester.pumpWidget(_host(text));
        final dynamic cache = _painter(tester).cache;
        final all = <dynamic>[
          for (final dynamic token in cache.tokens) ...token.units as List,
        ];
        var boundaries = 0;
        for (var i = 1; i < all.length; i++) {
          final before = all[i - 1], current = all[i];
          final a = text.substring(before.range.start, before.range.end);
          final b = text.substring(current.range.start, current.range.end);
          if (a.trim().isNotEmpty &&
              b.trim().isNotEmpty &&
              before.fragment.row == current.fragment.row &&
              before.range.end == current.range.start) {
            continue;
          }
          boundaries++;
          for (var us = 0; us < current.timing.liftStartUs; us += 16667) {
            expect(cache.followerTimeline.liftAt(i, us), 0);
          }
        }
        expect(boundaries, greaterThan(0));
      }
      final line = LyricLine(
        timestamp: Duration.zero,
        texts: ['中文歌'],
        tokens: [
          [
            LyricToken(
              text: '中',
              start: Duration.zero,
              end: const Duration(milliseconds: 400),
            ),
            LyricToken(
              text: '文',
              start: const Duration(milliseconds: 1300),
              end: const Duration(milliseconds: 1700),
            ),
            LyricToken(
              text: '歌',
              start: const Duration(milliseconds: 1700),
              end: const Duration(milliseconds: 2100),
            ),
          ],
        ],
      );
      await tester.pumpWidget(_host('中文歌', sourceLine: line));
      final dynamic cache = _painter(tester).cache;
      expect(cache.synthetic, isFalse);
      expect(cache.followerTimeline.ownAt(0, 1000000), 1);
      expect(cache.followerTimeline.liftAt(1, 1000000), 0);
      expect(cache.tokens[1].units.first.timing.sourceTokenStartUs, 1300000);
    },
  );
  testWidgets(
    'synthetic Chinese relays share a front without boundary resets',
    (tester) async {
      await _fonts(tester);
      await tester.pumpWidget(_host('中文歌词持续推进'));
      final dynamic painter = _painter(tester);
      final dynamic cache = painter.cache;
      await _warm(tester, cache);
      final builds = debugKaraokeTextLayoutCount;
      final boundary = cache.tokens.first.range.token.end.inMicroseconds as int;
      for (final hz in [60, 90, 120]) {
        double? previous;
        for (var frame = -3; frame <= 3; frame++) {
          final recorder = ui.PictureRecorder();
          cache.paint(
            Canvas(recorder),
            boundary + (frame * 1000000 / hz).round(),
            1.0,
            painter.colors,
          );
          recorder.endRecording().dispose();
          final fronts = <double>[];
          for (final dynamic token in cache.tokens) {
            for (final dynamic fragment in token.fragments) {
              if (fragment.row == 0) {
                fronts.add(cache.fragmentFronts[fragment.index] as double);
              }
            }
          }
          expect(fronts.length, greaterThan(1));
          for (final front in fronts.skip(1)) {
            expect(
              front,
              closeTo(fronts.first, .00001),
              reason: 'one continuous front per physical row',
            );
          }
          if (previous != null) expect(fronts.first, greaterThan(previous));
          previous = fronts.first;
        }
      }
      expect(debugKaraokeTextLayoutCount, builds);
    },
  );
  testWidgets(
    'native phrase sweep skips internal whitespace without moving source time',
    (tester) async {
      await _fonts(tester);
      const text = 'مرحبا           بالعالم';
      final line = LyricLine(
        timestamp: const Duration(seconds: 1),
        texts: const [text],
        tokens: [
          [
            LyricToken(
              text: text,
              start: const Duration(seconds: 1),
              end: const Duration(seconds: 5),
            ),
          ],
        ],
      );
      await tester.pumpWidget(_host(text, sourceLine: line));
      final dynamic cache = _painter(tester).cache;
      final dynamic token = cache.tokens.first;
      expect(token.nativeShaping, isTrue);
      var total = 0.0;
      var physical = 0.0;
      for (final dynamic fragment in token.fragments) {
        total += fragment.sweep.length as double;
        physical += fragment.bounds.width as double;
        var previous = fragment.sweep.frontAt(0.0, 0.0, rtl: true) as double;
        for (var frame = 1; frame <= 120; frame++) {
          final front =
              fragment.sweep.frontAt(frame / 120, 0.0, rtl: true) as double;
          expect(front, lessThanOrEqualTo(previous));
          previous = front;
        }
      }
      expect(
        total,
        lessThan(physical * .85),
        reason: 'spaces do not consume visual advance',
      );
      for (final dynamic unit in token.units) {
        expect(unit.timing.sourceTokenStartUs, 1000000);
        expect(unit.timing.sourceTokenEndUs, 5000000);
      }
      final builds = debugKaraokeTextLayoutCount;
      await _warm(tester, cache);
      final painter = _painter(tester);
      for (var frame = 0; frame <= 120; frame++) {
        final recorder = ui.PictureRecorder();
        cache.paint(
          Canvas(recorder),
          1000000 + frame * 33333,
          1.0,
          painter.colors,
        );
        recorder.endRecording().dispose();
      }
      expect(
        debugKaraokeTextLayoutCount,
        builds,
        reason: 'no per-frame text layout',
      );
    },
  );
  testWidgets('descenders retain their entire shaped ink in their own glyph', (
    tester,
  ) async {
    await _fonts(tester);
    const sample = 'money gypsy playing';
    await tester.pumpWidget(_host(sample, fontSize: 48));
    final dynamic cache = _painter(tester).cache;
    await _warm(tester, cache);
    await tester.runAsync(() async {
      for (final dynamic token in cache.tokens) {
        for (final dynamic unit in token.units) {
          final int start = unit.range.start;
          final int end = unit.range.end;
          if (!'ygp'.contains(sample.substring(start, end))) continue;
          final expected = await _render(cache, (canvas) {
            final layout = TextPainter(
              text: TextSpan(
                style: (cache.style as TextStyle).copyWith(
                  color: Colors.transparent,
                  shadows: null,
                  decoration: TextDecoration.none,
                ),
                children: [
                  TextSpan(text: sample.substring(0, start)),
                  TextSpan(
                    text: sample.substring(start, end),
                    style: const TextStyle(color: Colors.white),
                  ),
                  TextSpan(text: sample.substring(end)),
                ],
              ),
              textAlign: TextAlign.left,
              textDirection: TextDirection.ltr,
              textScaler: cache.textScaler,
            )..layout(maxWidth: cache.width);
            layout.paint(canvas, Offset.zero);
            layout.dispose();
          });
          final actual = await _render(
            cache,
            (canvas) => cache.debugPaintOwnedGlyph(canvas, unit.inkId),
          );
          var missing = 0;
          for (var i = 0; i < actual.length; i += 4) {
            if (expected[i] - actual[i] > 12) {
              missing++;
            }
          }
          expect(
            missing,
            0,
            reason: '${sample.substring(start, end)} at $start',
          );
        }
      }
    });
  });

  testWidgets('moving glyphs have exclusive ink including descender tails', (
    tester,
  ) async {
    await _fonts(tester);
    for (final size in [30.0, 48.0, 72.0]) {
      await tester.pumpWidget(_host('money gypsy playing ', fontSize: size));
      final dynamic cache = _painter(tester).cache;
      await _warm(tester, cache);
      await tester.runAsync(() async {
        Uint8List? claimed;
        for (final dynamic token in cache.tokens) {
          for (final dynamic unit in token.units) {
            final pixels = await _render(
              cache,
              (canvas) => cache.debugPaintOwnedGlyph(canvas, unit.inkId),
            );
            claimed ??= Uint8List(pixels.length ~/ 4);
            var duplicate = 0;
            for (var i = 0; i < pixels.length; i += 4) {
              if (pixels[i] <= 12) continue;
              if (claimed[i ~/ 4] != 0) duplicate++;
              claimed[i ~/ 4] = 1;
            }
            expect(
              duplicate,
              0,
              reason: 'size=$size range=${unit.range.start}',
            );
          }
        }
      });
    }
  });

  testWidgets('fractional lifts smoothly filter complete descender ink', (
    tester,
  ) async {
    await _fonts(tester);
    for (final dpr in [1.0, 3.0]) {
      await tester.pumpWidget(
        _host('money gypsy playing', fontSize: 48, dpr: dpr),
      );
      final dynamic cache = _painter(tester).cache;
      await _warm(tester, cache);
      await tester.runAsync(() async {
        for (final dynamic token in cache.tokens) {
          for (final dynamic unit in token.units) {
            final full = await _render(cache, (canvas) {
              cache.debugPaintOwnedGlyph(canvas, unit.inkId);
            });
            final layered = await _render(cache, (canvas) {
              canvas.save();
              canvas.translate(0, -.5);
              cache.debugPaintOwnedGlyph(canvas, unit.inkId);
              canvas.restore();
            });
            var fullInk = 0;
            var movedInk = 0;
            for (var i = 0; i < full.length; i += 4) {
              fullInk += full[i];
              movedInk += layered[i];
            }
            expect(
              (fullInk - movedInk).abs(),
              lessThanOrEqualTo(fullInk * .025 + 12),
              reason: 'dpr=$dpr range=${unit.range.start}',
            );
          }
        }
      });
    }
  });

  testWidgets(
    'normal handoff fades only sung ink and never flashes translation',
    (tester) async {
      await _fonts(tester);
      final position = ValueNotifier(const Duration(milliseconds: 700));
      addTearDown(position.dispose);
      final lines = [
        LyricLine(
          timestamp: Duration.zero,
          texts: const ['money gypsy', '翻译不高亮'],
        ),
        LyricLine(
          timestamp: const Duration(seconds: 2),
          texts: const ['playing'],
        ),
      ];
      Widget host(int active) => MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 600,
            child: MobileLyricsList(
              lines: lines,
              active: active,
              positionListenable: position,
              karaokeLyricsMode: KaraokeLyricsMode.all,
              fontFamily: 'Coverage',
              fontSize: 30,
              activeColor: Colors.orange,
              highlightActiveLine: false,
              textAlign: TextAlign.left,
            ),
          ),
        ),
      );
      dynamic rowPainter(int index) => tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byKey(ValueKey('mobile_lyric_$index')),
              matching: find.byKey(
                const ValueKey('mobile_karaoke_single_pass_paint'),
              ),
            ),
          )
          .painter;
      await tester.pumpWidget(host(0));
      await tester.pump();
      // Resource preparation has its own idle queue. Finish it before timing
      // the 240ms ink handoff, rather than advancing that animation to warm.
      await _warm(tester, rowPainter(0).cache);
      await _warm(tester, rowPainter(1).cache);
      final dynamic before = rowPainter(0);
      final oldActive = before.colors.active;
      final oldInactive = before.colors.inactive;
      await tester.pumpWidget(host(1));
      final dynamic after = rowPainter(0);
      expect(after.colors.active, oldActive, reason: 'no white colour swap');
      expect(
        after.colors.inactive,
        oldInactive,
        reason: 'unplayed and translation stay dim',
      );
      final firstStrength = after.highlightStrength as double;
      expect(rowPainter(1).highlightStrength, 0);
      final entered = rowPainter(1).colors.inactive;
      final dynamic cache = after.cache;
      await _warm(tester, cache);
      await tester.runAsync(() async {
        final bright = await _render(
          cache,
          (canvas) => cache.paint(canvas, 700000, 0.0, after.colors, 1.0),
        );
        final dim = await _render(
          cache,
          (canvas) => cache.paint(canvas, 700000, 0.0, after.colors, 0.0),
        );
        // Lower half of the second text row is translation only. The sweep's
        // focus envelope must not brighten or dim its actual painted pixels.
        final start =
            ((24 + cache.height * .75).ceil() * (cache.width.ceil() + 48) * 4)
                as int;
        expect(bright.sublist(start), dim.sublist(start));
      });
      await tester.pump(const Duration(milliseconds: 120));
      expect(rowPainter(0).highlightStrength, lessThan(firstStrength));
      expect(rowPainter(1).highlightStrength, inExclusiveRange(0, 1));
      expect(rowPainter(1).colors.inactive, entered);
      await tester.pump(const Duration(milliseconds: 160));
      expect(rowPainter(0).highlightStrength, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('shaped coverage has no duplicate alpha or cut ink at wraps', (
    tester,
  ) async {
    await _fonts(tester);
    for (final sample in const [
      'A👨‍👩‍👧‍👦B',
      'A🙂B',
      'Love ❤️ and ☀️ shine',
      'لا تُطفئ الضوء',
      'AशांतB',
      'ABCالعربيةZ',
      'École Ångström é 中文 mixed English',
      'supercalifragilisticexpialidocious softly follows',
      '快速中文测试边界高亮文字',
      'AVATAR office fluffy wonderful',
      'money gypsy playing y g p quietly',
    ]) {
      await tester.pumpWidget(_host(sample));
      final dynamic painter = _painter(tester);
      final dynamic cache = painter.cache;
      final dynamic colors = painter.colors.withColors(
        Colors.white.withValues(alpha: .36),
        Colors.white.withValues(alpha: .36),
      );
      final tint = ui.ColorFilter.mode(
        Colors.white.withValues(alpha: .36),
        BlendMode.srcIn,
      );
      final reference = await tester.runAsync(
        () => _render(cache, (canvas) {
          final layout = TextPainter(
            text: TextSpan(
              text: sample,
              style: (cache.style as TextStyle).copyWith(
                color: Colors.white,
                shadows: null,
              ),
            ),
            textAlign: TextAlign.left,
            textDirection: TextDirection.ltr,
            textScaler: cache.textScaler,
            locale: cache.locale,
          )..layout(maxWidth: cache.width);
          canvas.saveLayer(cache.fullBounds, Paint()..colorFilter = tint);
          layout.paint(canvas, Offset.zero);
          canvas.restore();
          layout.dispose();
        }),
      );
      // Both the immediately available Picture fallback and warmed atlas
      // must preserve the intact paragraph's alpha, including fallback fonts.
      for (final warm in [false, true]) {
        if (warm) await _warm(tester, cache);
        await tester.runAsync(() async {
          for (final time in [900000, 1900000, 3900000]) {
            final actual = await _render(cache, (canvas) {
              cache.paint(canvas, time, 0.0, colors);
            });
            var peak = 0;
            var differing = 0;
            for (var i = 0; i < actual.length; i += 4) {
              final delta = (actual[i] - reference![i]).abs();
              if (delta > peak) peak = delta;
              if (delta > 12) differing++;
            }
            expect(
              peak,
              lessThanOrEqualTo(12),
              reason:
                  '$sample warm=$warm time=$time differs at $differing pixels',
            );
          }
        });
      }
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('fallback runs share physical rows and preserve timing order', (
    tester,
  ) async {
    await _fonts(tester);
    await tester.pumpWidget(_host('A👨‍👩‍👧‍👦B'));
    final dynamic token = _painter(tester).cache.tokens.first;
    expect(token.fragments, hasLength(1));
    expect(token.units, hasLength(1));
    expect(token.units.first.range.start, 0);
    expect(token.units.first.range.end, 'A👨‍👩‍👧‍👦B'.length);
    final dynamic cache = _painter(tester).cache;
    expect(
      token.fragments.first.layerBounds.contains(
        token.fragments.first.bounds.center,
      ),
      isTrue,
    );
    // Native fallback still owns a complete shaped run. Its GPU layer is
    // prepared outside paint and does not include unrelated paragraph rows.
    expect(
      token.fragments.first.layerBounds.width,
      lessThan(cache.fullBounds.width),
    );
    await tester.pumpWidget(_host('supercalifragilisticexpialidocious'));
    final dynamic longWord = _painter(tester).cache.tokens.first;
    var previous = -1;
    for (final dynamic unit in longWord.units) {
      final int start = unit.timing.highlightStartUs;
      expect(start, greaterThanOrEqualTo(previous));
      previous = start;
    }
    expect(longWord.fragments.length, greaterThan(1));
  });

  testWidgets(
    'completed highlight covers overhang ink, not only advance boxes',
    (tester) async {
      await _fonts(tester);
      const sample = 'money gypsy playing y g p';
      await tester.pumpWidget(_host(sample, fontSize: 48));
      final dynamic painter = _painter(tester);
      final dynamic cache = painter.cache;
      await _warm(tester, cache);
      await tester.runAsync(() async {
        final actual = await _render(
          cache,
          (canvas) => cache.paint(
            canvas,
            20000000,
            0.0,
            painter.colors.withColors(
              Colors.white,
              Colors.white.withValues(alpha: .36),
            ),
          ),
        );
        final expected = await _render(cache, (canvas) {
          final layout = TextPainter(
            text: TextSpan(
              text: sample,
              style: (cache.style as TextStyle).copyWith(
                color: Colors.white,
                shadows: null,
                decoration: TextDecoration.none,
              ),
            ),
            textAlign: TextAlign.left,
            textDirection: TextDirection.ltr,
            textScaler: cache.textScaler,
          )..layout(maxWidth: cache.width);
          layout.paint(canvas, Offset.zero);
          layout.dispose();
        });
        var missing = 0;
        for (var i = 0; i < actual.length; i += 4) {
          if (expected[i] - actual[i] > 12) missing++;
        }
        expect(
          missing,
          0,
          reason: 'fully sung descenders/overhangs stay white',
        );
      });
    },
  );

  testWidgets('warmed letters use no solid saveLayer, with bounded image', (
    tester,
  ) async {
    await _fonts(tester);
    await tester.pumpWidget(_host('supercalifragilisticexpialidocious'));
    final dynamic painter = _painter(tester);
    await _warm(tester, painter.cache);
    expect(painter.cache.imageReady, isTrue);
    expect(painter.cache.imageBytes, lessThanOrEqualTo(4194304));
    expect(painter.cache.restSuffixMasks, isEmpty);
    final layouts = debugKaraokeTextLayoutCount;
    final layers = debugKaraokeSolidLayerCount;
    for (var f = 0; f < 120; f++) {
      final recorder = ui.PictureRecorder();
      painter.cache.paint(Canvas(recorder), f * 8333, 1.0, painter.colors);
      recorder.endRecording().dispose();
    }
    expect(debugKaraokeTextLayoutCount, layouts);
    expect(debugKaraokeSolidLayerCount, layers);
  });

  testWidgets('DPR invalidates raster and stale async results dispose safely', (
    tester,
  ) async {
    await tester.pumpWidget(_host('字形 cache', dpr: 1));
    final dynamic previous = _painter(tester).cache;
    final Future<void> pending = previous.prepareImage();
    await tester.pumpWidget(_host('字形 cache', dpr: 3));
    final dynamic next = _painter(tester).cache;
    expect(next, isNot(same(previous)));
    await _warm(tester, next);
    await pending;
    expect(previous.imageReady, isFalse);
    expect(next.imageReady, isTrue);
    expect(next.pixelRatio, 3);
    await tester.pumpWidget(const SizedBox());
    expect(next.imageReady, isFalse);
  });

  testWidgets('native run coverage is bounded and avoids per-frame layers', (
    tester,
  ) async {
    await _fonts(tester);
    await tester.pumpWidget(_host('ABCالعربيةZ शांत A🙂B', dpr: 3));
    final dynamic painter = _painter(tester);
    final dynamic cache = painter.cache;
    await _warm(tester, cache);
    expect(cache.imageBytes, lessThanOrEqualTo(6291456));
    for (final dynamic token in cache.tokens) {
      if (token.nativeShaping as bool) {
        for (final dynamic fragment in token.fragments) {
          expect(fragment.nativeInk, isNotNull);
        }
      }
    }
    final layouts = debugKaraokeTextLayoutCount;
    final solid = debugKaraokeSolidLayerCount,
        gradient = debugKaraokeGradientLayerCount;
    for (var f = 0; f < 120; f++) {
      final recorder = ui.PictureRecorder();
      cache.paint(Canvas(recorder), 600000 + f * 8333, 1.0, painter.colors, .5);
      recorder.endRecording().dispose();
    }
    expect(debugKaraokeTextLayoutCount, layouts);
    expect(debugKaraokeSolidLayerCount, solid);
    expect(debugKaraokeGradientLayerCount, gradient);
    await tester.pumpWidget(const SizedBox());
    expect(cache.imageBytes, 0);
    expect(cache.imageReady, isFalse);
  });

  testWidgets('long lines cannot wrap atlas IDs into other glyphs', (
    tester,
  ) async {
    await _fonts(tester);
    final text = List.filled(514, '快').join();
    await tester.pumpWidget(_host(text, fontSize: 12));
    final dynamic painter = _painter(tester);
    final dynamic cache = painter.cache;
    await _warm(tester, cache);
    var fallback = 0;
    for (final dynamic token in cache.tokens) {
      for (final dynamic unit in token.units) {
        expect(unit.inkId, lessThan(512));
        if (token.nativeShaping as bool) {
          fallback++;
          expect(unit.inkId, 511);
        } else {
          expect(unit.inkId, lessThan(509));
        }
      }
    }
    expect(fallback, greaterThan(0));
    expect(cache.imageBytes, lessThanOrEqualTo(6291456));
    await tester.runAsync(() async {
      final actual = await _render(
        cache,
        (canvas) => cache.paint(canvas, 20000000, 0.0, painter.colors, 0.0),
      );
      final expected = await _render(cache, (canvas) {
        final layout = TextPainter(
          text: TextSpan(
            text: text,
            style: (cache.style as TextStyle).copyWith(
              color: painter.colors.inactive,
              decoration: TextDecoration.none,
              shadows: null,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: cache.width);
        layout.paint(canvas, Offset.zero);
        layout.dispose();
      });
      var missing = 0;
      for (var i = 0; i < actual.length; i += 4) {
        if (expected[i] - actual[i] > 12) missing++;
      }
      expect(missing, 0);
    });
  });
}

Future<void> _warm(WidgetTester tester, dynamic cache) async {
  cache.prepareImage();
  // The native raster callback arrives outside fake time, but the Future's
  // continuation was registered during build inside fake time. Pump both.
  for (var i = 0; i < 80 && !cache.imageReady; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(cache.imageReady, isTrue);
}

final _lineCache = <String, LyricLine>{};
Widget _host(
  String text, {
  double dpr = 1,
  double fontSize = 30,
  LyricLine? sourceLine,
}) => MaterialApp(
  theme: ThemeData(
    fontFamilyFallback: const [
      'CoverageEmoji',
      'CoverageIndic',
      'CoverageArabic',
    ],
  ),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(size: const Size(800, 600), devicePixelRatio: dpr),
      child: SizedBox(
        width: 220,
        height: 600,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 220,
            child: MobileLyricsList(
              lines: [
                sourceLine ??
                    _lineCache.putIfAbsent(
                      text,
                      () => LyricLine(timestamp: Duration.zero, texts: [text]),
                    ),
              ],
              active: 0,
              karaokeLyricsMode: KaraokeLyricsMode.all,
              fontFamily: 'Coverage',
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              textAlign: TextAlign.left,
              lineBlurEnabled: false,
            ),
          ),
        ),
      ),
    ),
  ),
);
dynamic _painter(WidgetTester tester) => tester
    .widget<CustomPaint>(
      find.byKey(const ValueKey('mobile_karaoke_single_pass_paint')),
    )
    .painter;

Future<Uint8List> _render(dynamic cache, void Function(Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawColor(Colors.black, BlendMode.src);
  canvas.translate(24, 24);
  draw(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    cache.width.ceil() + 48,
    cache.height.ceil() + 48,
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final result = Uint8List.fromList(bytes!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return result;
}

Future<void> _fonts(WidgetTester tester) => tester.runAsync(() async {
  for (final entry in const {
    'Coverage': 'assets/fonts/MiSansVF.ttf',
    // Optional host fallbacks only; Android uses its system fonts. Nothing is
    // bundled or downloaded for this regression test.
    'CoverageEmoji': 'C:/Windows/Fonts/seguiemj.ttf',
    'CoverageIndic': 'C:/Windows/Fonts/Nirmala.ttf',
    'CoverageArabic': 'C:/Windows/Fonts/arial.ttf',
  }.entries) {
    final file = File(entry.value);
    if (!await file.exists()) continue;
    final bytes = await file.readAsBytes();
    await (FontLoader(
      entry.key,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }
});
