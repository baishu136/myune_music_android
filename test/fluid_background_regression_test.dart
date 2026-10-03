import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/services/artwork_palette_cache.dart';
import 'package:myune_music/services/fluid_background_controller.dart';
import 'package:myune_music/widgets/playback_background/fluid_background_painter.dart';

void main() {
  const pinkGreen = FluidPalette(
    Color(0xFFEE628B),
    Color(0xFF25BFA3),
    Color(0xFFFFBF54),
    Color(0xFF6B6F9B),
    baseColor: Color(0xFF200911),
    glowStrength: .92,
  );

  void activate(
    FluidBackgroundController controller, {
    bool visible = true,
    bool foreground = true,
    bool transition = false,
    FluidBackgroundQuality quality = FluidBackgroundQuality.smooth,
    double hz = 60,
  }) => controller.updateOperatingState(
    enabled: true,
    visible: visible,
    foreground: foreground,
    reduceMotion: false,
    routeTransitionActive: transition,
    quality: quality,
    displayRefreshRate: hz,
  );

  test('black and white covers never inherit colourful fallback accents', () {
    for (final samples in [
      const [
        FluidColorSample(Colors.black, .98),
        FluidColorSample(Colors.white, .02),
      ],
      const [FluidColorSample(Colors.black, 1)],
      const [FluidColorSample(Color(0xFF151515), 1)],
    ]) {
      final palette = buildWeightedFluidPalette(
        samples,
        fallbackSeed: Colors.pink,
      );
      for (final color in [...palette.colors, palette.baseColor]) {
        expect(HSLColor.fromColor(color).saturation, lessThan(.01));
      }
      expect(HSLColor.fromColor(palette.baseColor).lightness, lessThan(.04));
      expect(palette.glowStrength, lessThan(.35));
    }
  });

  test('dark blue edge light stays dark and vivid hues remain distinct', () {
    final dark = buildWeightedFluidPalette(const [
      FluidColorSample(Colors.black, .91),
      FluidColorSample(Color(0xFF102A3D), .09),
    ], fallbackSeed: Colors.orange);
    expect(dark.baseColor, Colors.black);
    expect(
      dark.colors.any((color) {
        final hsl = HSLColor.fromColor(color);
        return hsl.hue > 190 && hsl.hue < 240 && hsl.lightness < .20;
      }),
      isTrue,
    );
    expect(
      dark.colors.every((c) => HSLColor.fromColor(c).lightness < .20),
      isTrue,
    );
    final vivid = buildFluidPalette(
      pinkGreen.colors,
      fallbackSeed: Colors.blue,
    );
    expect(
      vivid.colors.where((c) => HSLColor.fromColor(c).saturation > .6).length,
      greaterThanOrEqualTo(3),
    );
    // Energy alone is not perceived brightness: diffuse vivid colours need
    // less energy than a faint dark-blue field to remain bright but readable.
    expect(
      vivid.colors
          .map((c) => HSLColor.fromColor(c).lightness)
          .reduce((a, b) => a + b),
      greaterThan(
        dark.colors
            .map((c) => HSLColor.fromColor(c).lightness)
            .reduce((a, b) => a + b),
      ),
    );
  });

  test('four slots retain pink and teal before sorting a six-colour cover', () {
    final palette = buildWeightedFluidPalette(const [
      FluidColorSample(Colors.black, .16),
      FluidColorSample(Color(0xFF0B9D93), .20),
      FluidColorSample(Color(0xFFEF2683), .20),
      FluidColorSample(Color(0xFFF09D2C), .15),
      FluidColorSample(Color(0xFFCC5845), .15),
      FluidColorSample(Color(0xFF58687B), .14),
    ], fallbackSeed: Colors.teal);
    final hues = palette.colors.map(HSLColor.fromColor).toList();
    expect(
      hues.any((c) => c.hue > 300 && c.hue < 350 && c.saturation > .5),
      isTrue,
      reason: '$hues',
    );
    expect(
      hues.any((c) => c.hue > 160 && c.hue < 200 && c.saturation > .5),
      isTrue,
      reason: '$hues',
    );
  });

  testWidgets('650ms blend and rapid retarget preserve the displayed colour', (
    tester,
  ) async {
    final controller = FluidBackgroundController(
      vsync: const TestVSync(),
      initialPalette: FluidPalette.fallback(Colors.blue),
    );
    addTearDown(controller.dispose);
    activate(controller);
    controller.setPalette(pinkGreen);
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.paletteProgress, inExclusiveRange(.2, .5));
    final displayed = controller.currentPalette;
    final expected = FluidPalette.lerp(
      controller.sourcePalette,
      controller.targetPalette,
      fluidPaletteBlend(controller.paletteProgress),
    );
    expect(displayed, expected);
    controller.setPalette(FluidPalette.fallback(Colors.orange));
    expect(controller.sourcePalette, displayed);
    expect(controller.currentPalette, displayed);
    for (var i = 0; i < 43; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.paletteProgress, 1);
    expect(controller.currentPalette, controller.targetPalette);
    activate(controller, visible: false);
    await tester.pump();
  });

  for (final hz in [60, 90, 120]) {
    testWidgets(
      'smooth scheduling follows $hz Hz without alternate-frame loss',
      (tester) async {
        final controller = FluidBackgroundController(
          vsync: const TestVSync(),
          initialPalette: pinkGreen,
        );
        addTearDown(controller.dispose);
        var paints = 0;
        controller.addListener(() => paints++);
        activate(controller, hz: hz.toDouble());
        for (var i = 0; i < hz; i++) {
          await tester.pump(Duration(microseconds: (1000000 / hz).round()));
        }
        expect(paints, greaterThan(hz - 5));
        final phase = controller.effectiveTime;
        final progress = controller.paletteProgress;
        activate(controller, foreground: false, hz: hz.toDouble());
        await tester.pump(const Duration(seconds: 3));
        expect(controller.isTicking, isFalse);
        expect(controller.effectiveTime, phase);
        expect(controller.paletteProgress, progress);
        activate(controller, hz: hz.toDouble());
        await tester.pump(const Duration(milliseconds: 16));
        expect((controller.effectiveTime - phase).abs(), lessThan(.03));
        activate(controller, transition: true);
        expect(controller.isTicking, isFalse);
        activate(controller, visible: false);
        expect(controller.isTicking, isFalse);
      },
    );
  }

  testWidgets(
    'bounded extraction deduplicates and cache invalidation rejects old completion',
    (tester) async {
      final cache = ArtworkPaletteCache(maximumEntries: 2);
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      await tester.runAsync(() async {
        final first = cache.resolve(
          key: 'pending',
          bytes: png,
          fallbackSeed: Colors.pink,
        );
        expect(
          cache.resolve(key: 'pending', bytes: png, fallbackSeed: Colors.pink),
          same(first),
        );
        cache.clear();
        await first;
        expect(cache.peek('pending'), isNull);
        final extracted = await cache.resolve(
          key: 'black',
          bytes: png,
          fallbackSeed: Colors.pink,
        );
        expect(
          extracted.colors.every((c) => HSLColor.fromColor(c).saturation < .01),
          isTrue,
        );
      });
      cache.remember('a', pinkGreen);
      cache.remember('b', pinkGreen);
      cache.remember('c', pinkGreen);
      expect(cache.length, 2);
      expect(cache.peek('a'), isNull);
    },
  );

  testWidgets('actual shader wraps continuously, moves widely and protects black', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/fluid_background.frag',
      );
      final shader = program.fragmentShader();
      addTearDown(shader.dispose);
      Future<Uint8List> render(FluidPalette palette, double phase) async {
        final recorder = ui.PictureRecorder();
        final controller = FluidBackgroundController(
          vsync: const TestVSync(),
          initialPalette: palette,
          initialEffectiveTime: phase,
        );
        // Enable a stable non-zero warp envelope, without relying on wall time.
        shader.setFloat(0, 96);
        shader.setFloat(1, 160);
        shader.setFloat(2, phase);
        shader.setFloat(3, 1);
        shader.setFloat(4, .3);
        shader.setFloat(5, 1);
        for (var i = 0; i < 4; i++) {
          for (final start in [6, 22]) {
            shader.setFloat(start + i * 4, palette[i].r);
            shader.setFloat(start + i * 4 + 1, palette[i].g);
            shader.setFloat(start + i * 4 + 2, palette[i].b);
            shader.setFloat(start + i * 4 + 3, 1);
          }
        }
        for (final start in [38, 42]) {
          shader.setFloat(start, palette.baseColor.r);
          shader.setFloat(start + 1, palette.baseColor.g);
          shader.setFloat(start + 2, palette.baseColor.b);
          shader.setFloat(start + 3, 1);
        }
        shader.setFloat(46, palette.glowStrength);
        shader.setFloat(47, palette.glowStrength);
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 96, 160),
          Paint()..shader = shader,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(96, 160);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        image.dispose();
        picture.dispose();
        controller.dispose();
        return bytes;
      }

      final initial = await render(pinkGreen, 0);
      // Same orbital displacement as before, now reached at the slower clock.
      final moved = await render(pinkGreen, 12 / fluidShaderTimeScale);
      final wrapped = await render(pinkGreen, fluidPhaseCycle);
      var changed = 0, wrapDiff = 0;
      for (var i = 0; i < initial.length; i += 4) {
        if ((initial[i] - moved[i]).abs() +
                (initial[i + 1] - moved[i + 1]).abs() +
                (initial[i + 2] - moved[i + 2]).abs() >
            12) {
          changed++;
        }
        wrapDiff += (initial[i] - wrapped[i]).abs();
      }
      expect(changed, greaterThan(96 * 160 * .35));
      expect(wrapDiff / (96 * 160), lessThan(1));
      final dark = buildWeightedFluidPalette(const [
        FluidColorSample(Colors.black, .98),
        FluidColorSample(Colors.white, .02),
      ], fallbackSeed: Colors.pink);
      final black = await render(dark, 6);
      var maxLuma = 0;
      for (var i = 0; i < black.length; i += 4) {
        maxLuma = black[i] > maxLuma ? black[i] : maxLuma;
        expect((black[i] - black[i + 1]).abs(), lessThanOrEqualTo(1));
        expect((black[i] - black[i + 2]).abs(), lessThanOrEqualTo(1));
      }
      expect(maxLuma, lessThan(45));
      // Painter uniform ordering, bounds and non-finite sizes are exercised too.
      final controller = FluidBackgroundController(
        vsync: const TestVSync(),
        initialPalette: dark,
      );
      final painter = FluidBackgroundPainter(
        shader: shader,
        controller: controller,
        dim: .3,
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(100, 180));
      painter.paint(canvas, const Size(100, 180));
      painter.paint(canvas, const Size(double.infinity, 180));
      recorder.endRecording().dispose();
      controller.dispose();
    });
  });
}
