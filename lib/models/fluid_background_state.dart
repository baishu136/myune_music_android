import 'dart:math' as math;

import 'package:flutter/material.dart';

enum PlaybackArtworkBackgroundStyle { blurred, fluid }

enum FluidBackgroundQuality { automatic, powerSaving, smooth }

// uTime is wall-clock seconds; the shader alone converts to orbital radians.
// Every temporal harmonic is an integer, so all masks/warps wrap together.
const fluidShaderTimeScale = .065;
const fluidPhaseCycle = math.pi * 2 / fluidShaderTimeScale; // 96.66 seconds

double wrapFluidPhase(double phase) => phase % fluidPhaseCycle;

/// Exactly the same envelope as the shader: also used when retargeting midway.
double fluidPaletteBlend(double progress) {
  final p = progress.clamp(0.0, 1.0);
  return p * p * p * (p * (p * 6 - 15) + 10);
}

@immutable
class FluidPalette {
  const FluidPalette(
    this.first,
    this.second,
    this.third,
    this.fourth, {
    this.baseColor = const Color(0xFF080A0E),
    this.glowStrength = .72,
    this.warmAccentLocked = false,
    this.vividAccentLocked = false,
    this.layeredRolesLocked = false,
  });

  final Color first;
  final Color second;
  final Color third;
  final Color fourth;
  // Base and ambient energy are artwork properties, not per-frame analysis.
  final Color baseColor;
  final double glowStrength;
  // A significant real artwork accent owns c2's ambient tint. Slot
  // matching may reorder the other fields, but must not evict this colour.
  final bool warmAccentLocked;
  // Actual vivid lead owns slot 1; never relabel a grey as the lead.
  final bool vividAccentLocked;
  // Layer roles: baseColor=canvas, second=blob1, fourth=blob2, third=ambient.
  // first remains extraction metadata for existing callers, not a fourth light.
  // Extraction locks roles so closest-colour matching cannot swap a blob with
  // an ambient accent. Colour interpolation itself remains continuous.
  final bool layeredRolesLocked;

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
      baseColor: Color.lerp(source.baseColor, target.baseColor, t)!,
      glowStrength:
          source.glowStrength + (target.glowStrength - source.glowStrength) * t,
      warmAccentLocked: t == 0
          ? source.warmAccentLocked
          : target.warmAccentLocked,
      vividAccentLocked: t == 0
          ? source.vividAccentLocked
          : target.vividAccentLocked,
      layeredRolesLocked: t == 0
          ? source.layeredRolesLocked
          : target.layeredRolesLocked,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FluidPalette &&
          first == other.first &&
          second == other.second &&
          third == other.third &&
          fourth == other.fourth &&
          baseColor == other.baseColor &&
          glowStrength == other.glowStrength &&
          warmAccentLocked == other.warmAccentLocked &&
          vividAccentLocked == other.vividAccentLocked &&
          layeredRolesLocked == other.layeredRolesLocked;

  @override
  int get hashCode => Object.hash(
    first,
    second,
    third,
    fourth,
    baseColor,
    glowStrength,
    warmAccentLocked,
    vividAccentLocked,
    layeredRolesLocked,
  );
}

/// Matches a new artwork palette to the current colour slots. This avoids a
/// red field unnecessarily morphing through green merely because colorgram
/// returned the next cover's colours in a different order.
FluidPalette alignFluidPaletteSlots(
  FluidPalette current,
  FluidPalette incoming,
) {
  if (incoming.layeredRolesLocked) return incoming;
  final source = current.colors;
  final target = incoming.colors;
  List<Color>? best;
  var bestDistance = double.infinity;

  void visit(List<Color> remaining, List<Color> ordered) {
    if (remaining.isEmpty) {
      if (incoming.warmAccentLocked && ordered[2] != incoming.third) return;
      if (incoming.vividAccentLocked && ordered[1] != incoming.second) return;
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
  return FluidPalette(
    colors[0],
    colors[1],
    colors[2],
    colors[3],
    baseColor: incoming.baseColor,
    glowStrength: incoming.glowStrength,
    warmAccentLocked: incoming.warmAccentLocked,
    vividAccentLocked: incoming.vividAccentLocked,
    layeredRolesLocked: incoming.layeredRolesLocked,
  );
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
        motionPeriodSeconds: fluidPhaseCycle,
      ),
      FluidBackgroundQuality.smooth => const FluidBackgroundConfig(
        framesPerSecond: 120,
        motionPeriodSeconds: fluidPhaseCycle,
      ),
      FluidBackgroundQuality.automatic => const FluidBackgroundConfig(
        framesPerSecond: 60,
        motionPeriodSeconds: fluidPhaseCycle,
      ),
    };
  }
}
