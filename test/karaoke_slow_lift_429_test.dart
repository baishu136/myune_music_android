import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/widgets/karaoke_motion.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';

KaraokeGlyphTiming _timing(int start, int span) => KaraokeGlyphTiming(
  sourceTokenStartUs: start,
  sourceTokenEndUs: start + span,
  visualTokenStartUs: start,
  highlightStartUs: start,
  highlightEndUs: start + span,
  liftStartUs: start,
  estimatedCadenceUs: span,
);

void main() {
  for (final config in [karaokeDefaultMotion, karaokeSmoothMotion]) {
    test(
      'slow ${config.curve.name} keeps moving through a sustained glyph',
      () {
        final glyph = _timing(1000000, 2000000);
        final before = karaokeGlyphLiftAt(2100000, glyph, config);
        final after = karaokeGlyphLiftAt(2400000, glyph, config);
        expect(after - before, greaterThan(.08));
        expect(after, lessThan(.90));
        expect(karaokeGlyphLiftAt(5000000, glyph, config), 1);
        expect(karaokeGlyphLiftAt(900000, glyph, config), 0);
      },
    );
  }

  test('slow neighbours continue gentle traction before their own onset', () {
    final motion = KaraokeFollowerTimeline([
      for (var i = 0; i < 4; i++)
        KaraokeFollowerGlyph(timing: _timing(i * 2000000, 2000000), chain: 0),
    ], karaokeDefaultMotion);
    final first = motion.liftAt(1, 1100000);
    final later = motion.liftAt(1, 1500000);
    expect(later - first, greaterThan(.04));
    expect(later, lessThan(.30));
    expect(motion.ownAt(1, 1500000), 0);
    expect(karaokeGlyphHighlightAt(1500000, _timing(2000000, 2000000)), 0);
  });

  testWidgets('paint clock follows the actual end of a slow lift', (
    tester,
  ) async {
    await (FontLoader(
      'SlowLift',
    )..addFont(rootBundle.load('assets/fonts/MiSansVF.ttf'))).load();
    for (final smooth in [false, true]) {
      final source = LyricLine(
        timestamp: const Duration(seconds: 1),
        texts: ['I'],
        tokens: [
          [
            LyricToken(
              text: 'I',
              start: const Duration(seconds: 1),
              end: const Duration(seconds: 3),
            ),
          ],
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileLyricsList(
              lines: [source],
              active: 0,
              isPlaying: false,
              fontFamily: 'SlowLift',
              fontSize: 40,
              smoothKaraokeMotion: smooth,
            ),
          ),
        ),
      );
      final dynamic painter = tester
          .widget<CustomPaint>(
            find.byKey(const ValueKey('mobile_karaoke_single_pass_paint')),
          )
          .painter;
      final dynamic cache = painter.cache;
      expect(cache.synthetic, isFalse);
      void draw(int us) {
        final recorder = ui.PictureRecorder();
        cache.paint(Canvas(recorder), us, 1.0, painter.colors);
        recorder.endRecording().dispose();
      }

      draw(3050000);
      final double first = cache.lifts[0];
      draw(3090000);
      expect(cache.lifts[0], lessThan(first));
      final media = ValueNotifier(const Duration(microseconds: 3050000));
      final clock = KaraokePaintClock(media)
        ..settleAfterUs = cache.settleAfterUs;
      var paints = 0;
      clock.addListener(() => paints++);
      media.value = const Duration(microseconds: 3090000);
      expect(
        paints,
        1,
        reason: 'a finished highlight must not freeze a live lift',
      );
      draw(cache.settleAfterUs);
      expect(cache.lifts[0], closeTo(-cache.liftHeight, 1e-10));
      media.value = Duration(microseconds: cache.settleAfterUs);
      final settled = paints;
      media.value += const Duration(seconds: 1);
      expect(paints, settled);
      clock.dispose();
      media.dispose();
      await tester.pumpWidget(const SizedBox());
    }
  });

  test('cadence transitions are continuous and very long sustains settle', () {
    final config = karaokeDefaultMotion;
    for (final cadence in [759999, 760000, 760001, 1519999, 1520000, 1520001]) {
      final before = _timing(0, cadence);
      final after = _timing(0, cadence + 1);
      for (var us = 0; us < 3000000; us += 8333) {
        expect(
          (karaokeGlyphLiftAt(us, before, config) -
                  karaokeGlyphLiftAt(us, after, config))
              .abs(),
          lessThan(.00001),
        );
      }
    }
    final held = _timing(0, 30000000);
    expect(karaokeGlyphLiftAt(2500000, held, config), lessThan(1));
    expect(karaokeGlyphLiftAt(3040000, held, config), 1);
    expect(karaokeGlyphHighlightAt(3040000, held), lessThan(.11));
    final motion = KaraokeFollowerTimeline([
      KaraokeFollowerGlyph(timing: held, chain: 0),
    ], config);
    expect(motion.settleAfterUs, 3040000);
  });

  testWidgets(
    'slow shaped ink preserves wraps, buffers and layout while moving',
    (tester) async {
      await (FontLoader(
        'SlowInk',
      )..addFont(rootBundle.load('assets/fonts/MiSansVF.ttf'))).load();
      for (final entry in {
        'cjk': ['慢', '速', '歌', '词'],
        'latin': ['y ', 'g ', 'p'],
        'kana': ['か\u3099', 'く', 'せ', 'い'],
      }.entries) {
        for (final smooth in [false, true]) {
          final text = entry.value.join();
          final source = LyricLine(
            timestamp: Duration.zero,
            texts: [text, 'translation stays still'],
            tokens: [
              [
                for (var i = 0; i < entry.value.length; i++)
                  LyricToken(
                    text: entry.value[i],
                    start: Duration(seconds: i * 2),
                    end: Duration(seconds: (i + 1) * 2),
                  ),
              ],
              [],
            ],
          );
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 140,
                    child: MobileLyricsList(
                      lines: [source],
                      active: 0,
                      isPlaying: false,
                      fontFamily: 'SlowInk',
                      fontSize: 40,
                      smoothKaraokeMotion: smooth,
                      textAlign: TextAlign.left,
                      lineBlurEnabled: false,
                    ),
                  ),
                ),
              ),
            ),
          );
          final dynamic painter = tester
              .widget<CustomPaint>(
                find.byKey(const ValueKey('mobile_karaoke_single_pass_paint')),
              )
              .painter;
          final dynamic cache = painter.cache;
          cache.prepareImage();
          for (var i = 0; i < 80 && !cache.imageReady; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump(const Duration(milliseconds: 20));
          }
          expect(cache.imageReady, isTrue);
          expect(cache.drawTranslation, isTrue);
          final layouts = debugKaraokeTextLayoutCount;
          final buffer = cache.lifts;
          final previous = Float64List(buffer.length);
          for (var us = 0; us <= 3000000; us += 8333) {
            final recorder = ui.PictureRecorder();
            cache.paint(Canvas(recorder), us, 1.0, painter.colors);
            recorder.endRecording().dispose();
            for (var i = 0; i < previous.length; i++) {
              expect(cache.lifts[i], lessThanOrEqualTo(previous[i] + 1e-9));
              expect((cache.lifts[i] - previous[i]).abs(), lessThan(.15));
              previous[i] = cache.lifts[i];
            }
          }
          expect(identical(cache.lifts, buffer), isTrue);
          expect(debugKaraokeTextLayoutCount, layouts);
          final output = Platform.environment['MYUNE_SLOW_LIFT_EVIDENCE'];
          if (output != null) {
            await tester.runAsync(() async {
              final width = cache.width.ceil() + 32 as int;
              final height = cache.height.ceil() + 44 as int;
              final recorder = ui.PictureRecorder();
              final canvas = Canvas(recorder);
              canvas.drawColor(const Color(0xff202027), BlendMode.src);
              for (var frame = 0; frame < 7; frame++) {
                canvas.save();
                canvas.translate(16, (frame * height).toDouble());
                final label = TextPainter(
                  text: TextSpan(
                    text: '${frame * 400} ms',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontFamily: 'SlowInk',
                    ),
                  ),
                  textDirection: TextDirection.ltr,
                )..layout();
                label.paint(canvas, const Offset(0, 4));
                label.dispose();
                canvas.translate(0, 32);
                cache.paint(canvas, frame * 400000, 1.0, painter.colors);
                canvas.restore();
              }
              final picture = recorder.endRecording();
              final image = await picture.toImage(width, height * 7);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '$output/slow-${entry.key}-${smooth ? 'smooth' : 'default'}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
              picture.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox());
        }
      }
    },
  );

  test(
    'pauses, seeks, rates and output buffers share deterministic slow poses',
    () {
      final glyphs = [
        KaraokeFollowerGlyph(timing: _timing(0, 1400000), chain: 0),
        KaraokeFollowerGlyph(timing: _timing(1400000, 2200000), chain: 0),
        KaraokeFollowerGlyph(timing: _timing(5000000, 10000000), chain: 1),
      ];
      for (final config in [karaokeDefaultMotion, karaokeSmoothMotion]) {
        final motion = KaraokeFollowerTimeline(glyphs, config);
        final output = Float64List(3);
        for (final hz in [60, 90, 120]) {
          for (final rate in [.5, 1.0, 1.5, 2.0]) {
            final previous = Float64List(3), velocity = Float64List(3);
            for (var frame = 0; frame <= hz * 9 / rate; frame++) {
              final us = (frame * 1000000 * rate / hz).round();
              motion.writeOffsets(us, 60, output);
              for (var i = 0; i < 3; i++) {
                final pose = motion.liftAt(i, us);
                expect(output[i], closeTo(-4.8 * pose, 1e-10));
                expect(pose, inInclusiveRange(0, 1));
                final speed = (output[i] - previous[i]) * hz;
                expect(output[i], lessThanOrEqualTo(previous[i] + 1e-10));
                expect((speed - velocity[i]).abs(), lessThan(1.6));
                previous[i] = output[i];
                velocity[i] = speed;
                expect(
                  karaokeGlyphHighlightAt(us, glyphs[i].timing),
                  ((us - glyphs[i].timing.highlightStartUs) /
                          (glyphs[i].timing.highlightEndUs -
                              glyphs[i].timing.highlightStartUs))
                      .clamp(0.0, 1.0),
                );
              }
            }
            motion.writeOffsets(1900000, 60, output);
            final paused = output.toList();
            motion.writeOffsets(1900000, 60, output);
            expect(output, paused);
            motion.writeOffsets(300000, 60, output);
            expect(output[2], 0, reason: 'a true rest disconnects traction');
            motion.writeOffsets(1900000, 60, output);
            expect(
              output,
              paused,
              reason: 'seek must not integrate old offsets',
            );
          }
        }
      }
    },
  );
}
