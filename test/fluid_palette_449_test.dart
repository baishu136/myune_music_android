import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/services/artwork_palette_cache.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/models/fluid_color_perception.dart';
import 'package:myune_music/widgets/playback_background/fluid_frame_uniforms.dart';

void main() {
  test(
    'Oklab reference primaries and neutrals retain perceptual separation',
    () {
      final red = fluidOklab(const Color(0xFFFF0000));
      expect(red.l, closeTo(.62795536, 1e-7));
      expect(red.a, closeTo(.22486306, 1e-7));
      expect(red.b, closeTo(.12584630, 1e-7));
      for (final c in [Colors.black, Colors.white, const Color(0xFF808080)]) {
        final lab = fluidOklab(c);
        expect(lab.a.abs(), lessThan(1e-7));
        expect(lab.b.abs(), lessThan(1e-7));
        expect(fluidPerceptualDistance(c, c), 0);
      }
    },
  );

  test(
    'soft saturation gain is monotonic, preserves hue/lightness and neutral covers',
    () {
      for (final hue in [0.0, 35.0, 180.0, 265.0]) {
        var previous = -1.0;
        for (var i = 0; i <= 1000; i++) {
          final original = HSLColor.fromAHSL(1, hue, i / 1000, .4).toColor();
          final before = HSLColor.fromColor(original);
          final after = HSLColor.fromColor(fluidSaturationBoost(original));
          expect(after.saturation, greaterThanOrEqualTo(previous - .005));
          expect(
            after.saturation,
            greaterThanOrEqualTo(before.saturation - .003),
          );
          expect(after.lightness, closeTo(before.lightness, .003));
          if (i > 150) expect((after.hue - before.hue).abs(), lessThan(1));
          if (before.saturation < .70) {
            expect(after.saturation, closeTo(before.saturation * 1.21, .006));
          }
          previous = after.saturation;
        }
      }
      expect(fluidSaturationBoost(Colors.white), Colors.white);
      expect(fluidSaturationBoost(Colors.black), Colors.black);
    },
  );

  test(
    'dominant cover colour gets bounded influence through every field cycle',
    () {
      final palette = buildWeightedFluidPalette(const [
        FluidColorSample(Color(0xFF176EB0), .80),
        FluidColorSample(Color(0xFFC83392), .15),
        FluidColorSample(Color(0xFFE89A23), .05),
      ], fallbackSeed: Colors.green);
      var blue = 0.0, gold = 0.0, blues = 0, golds = 0;
      for (var field = 0; field < 4; field++) {
        for (var variant = 0; variant < 8; variant++) {
          final c = HSLColor.fromColor(palette.motionColor(field, variant));
          final weight = palette.motionWeight(field, variant);
          expect(weight, inInclusiveRange(.55, 1.65));
          if (c.hue > 190 && c.hue < 240) {
            blue += weight;
            blues++;
          }
          if (c.hue > 20 && c.hue < 55) {
            gold += weight;
            golds++;
          }
        }
      }
      expect(blues, greaterThan(0));
      expect(golds, greaterThan(0));
      expect(blue / blues, greaterThan(gold / golds * 1.25));
      for (var variant = 0; variant < 8; variant++) {
        expect(
          HSLColor.fromColor(palette.motionColor(0, variant)).hue,
          inInclusiveRange(190, 240),
        );
      }
      final neutral = buildFluidPalette([
        Colors.black,
        Colors.grey,
      ], fallbackSeed: Colors.pink);
      expect(neutral.mixProtection, 0);
    },
  );

  testWidgets(
    'snapshot/retarget preserve weights and protection without restarting travel',
    (tester) async {
      await tester.runAsync(() async {
        final shader = (await ui.FragmentProgram.fromAsset(
          'shaders/fluid_background.frag',
        )).fragmentShader();
        final a = buildWeightedFluidPalette(const [
          FluidColorSample(Colors.red, .8),
          FluidColorSample(Colors.cyan, .2),
        ], fallbackSeed: Colors.red);
        final b = buildFluidPalette([
          Colors.black,
          Colors.grey,
        ], fallbackSeed: Colors.red);
        final first = FluidFrameUniforms(), second = FluidFrameUniforms();
        try {
          for (final p in [.01, .3, .6, .99]) {
            final snapshot = FluidPalette.lerp(
              a,
              b,
              fluidPaletteBlend(p),
              transitionProgress: p,
            );
            first.write(
              shader,
              size: const Size(240, 400),
              time: 23,
              motion: 1,
              dim: .3,
              source: a,
              target: b,
              paletteProgress: p,
            );
            second.write(
              shader,
              size: const Size(240, 400),
              time: 23,
              motion: 1,
              dim: .3,
              source: snapshot,
              target: a,
              paletteProgress: 0,
            );
            expect(first.values.sublist(6, 14), second.values.sublist(6, 14));
            for (var i = 29; i < 45; i++) {
              expect(first.values[i], closeTo(second.values[i], 3e-6));
            }
            for (var i = 45; i < 49; i++) {
              expect(first.values[i], closeTo(second.values[i], 1e-6));
            }
            for (var i = 49; i < 53; i++) {
              expect(first.values[i], closeTo(second.values[i], 1 / 255));
            }
            expect(FluidPalette.lerp(a, b, 1), same(b));
          }
        } finally {
          shader.dispose();
        }
      });
    },
  );

  test(
    'the eight-colour cycle is shorter than a random ordering, including its closing edge',
    () {
      final palette = buildWeightedFluidPalette(const [
        FluidColorSample(Color(0xFFC92852), .35),
        FluidColorSample(Color(0xFF259D91), .30),
        FluidColorSample(Color(0xFFE0A235), .20),
        FluidColorSample(Color(0xFF65469E), .15),
      ], fallbackSeed: Colors.blue);
      final colors = List.generate(8, (i) => palette.motionColor(0, i));
      var tour = 0.0, pairs = 0.0;
      for (var i = 0; i < 8; i++) {
        tour += fluidPerceptualDistance(colors[i], colors[(i + 1) % 8]);
        for (var j = 0; j < i; j++) {
          pairs += fluidPerceptualDistance(colors[i], colors[j]);
        }
      }
      expect(tour, lessThan(pairs * 8 / 28 * .9));
    },
  );

  testWidgets(
    'actual shader reduces deep cancellation without tinting neutral pixels',
    (tester) async {
      await tester.runAsync(() async {
        final shader = (await ui.FragmentProgram.fromAsset(
          'shaders/fluid_background.frag',
        )).fragmentShader();
        Future<List<int>> render(
          bool protect,
          bool neutral, {
          bool weighted = false,
        }) async {
          final pigmentA = neutral ? Colors.white : const Color(0xFFFF0000);
          final pigmentB = neutral ? Colors.black : const Color(0xFF00FFFF);
          final palette = FluidPalette(
            pigmentA,
            pigmentB,
            pigmentA,
            pigmentB,
            baseColor: Colors.black,
            mixAnchor: const Color(0xFFFFAA00),
            mixProtection: protect ? .2 : 0,
            motionColors: List.generate(
              32,
              (i) => (i ~/ 8).isEven ? pigmentA : pigmentB,
            ),
            motionWeights: weighted
                ? List.generate(32, (i) => (i ~/ 8).isEven ? 1.6 : .6)
                : const [],
          );
          final packed = FluidFrameUniforms();
          packed.write(
            shader,
            size: const Size(96, 160),
            time: 0,
            motion: 0,
            dim: 0,
            source: palette,
            target: palette,
          );
          for (var field = 0; field < 4; field++) {
            shader.setFloat(6 + field * 2, .5);
            shader.setFloat(7 + field * 2, .5);
            shader.setFloat(29 + field * 4, 2);
            shader.setFloat(30 + field * 4, 0);
            shader.setFloat(31 + field * 4, 0);
            shader.setFloat(32 + field * 4, 2);
          }
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawRect(
            const Rect.fromLTWH(0, 0, 96, 160),
            Paint()..shader = shader,
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(96, 160);
          try {
            return (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
          } finally {
            image.dispose();
            picture.dispose();
          }
        }

        try {
          final original = await render(false, false),
              improved = await render(true, false);
          final grey = await render(false, true),
              protectedGrey = await render(true, true);
          final weighted = await render(false, false, weighted: true);
          const centre = (80 * 96 + 48) * 4;
          expect(
            weighted[centre] / (weighted[centre] + weighted[centre + 1]),
            closeTo(1.6 / 2.2, .008),
          );
          var oldChroma = 0.0, newChroma = 0.0, brightnessDifference = 0.0;
          for (var i = 0; i < original.length; i += 4) {
            double chroma(List<int> p) =>
                (math.max(p[i], math.max(p[i + 1], p[i + 2])) -
                    math.min(p[i], math.min(p[i + 1], p[i + 2]))) /
                255;
            oldChroma += chroma(original);
            newChroma += chroma(improved);
            brightnessDifference +=
                ((.2126 * original[i] +
                            .7152 * original[i + 1] +
                            .0722 * original[i + 2]) -
                        (.2126 * improved[i] +
                            .7152 * improved[i + 1] +
                            .0722 * improved[i + 2]))
                    .abs() /
                255;
            expect(improved[i + 3], 255);
          }
          expect(oldChroma, 0);
          expect(newChroma / (96 * 160), greaterThan(.12));
          expect(brightnessDifference / (96 * 160), lessThan(1.1 / 255));
          expect(protectedGrey, orderedEquals(grey));
        } finally {
          shader.dispose();
        }
      });
    },
  );

  testWidgets('a small purple gradient survives a many-bin green cover', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      for (var y = 0; y < 62; y++) {
        canvas.drawRect(
          Rect.fromLTWH(0, y.toDouble(), 64, 1),
          Paint()
            ..color = Color.fromARGB(
              255,
              16 + (y % 4) * 16,
              112 + (y ~/ 4 % 8) * 16,
              16 + (y ~/ 32) * 32,
            ),
        );
      }
      for (var x = 0; x < 64; x++) {
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), 62, 1, 2),
          Paint()..color = Color.fromARGB(255, 96 + (x ~/ 4) * 8, 24, 208),
        );
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(64, 64);
      try {
        final png = (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        final palette = await ArtworkPaletteCache().resolve(
          key: 'purple449',
          bytes: png,
          fallbackSeed: Colors.green,
        );
        debugPrint(
          '449 sampled hues: ${palette.motionColors.map((c) => HSLColor.fromColor(c).hue.toStringAsFixed(1)).toSet()}',
        );
        expect(
          palette.motionColors.any((c) {
            final hsl = HSLColor.fromColor(c);
            return hsl.hue >= 260 && hsl.hue <= 325 && hsl.saturation > .3;
          }),
          isTrue,
        );
      } finally {
        image.dispose();
        picture.dispose();
      }
    });
  });
}
