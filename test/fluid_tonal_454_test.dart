import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/services/artwork_palette_cache.dart';

double gap(Color a, Color b) {
  final d = (HSLColor.fromColor(a).hue - HSLColor.fromColor(b).hue).abs();
  return d > 180 ? 360 - d : d;
}

void main() {
  test(
    'tone selection merges shades, pools their area and rejects tiny specks',
    () {
      final colors = selectFluidTonalSamples(const [
        FluidColorSample(Color(0xFF245B9E), .30),
        FluidColorSample(Color(0xFF194272), .25),
        FluidColorSample(Color(0xFF376CAE), .20),
        FluidColorSample(Color(0xFFAC3981), .24),
        FluidColorSample(Color(0xFFF4BA22), .01),
      ]);
      expect(colors, hasLength(2));
      expect(colors.first.proportion, closeTo(.75, 1e-9));
      expect(gap(colors.first.color, const Color(0xFF245B9E)), lessThan(10));
      expect(gap(colors.last.color, const Color(0xFFAC3981)), lessThan(3));
      final reversed = selectFluidTonalSamples(const [
        FluidColorSample(Color(0xFFF4BA22), .01),
        FluidColorSample(Color(0xFFAC3981), .24),
        FluidColorSample(Color(0xFF376CAE), .20),
        FluidColorSample(Color(0xFF194272), .25),
        FluidColorSample(Color(0xFF245B9E), .30),
      ]);
      expect(reversed.map((s) => s.color), colors.map((s) => s.color));
    },
  );

  test(
    'two to five observed tones survive, extra families are bounded to five',
    () {
      for (var count = 2; count <= 8; count++) {
        final input = List.generate(
          count,
          (i) => FluidColorSample(
            HSLColor.fromAHSL(1, i * 360 / count, .65, .4).toColor(),
            1 / count,
          ),
        );
        final result = selectFluidTonalSamples(input);
        expect(result.length, count.clamp(2, 5));
        expect(
          result.every((s) => input.any((i) => i.color == s.color)),
          isTrue,
        );
      }
    },
  );

  test(
    'red wraparound is one tone; monochrome depth never imports seed hues',
    () {
      final red = selectFluidTonalSamples([
        FluidColorSample(const HSLColor.fromAHSL(1, 359, .7, .4).toColor(), .6),
        FluidColorSample(const HSLColor.fromAHSL(1, 1, .7, .3).toColor(), .4),
      ]);
      expect(red, hasLength(2));
      expect(gap(red[0].color, red[1].color), lessThan(3));
      for (final color in [
        Colors.black,
        const Color(0xFF777777),
        const Color(0xFF426369),
      ]) {
        final result = selectFluidTonalSamples([FluidColorSample(color, 1)]);
        expect(result, hasLength(2));
        for (final s in result) {
          expect(gap(s.color, color), lessThan(2));
          expect(
            HSLColor.fromColor(s.color).lightness,
            lessThanOrEqualTo(HSLColor.fromColor(color).lightness),
          );
        }
      }
    },
  );

  test(
    'production palette excludes rejected specks throughout its colour cycle',
    () {
      final palette = buildWeightedFluidPalette(const [
        FluidColorSample(Color(0xFF245B9E), .75),
        FluidColorSample(Color(0xFFAC3981), .24),
        FluidColorSample(Color(0xFFF4BA22), .01),
      ], fallbackSeed: Colors.green);
      for (final c in [...palette.colors, ...palette.motionColors]) {
        final hsl = HSLColor.fromColor(c);
        expect(hsl.saturation < .10 || hsl.hue > 180, isTrue);
      }
    },
  );
}
