import 'dart:math' as math;
import 'dart:ui';

typedef FluidLab = ({double l, double a, double b});

// Oklab, Björn Ottosson's public-domain/MIT reference matrices (2021-01-25).
// https://bottosson.github.io/posts/oklab/
// Palette preparation only; never transform every screen pixel to Oklab.
FluidLab fluidOklab(Color color) {
  double linear(double x) =>
      x <= .04045 ? x / 12.92 : math.pow((x + .055) / 1.055, 2.4).toDouble();
  final r = linear(color.r * color.a);
  final g = linear(color.g * color.a), b = linear(color.b * color.a);
  final l = math
      .pow(.4122214708 * r + .5363325363 * g + .0514459929 * b, 1 / 3)
      .toDouble();
  final m = math
      .pow(.2119034982 * r + .6806995451 * g + .1073969566 * b, 1 / 3)
      .toDouble();
  final s = math
      .pow(.0883024619 * r + .2817188376 * g + .6299787005 * b, 1 / 3)
      .toDouble();
  return (
    l: .2104542553 * l + .7936177850 * m - .0040720468 * s,
    a: 1.9779984951 * l - 2.4285922050 * m + .4505937099 * s,
    b: .0259040371 * l + .7827717662 * m - .8086757660 * s,
  );
}

double fluidLabDistanceSquared(FluidLab a, FluidLab b) {
  final dl = a.l - b.l, da = a.a - b.a, db = a.b - b.b;
  return dl * dl + da * da + db * db;
}

double fluidPerceptualDistance(Color a, Color b) =>
    math.sqrt(fluidLabDistanceSquared(fluidOklab(a), fluidOklab(b)));
