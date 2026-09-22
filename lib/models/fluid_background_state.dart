import 'dart:math' as math;

import 'package:flutter/material.dart';

enum PlaybackArtworkBackgroundStyle { blurred, fluid }

enum FluidBackgroundQuality { automatic, powerSaving, smooth }

// Every shader frequency is expressed in hundredths of the phase. Wrapping at
// 200π therefore returns every sine/cosine term to the same value. The former
// 2π wrap reset non-integer harmonics mid-wave and produced a periodic flash.
const fluidPhaseCycle = math.pi * 200;

double wrapFluidPhase(double phase) => phase % fluidPhaseCycle;

@immutable
class FluidPalette {
  const FluidPalette(this.first, this.second, this.third, this.fourth);

  final Color first;
  final Color second;
  final Color third;
  final Color fourth;

  List<Color> get colors => <Color>[first, second, third, fourth];

  Color operator [](int index) => switch (index) {
    0 => first,
    1 => second,
    2 => third,
    _ => fourth,
  };

  static FluidPalette fallback(Color seed) {
    final hsl = HSLColor.fromColor(seed);
    final neutralSeed = hsl.saturation < .08;
    Color shade(double hueOffset, double saturation, double lightness) {
      return hsl
          .withHue((hsl.hue + hueOffset) % 360)
          .withSaturation(
            neutralSeed
                ? saturation.clamp(.02, .12)
                : saturation.clamp(.18, .72),
          )
          .withLightness(lightness.clamp(.12, .62))
          .toColor();
    }

    return FluidPalette(
      shade(-18, math.max(hsl.saturation, .38), .28),
      shade(24, math.max(hsl.saturation * .9, .30), .40),
      shade(72, math.max(hsl.saturation * .72, .24), .24),
      shade(-58, math.max(hsl.saturation * .8, .28), .34),
    );
  }

  static FluidPalette lerp(
    FluidPalette source,
    FluidPalette target,
    double value,
  ) {
    final t = value.clamp(0.0, 1.0);
    return FluidPalette(
      Color.lerp(source.first, target.first, t)!,
      Color.lerp(source.second, target.second, t)!,
      Color.lerp(source.third, target.third, t)!,
      Color.lerp(source.fourth, target.fourth, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FluidPalette &&
          first == other.first &&
          second == other.second &&
          third == other.third &&
          fourth == other.fourth;

  @override
  int get hashCode => Object.hash(first, second, third, fourth);
}

/// Matches a new artwork palette to the current colour slots. This avoids a
/// red field unnecessarily morphing through green merely because colorgram
/// returned the next cover's colours in a different order.
FluidPalette alignFluidPaletteSlots(
  FluidPalette current,
  FluidPalette incoming,
) {
  final source = current.colors;
  final target = incoming.colors;
  List<Color>? best;
  var bestDistance = double.infinity;

  void visit(List<Color> remaining, List<Color> ordered) {
    if (remaining.isEmpty) {
      var distance = 0.0;
      for (var index = 0; index < 4; index++) {
        final first = HSLColor.fromColor(source[index]);
        final second = HSLColor.fromColor(ordered[index]);
        final rawHue = (first.hue - second.hue).abs();
        final hue = (rawHue > 180 ? 360 - rawHue : rawHue) / 180;
        distance +=
            hue * (.2 + .8 * (first.saturation + second.saturation) / 2) * .55 +
            (first.saturation - second.saturation).abs() * .25 +
            (first.lightness - second.lightness).abs() * .20;
      }
      if (distance < bestDistance) {
        bestDistance = distance;
        best = List<Color>.of(ordered);
      }
      return;
    }
    for (var index = 0; index < remaining.length; index++) {
      visit(
        <Color>[...remaining.take(index), ...remaining.skip(index + 1)],
        <Color>[...ordered, remaining[index]],
      );
    }
  }

  visit(target, const <Color>[]);
  final colors = best!;
  return FluidPalette(colors[0], colors[1], colors[2], colors[3]);
}

@immutable
class FluidBackgroundConfig {
  const FluidBackgroundConfig({
    required this.framesPerSecond,
    required this.motionPeriodSeconds,
  });

  final int framesPerSecond;
  final double motionPeriodSeconds;

  static FluidBackgroundConfig forQuality(FluidBackgroundQuality quality) {
    return switch (quality) {
      FluidBackgroundQuality.powerSaving => const FluidBackgroundConfig(
        framesPerSecond: 24,
        motionPeriodSeconds: 6.5,
      ),
      FluidBackgroundQuality.smooth => const FluidBackgroundConfig(
        framesPerSecond: 60,
        motionPeriodSeconds: 4.625,
      ),
      FluidBackgroundQuality.automatic => const FluidBackgroundConfig(
        framesPerSecond: 30,
        motionPeriodSeconds: 5.5,
      ),
    };
  }
}
