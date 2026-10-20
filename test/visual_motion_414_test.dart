import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/services/artwork_palette_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/widgets/playback_background/fluid_frame_uniforms.dart';
import 'package:myune_music/widgets/playback_background/fluid_colour_motion.dart';

void main() {
  test('smooth preference is opt-in and survives restart', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.initializationFuture;
    expect(settings.smoothKaraokeMotion, isFalse);
    await settings.setSmoothKaraokeMotion(true);
    final restored = SettingsProvider();
    await restored.initializationFuture;
    expect(restored.smoothKaraokeMotion, isTrue);
    settings.dispose();
    restored.dispose();
  });
  test(
    'smooth clock has bounded speed and follows seek pause rate at 60/90/120Hz',
    () {
      for (final hz in [60, 90, 120]) {
        final clock = KaraokeMediaClock(
          const Duration(seconds: 10),
          smoothMotion: true,
        );
        clock.setRunning(true, clock.value);
        var previous = clock.value;
        var previousSpeed = 1.0;
        for (var frame = 1; frame <= hz * 4; frame++) {
          final stamp = Duration(microseconds: (frame * 1000000 / hz).round());
          if (frame % (hz ~/ 5) == 0) {
            clock.readSource(
              const Duration(seconds: 10) +
                  stamp +
                  Duration(milliseconds: frame.isEven ? 70 : -45),
            );
          }
          clock.tick(stamp);
          final speed =
              (clock.value - previous).inMicroseconds / (1000000 / hz);
          expect(speed, inInclusiveRange(.915, 1.085));
          expect((speed - previousSpeed).abs(), lessThan(.04));
          previousSpeed = speed;
          previous = clock.value;
        }
        clock.setRunning(false, clock.value);
        clock.tick(const Duration(seconds: 8));
        expect(clock.value, previous);
        clock.seek(const Duration(seconds: 2), protectFromStaleSource: true);
        expect(clock.value, const Duration(seconds: 2));
        clock.setRunning(true, clock.value);
        clock.changeRate(2, clock.value);
        clock.tick(const Duration(milliseconds: 100));
        expect(clock.value, const Duration(milliseconds: 2200));
        clock.dispose();
      }
    },
  );
  testWidgets('real timed glyphs use continuous relays only when selected', (
    tester,
  ) async {
    await (FontLoader(
      'misans',
    )..addFont(rootBundle.load('assets/fonts/MiSansVF.ttf'))).load();
    final tokens = <LyricToken>[
      LyricToken(
        text: '歌',
        start: const Duration(seconds: 1),
        end: const Duration(milliseconds: 1100),
      ),
      LyricToken(
        text: '词',
        start: const Duration(milliseconds: 1100),
        end: const Duration(milliseconds: 2100),
      ),
      LyricToken(
        text: '连',
        start: const Duration(milliseconds: 2100),
        end: const Duration(milliseconds: 2300),
      ),
      LyricToken(
        text: '贯',
        start: const Duration(milliseconds: 2300),
        end: const Duration(milliseconds: 3300),
      ),
    ];
    final line = LyricLine(
      timestamp: const Duration(seconds: 1),
      texts: ['歌词连贯'],
      tokens: [tokens],
    );
    Widget host(bool enabled) => MaterialApp(
      home: Scaffold(
        body: MobileLyricsList(
          lines: [line],
          active: 0,
          isPlaying: false,
          position: const Duration(milliseconds: 1500),
          fontFamily: 'misans',
          fontSize: 50,
          smoothKaraokeMotion: enabled,
        ),
      ),
    );
    await tester.pumpWidget(host(false));
    dynamic painter = tester
        .widget<CustomPaint>(
          find.byKey(const ValueKey('mobile_karaoke_single_pass_paint')),
        )
        .painter;
    expect(painter.cache.sweepRelays, isEmpty);
    await tester.pumpWidget(host(true));
    painter = tester
        .widget<CustomPaint>(
          find.byKey(const ValueKey('mobile_karaoke_single_pass_paint')),
        )
        .painter;
    final dynamic cache = painter.cache;
    expect(cache.synthetic, isFalse);
    expect(cache.smoothMotion, isTrue);
    expect(cache.followerTimeline.config.fastOvershootFraction, 0);
    expect(cache.sweepRelays.length, 1);
    final dynamic timeline = cache.sweepRelays.first.timeline;
    for (final boundary in [1100000, 2100000, 2300000]) {
      final double middle = timeline.phaseAt(boundary);
      final double before = timeline.phaseAt(boundary - 10);
      final double after = timeline.phaseAt(boundary + 10);
      expect(((middle - before) - (after - middle)).abs(), lessThan(1e-7));
    }
    final starts = [
      for (final dynamic token in cache.tokens) token.range.token.start,
    ];
    expect(starts, tokens.map((t) => t.start).toList());
    final lengths = [
      for (final dynamic token in cache.tokens)
        token.fragments.first.sweep.length,
    ];
    cache.prepareImage();
    for (var i = 0; i < 80 && !cache.imageReady; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(cache.imageReady, isTrue);
    expect([
      for (final dynamic token in cache.tokens)
        token.fragments.first.sweep.length,
    ], lengths);
    final builds = debugKaraokeLayoutBuildCount;
    for (var frame = 0; frame < 120; frame++) {
      final recorder = ui.PictureRecorder();
      cache.paint(
        Canvas(recorder),
        1000000 + frame * 16667,
        1.0,
        painter.colors,
      );
      recorder.endRecording().dispose();
    }
    expect(debugKaraokeLayoutBuildCount, builds);
    void drawAt(int time) {
      final recorder = ui.PictureRecorder();
      cache.paint(Canvas(recorder), time, 1.0, painter.colors);
      recorder.endRecording().dispose();
    }

    drawAt(2500000);
    final pose = List<double>.from(cache.lifts);
    drawAt(700000);
    drawAt(2500000);
    expect(List<double>.from(cache.lifts), pose);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'roaming centres cross the hub with bounded shape, relay and wrap',
    (tester) async {
      final program = await tester.runAsync(
        () => ui.FragmentProgram.fromAsset('shaders/fluid_background.frag'),
      );
      final shader = program!.fragmentShader();
      final packed = FluidFrameUniforms();
      final relay = FluidColourRelayFrame();
      final palette = buildFluidPalette([
        Colors.pink,
        Colors.teal,
        Colors.indigo,
        Colors.amber,
      ], fallbackSeed: Colors.blue);
      var nearest = 1.0, farthest = 0.0, transmitted = 0.0;
      try {
        for (var i = 0; i < 2000; i++) {
          final time = fluidPhaseCycle * i / 2000;
          packed.write(
            shader,
            size: const Size(180, 320),
            time: time,
            motion: 1,
            dim: .3,
            source: palette,
            target: palette,
          );
          final v = packed.values;
          relay.update(time, v);
          for (var field = 0; field < 4; field++) {
            final x = v[6 + field * 2] - .5, y = v[7 + field * 2] - .5;
            final radius = math.sqrt(x * x + y * y);
            nearest = math.min(nearest, radius);
            farthest = math.max(farthest, radius);
            transmitted = math.max(transmitted, relay.strengths[field]);
            final a = v[29 + field * 4],
                b = v[30 + field * 4],
                c = v[31 + field * 4],
                d = v[32 + field * 4];
            final trace = a * a + b * b + c * c + d * d;
            final determinant = (a * d - b * c) * (a * d - b * c);
            final minimum =
                (trace -
                    math.sqrt(math.max(0, trace * trace - 4 * determinant))) /
                2;
            expect(
              2 * 180 / math.sqrt(minimum),
              lessThanOrEqualTo(320 * 2 / 3 + .01),
            );
          }
        }
        expect(nearest, lessThan(.025));
        expect(farthest, greaterThan(.75));
        expect(transmitted, greaterThan(.15));
        packed.write(
          shader,
          size: const Size(180, 320),
          time: 0,
          motion: 1,
          dim: .3,
          source: palette,
          target: palette,
        );
        final start = List<double>.of(packed.values);
        packed.write(
          shader,
          size: const Size(180, 320),
          time: fluidPhaseCycle,
          motion: 1,
          dim: .3,
          source: palette,
          target: palette,
        );
        for (var i = 0; i < start.length; i++) {
          if (i == 4 || i == 5) {
            expect(
              math.sin(packed.values[i]),
              closeTo(math.sin(start[i]), 1e-5),
            );
            expect(
              math.cos(packed.values[i]),
              closeTo(math.cos(start[i]), 1e-5),
            );
            continue;
          }
          expect(packed.values[i], closeTo(start[i], 1e-5));
        }
        final output = Platform.environment['MOTION414_PREVIEW_DIR'];
        if (output != null) {
          await tester.runAsync(() async {
            for (var frame = 0; frame < 6; frame++) {
              packed.write(
                shader,
                size: const Size(180, 320),
                time: frame * 9.0,
                motion: 1,
                dim: .3,
                source: palette,
                target: palette,
              );
              final recorder = ui.PictureRecorder();
              Canvas(recorder).drawRect(
                const Rect.fromLTWH(0, 0, 180, 320),
                Paint()..shader = shader,
              );
              final picture = recorder.endRecording();
              final image = await picture.toImage(180, 320);
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '$output/fluid-$frame.png',
              ).writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
              picture.dispose();
            }
          });
        }
      } finally {
        shader.dispose();
      }
    },
  );
  test('phone font limit is 50 and edits snap to integers', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.initializationFuture;
    expect(SettingsProvider.maxLyricFontSizeFor(const Size(390, 844)), 50);
    settings.previewFontSize(46.7);
    expect(settings.fontSize, 47);
    settings.dispose();
  });
  test('non-neutral artwork supplies eight distinct shared colours', () {
    for (final colors in [
      [
        const Color(0xff281230),
        const Color(0xff281230),
        const Color(0xff381c3c),
      ],
      [Colors.pink, Colors.teal, Colors.amber, Colors.white],
      [const Color(0xffa0b0b5), const Color(0xffb0b9c0)],
    ]) {
      final palette = buildFluidPalette(colors, fallbackSeed: Colors.blue);
      expect(palette.motionColors.toSet().length, greaterThanOrEqualTo(8));
      expect(palette.motionColors.length, 4 * fluidMotionColourCount);
      expect(
        palette.motionColors.every((c) => c.r >= 0 && c.g >= 0 && c.b >= 0),
        isTrue,
      );
    }
    expect(fluidPhaseCycle, greaterThan(math.pi));
  });
}
