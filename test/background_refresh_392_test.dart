import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/services/artwork_palette_cache.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/services/fluid_background_controller.dart';
import 'package:myune_music/widgets/playback_background/fluid_colour_motion.dart';
import 'package:myune_music/widgets/playback_background/fluid_frame_uniforms.dart';
import 'package:myune_music/widgets/playback_background/fluid_background.dart';
import 'package:myune_music/widgets/playback_background/fluid_background_painter.dart';
import 'package:myune_music/services/interaction_performance_controller.dart';

void main() {
  testWidgets(
    'an uncached next cover retains the displayed palette while preparation waits',
    (tester) async {
      Future<Uint8List> png(Color c) async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(c, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(64, 64);
        try {
          return (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
        } finally {
          image.dispose();
          picture.dispose();
        }
      }

      final blue = (await tester.runAsync(() => png(Colors.blue)))!;
      final red = (await tester.runAsync(() => png(Colors.red)))!;
      await tester.runAsync(
        () => FluidPlaybackBackground.prewarm(
          bytes: blue,
          identity: 'old-blue-392',
          cacheGeneration: 0,
          fallbackSeed: Colors.purple,
        ),
      );
      Widget host(String id, Uint8List bytes) => MaterialApp(
        home: FluidPlaybackBackground(
          artworkBytes: bytes,
          artworkIdentity: id,
          artworkCacheGeneration: 0,
          fallbackSeed: Colors.purple,
          dim: .3,
          quality: FluidBackgroundQuality.automatic,
          routeTransitionActive: false,
          child: const SizedBox(),
        ),
      );
      await tester.pumpWidget(host('old-blue-392', blue));
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('fluid-background-shader')),
                  )
                  .painter!
              as FluidBackgroundPainter;
      final previous = painter.controller.currentPalette;
      final guard = InteractionPerformanceController.instance.beginTransition();
      try {
        await tester.pumpWidget(host('uncached-red-392', red));
        await tester.pump(const Duration(milliseconds: 120));
        expect(painter.controller.targetPalette, previous);
        expect(painter.controller.currentPalette, previous);
      } finally {
        await tester.pumpWidget(const SizedBox());
        guard.release();
        await tester.pump(const Duration(milliseconds: 50));
      }
    },
  );

  test('bright muted artwork retains its large neutral area', () {
    final palette = buildWeightedFluidPalette(const [
      FluidColorSample(Color(0xff929496), .88),
      FluidColorSample(Color(0xfff02947), .12),
    ], fallbackSeed: Colors.blue);
    expect(HSLColor.fromColor(palette.baseColor).saturation, lessThan(.1));
    expect(
      palette.motionColors
          .take(8)
          .where((c) => HSLColor.fromColor(c).saturation < .1)
          .length,
      greaterThanOrEqualTo(2),
    );
  });

  testWidgets(
    'a white cover with black printing is classified before white removal',
    (tester) async {
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 64, 10),
          Paint()..color = Colors.black,
        );
        canvas.drawRect(
          const Rect.fromLTWH(0, 10, 64, 10),
          Paint()..color = const Color(0xff55bbe5),
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(64, 64);
        final png = (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        image.dispose();
        picture.dispose();
        final palette = await ArtworkPaletteCache().resolve(
          key: 'bright-black-print',
          bytes: png,
          fallbackSeed: Colors.purple,
        );
        expect(
          palette.motionColors.every(
            (c) => HSLColor.fromColor(c).lightness >= .20,
          ),
          isTrue,
        );
        expect(
          HSLColor.fromColor(palette.baseColor).lightness,
          greaterThan(.20),
        );
      });
    },
  );

  testWidgets(
    'real running controller retargets rendered colours without a jump',
    (tester) async {
      final program = await tester.runAsync(
        () => ui.FragmentProgram.fromAsset('shaders/fluid_background.frag'),
      );
      final shader = program!.fragmentShader();
      final packed = FluidFrameUniforms();
      final dark = buildFluidPalette(const [
        Color(0xff102030),
        Color(0xff221a44),
      ], fallbackSeed: Colors.blue);
      final bright = buildWeightedFluidPalette(const [
        FluidColorSample(Colors.white, .6),
        FluidColorSample(Color(0xffaaddcc), .25),
        FluidColorSample(Color(0xffeeaa99), .15),
      ], fallbackSeed: Colors.pink);
      final controller = FluidBackgroundController(
        vsync: const TestVSync(),
        initialPalette: dark,
        initialEffectiveTime: 17,
      );
      controller.updateOperatingState(
        enabled: true,
        visible: true,
        foreground: true,
        reduceMotion: false,
        routeTransitionActive: false,
        quality: FluidBackgroundQuality.smooth,
      );
      void paint() => packed.write(
        shader,
        size: const Size(180, 320),
        time: controller.effectiveTime,
        motion: 1,
        dim: .3,
        source: controller.sourcePalette,
        target: controller.targetPalette,
        paletteProgress: controller.paletteProgress,
        stagedFields: controller.stagedFields,
      );
      try {
        controller.setPalette(bright);
        for (final target in [dark, bright, dark, bright]) {
          for (var frame = 0; frame < 17; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          paint();
          final before = Float32List.fromList(packed.values);
          final time = controller.effectiveTime;
          controller.setPalette(target);
          expect(controller.effectiveTime, time);
          paint();
          for (var i = 14; i < 29; i++) {
            expect(
              packed.values[i],
              closeTo(before[i], .000001),
              reason: 'rendered retarget $i',
            );
          }
          for (var field = 0; field < 4; field++) {
            expect(
              controller.stagedFields[field],
              fluidNeedsIntermediateColour(
                fluidFieldColourAtTime(controller.sourcePalette, time, field),
                fluidFieldColourAtTime(controller.targetPalette, time, field),
              ),
            );
          }
        }
      } finally {
        controller.dispose();
        shader.dispose();
      }
    },
  );

  test('eight cover colours are shared by four offset colour journeys', () {
    final palette = buildWeightedFluidPalette(const [
      FluidColorSample(Color(0xffee387d), .30),
      FluidColorSample(Color(0xff23bba2), .25),
      FluidColorSample(Color(0xffeeb12a), .15),
      FluidColorSample(Color(0xff525ea3), .10),
      FluidColorSample(Color(0xffb457cf), .10),
      FluidColorSample(Color(0xffe55733), .10),
    ], fallbackSeed: Colors.blue);
    expect(palette.motionColors, hasLength(32));
    final pool = palette.motionColors.take(8).toSet();
    expect(pool.length, inInclusiveRange(6, 8));
    for (var field = 0; field < 4; field++) {
      expect(palette.motionColors.skip(field * 8).take(8).toSet(), pool);
    }
  });

  test('colour speed doubles with coordinated smooth ramps', () {
    for (var step = 0; step < 200; step++) {
      final orbit = step * math.pi / 40;
      var total = 0.0;
      for (var field = 0; field < 4; field++) {
        final rate = fluidColourRate(orbit, field);
        expect(rate, greaterThan(0));
        final measured =
            (fluidColourPhase(orbit + .00001, field) -
                fluidColourPhase(orbit - .00001, field)) /
            .00002;
        expect(measured, closeTo(rate, .000001));
        total += rate;
      }
      expect(total, closeTo(8, .000001));
    }
  });

  test(
    'large opposite brightness uses a middle colour; same brightness skips it',
    () {
      expect(
        fluidNeedsIntermediateColour(
          const Color(0xff102030),
          const Color(0xffaaddcc),
        ),
        isTrue,
      );
      expect(
        fluidNeedsIntermediateColour(
          const Color(0xff102030),
          const Color(0xff302010),
        ),
        isFalse,
      );
      expect(
        fluidNeedsIntermediateColour(
          const Color(0xffddaa99),
          const Color(0xff99aadd),
        ),
        isFalse,
      );
      expect(
        fluidNeedsIntermediateColour(
          const Color(0xff445566),
          const Color(0xff465768),
        ),
        isFalse,
      );
      expect(fluidColourTransitionBlend(.25, true), closeTo(.25, .000001));
      expect(fluidColourTransitionBlend(.5, true), .5);
      expect(fluidColourTransitionBlend(.75, true), closeTo(.75, .000001));
      for (final p in [0.0, .5, 1.0]) {
        final before = fluidColourTransitionBlend(
          (p - .00001).clamp(0.0, 1.0),
          true,
        );
        final after = fluidColourTransitionBlend(
          (p + .00001).clamp(0.0, 1.0),
          true,
        );
        expect(after - before, lessThan(.000001));
      }
    },
  );

  testWidgets(
    'bounded shape, shared cycle and interrupted colour transition remain continuous',
    (tester) async {
      await tester.runAsync(() async {
        final shader = (await ui.FragmentProgram.fromAsset(
          'shaders/fluid_background.frag',
        )).fragmentShader();
        final packed = FluidFrameUniforms();
        final dark = buildFluidPalette(const [
          Color(0xff101a22),
          Color(0xff243044),
        ], fallbackSeed: Colors.blue);
        final bright = buildWeightedFluidPalette(const [
          FluidColorSample(Colors.white, .6),
          FluidColorSample(Color(0xff77ddbb), .3),
          FluidColorSample(Color(0xffee6699), .1),
        ], fallbackSeed: Colors.pink);
        final controller = FluidBackgroundController(
          vsync: const TestVSync(),
          initialPalette: dark,
        );
        try {
          for (final size in [
            const Size(360, 800),
            const Size(400, 600),
            const Size(600, 600),
            const Size(800, 360),
          ]) {
            for (var step = 0; step < 1000; step++) {
              packed.write(
                shader,
                size: size,
                time: fluidPhaseCycle * step / 1000,
                motion: 1,
                dim: .3,
                source: bright,
                target: bright,
              );
              for (var field = 0; field < 4; field++) {
                final s = 29 + field * 4;
                final radiusX =
                    1 /
                    math.sqrt(
                      math.pow(packed.values[s], 2) +
                          math.pow(packed.values[s + 1], 2),
                    );
                final radiusY =
                    1 /
                    math.sqrt(
                      math.pow(packed.values[s + 2], 2) +
                          math.pow(packed.values[s + 3], 2),
                    );
                expect(
                  2 * math.max(radiusX, radiusY) * size.shortestSide,
                  lessThanOrEqualTo(size.longestSide * 2 / 3 + .0001),
                );
              }
            }
          }
          void write(
            FluidPalette source,
            FluidPalette target,
            double progress, {
            double time = 17,
          }) => packed.write(
            shader,
            size: const Size(180, 320),
            time: time,
            motion: 1,
            dim: .3,
            source: source,
            target: target,
            paletteProgress: progress,
          );
          write(bright, bright, 1, time: 0);
          final start = Float32List.fromList(packed.values);
          write(bright, bright, 1, time: fluidPhaseCycle);
          for (var i = 6; i < packed.values.length; i++) {
            expect(
              packed.values[i],
              closeTo(start[i], .00001),
              reason: 'cycle value $i',
            );
          }
          controller.setPalette(bright);
          for (final progress in [.12, .25, .49, .51, .76]) {
            final snapshot = FluidPalette.lerp(
              dark,
              bright,
              fluidPaletteBlend(progress),
              transitionProgress: progress,
            );
            write(dark, bright, progress);
            final before = Float32List.fromList(packed.values);
            write(snapshot, dark, 0);
            for (var i = 14; i < 29; i++) {
              expect(
                packed.values[i],
                closeTo(before[i], .000001),
                reason: 'retarget $progress/$i',
              );
            }
          }
        } finally {
          shader.dispose();
          controller.dispose();
        }
      });
    },
  );

  test('bright artwork does not give black printing a dark pigment field', () {
    final palette = buildWeightedFluidPalette(const [
      FluidColorSample(Colors.white, .65),
      FluidColorSample(Color(0xff55bbe5), .20),
      FluidColorSample(Colors.black, .10),
      FluidColorSample(Color(0xff555555), .05),
    ], fallbackSeed: Colors.purple);
    expect(palette.colors, isNot(contains(Colors.black)));
    expect(
      palette.colors.every((c) => HSLColor.fromColor(c).lightness >= .20),
      isTrue,
    );
    expect(HSLColor.fromColor(palette.baseColor).lightness, greaterThan(.15));
  });
}
