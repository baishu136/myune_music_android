import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/services/artwork_palette_cache.dart';

double hueDistance(Color a, Color b) {
  final delta = (HSLColor.fromColor(a).hue - HSLColor.fromColor(b).hue).abs();
  return delta > 180 ? 360 - delta : delta;
}

void main() {
  test('muted but colourful cover retains pigment saturation and lead hue', () {
    final dominant = const HSLColor.fromAHSL(1, 200, .48, .44).toColor();
    final other = const HSLColor.fromAHSL(1, 225, .62, .42).toColor();
    final palette = buildWeightedFluidPalette([
      FluidColorSample(dominant, .70),
      FluidColorSample(other, .30),
    ], fallbackSeed: Colors.pink);
    expect(hueDistance(palette.second, dominant), lessThan(2));
    expect(HSLColor.fromColor(palette.second).saturation, closeTo(.48, .05));
  });

  test(
    'a tiny complementary speck cannot displace a substantial cover family',
    () {
      const blue = Color(0xFF25649E);
      const indigo = Color(0xFF4B468E);
      const speck = Color(0xFFF09D2C);
      final palette = buildWeightedFluidPalette(const [
        FluidColorSample(blue, .70),
        FluidColorSample(indigo, .285),
        FluidColorSample(speck, .015),
      ], fallbackSeed: Colors.red);
      expect(hueDistance(palette.fourth, blue), lessThan(80));
    },
  );
}
