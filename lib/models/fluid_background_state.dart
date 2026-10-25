import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

enum PlaybackArtworkBackgroundStyle { blurred, fluid }

enum FluidBackgroundQuality { automatic, powerSaving, smooth }

// Visible wall-clock seconds; frame uniforms convert to orbital radians.
// Orbit, doubled colour and 1.6x shape clocks share a five-orbit wrap.
const fluidShaderTimeScale = .15;
const fluidOrbitPeriod = math.pi * 2 / fluidShaderTimeScale;
// Five orbits keep the 1.6x shape clock continuous when visible time wraps.
const fluidPhaseCycle = fluidOrbitPeriod * 5;
const fluidMotionColourCount = 8;

/// Apply once to generated palettes, never to interpolation or cached frames.
/// Relative saturation only; preserve hue/lightness and neutral artwork.
Color fluidSaturationBoost(Color colour) {
  final hsl = HSLColor.fromColor(colour);
  if (hsl.saturation == 0) return colour;
  return hsl.withSaturation((hsl.saturation * 1.10).clamp(0.0, 1.0)).toColor();
}

bool fluidNeedsIntermediateColour(Color a, Color b) {
  double brightness(Color c) =>
      .30 * c.r * c.a + .40 * c.g * c.a + .30 * c.b * c.a;
  final x = brightness(a), y = brightness(b);
  final opposite = (x < .36 && y > .52) || (y < .36 && x > .52);
  final distance = math.sqrt(
    .30 * math.pow(a.r * a.a - b.r * b.a, 2) +
        .40 * math.pow(a.g * a.a - b.g * b.a, 2) +
        .30 * math.pow(a.b * a.a - b.b * b.a, 2),
  );
  return opposite && distance > .28;
}

double fluidColourTransitionBlend(double progress, bool throughMiddle) {
  if (!throughMiddle) return fluidPaletteBlend(progress);
  final p = progress.clamp(0.0, 1.0);
  return p < .5
      ? .5 * fluidPaletteBlend(p * 2)
      : .5 + .5 * fluidPaletteBlend((p - .5) * 2);
}

double wrapFluidPhase(double phase) => phase % fluidPhaseCycle;

/// Exactly the same envelope as the shader: also used when retargeting midway.
double fluidPaletteBlend(double progress) {
  final p = progress.clamp(0.0, 1.0);
  return p * p * p * (p * (p * 6 - 15) + 10);
}

class BackgroundColorBlendCurve extends Curve {
  const BackgroundColorBlendCurve();
  @override
  double transformInternal(double t) => fluidPaletteBlend(t);
}

/// Bound the perceived rate for wide colour changes; calculated once per song.
Duration fluidPaletteTransitionDuration(
  FluidPalette source,
  FluidPalette target,
) {
  var squared = 0.0;
  for (var i = 0; i < 5; i++) {
    final a = i == 4 ? source.baseColor : source[i];
    final b = i == 4 ? target.baseColor : target[i];
    squared +=
        .30 * math.pow(a.r * a.a - b.r * b.a, 2) +
        .40 * math.pow(a.g * a.a - b.g * b.a, 2) +
        .30 * math.pow(a.b * a.a - b.b * b.a, 2);
  }
  final span = (math.sqrt(squared / 5) / .70).clamp(0.0, 1.0);
  return Duration(milliseconds: (650 + 750 * fluidPaletteBlend(span)).round());
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
    this.motionColors = const [],
  });

  final Color first;
  final Color second;
  final Color third;
  final Color fourth;
  // Eight cover-related colours per field, prepared only when artwork changes.
  final List<Color> motionColors;

  bool stagesFieldTo(FluidPalette other, int field) =>
      other.motionColors.isNotEmpty &&
      fluidNeedsIntermediateColour(
        this[field == 3 ? 0 : field + 1],
        other[field == 3 ? 0 : field + 1],
      );

  Color motionColor(int field, int variant) {
    if (motionColors.length == 4 * fluidMotionColourCount) {
      return motionColors[field * fluidMotionColourCount + variant];
    }
    final c = this[field == 3 ? 0 : field + 1];
    final v = variant % 4;
    final scale = const [1.0, .94, .90, .97][v];
    final tint = const [0.0, .10, .10, .05][v];
    final r = c.r * c.a, g = c.g * c.a, b = c.b * c.a;
    return Color.from(
      alpha: 1,
      red: scale * (r + ((v == 2 ? b : g) - r) * tint),
      green: scale * (g + ((v == 2 ? r : b) - g) * tint),
      blue: scale * (b + ((v == 2 ? g : r) - b) * tint),
    );
  }

  // Base and ambient energy are artwork properties, not per-frame analysis.
  final Color baseColor;
  final double glowStrength;
  // A significant real artwork accent owns c2's ambient tint. Slot
  // matching may reorder the other fields, but must not evict this colour.
  final bool warmAccentLocked;
  // Actual vivid lead owns slot 1; never relabel a grey as the lead.
  final bool vividAccentLocked;
  // Orbit pigments: second=lead, third=real accent, fourth=secondary,
  // first=the fourth retained artwork pigment (may repeat for simple covers).
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
      return fluidSaturationBoost(
        hsl
            .withHue((hsl.hue + hueOffset) % 360)
            .withSaturation(
              neutralSeed
                  ? saturation.clamp(.02, .12)
                  : saturation.clamp(.18, .72),
            )
            .withLightness(lightness.clamp(.12, .62))
            .toColor(),
      );
    }

    return FluidPalette(
      shade(-18, math.max(hsl.saturation, .38), .28),
      shade(24, math.max(hsl.saturation * .9, .30), .40),
      shade(72, math.max(hsl.saturation * .72, .24), .24),
      shade(-58, math.max(hsl.saturation * .8, .28), .34),
      baseColor: fluidSaturationBoost(const Color(0xFF080A0E)),
    );
  }

  static FluidPalette lerp(
    FluidPalette source,
    FluidPalette target,
    double value, {
    double? transitionProgress,
    List<bool>? stagedFields,
  }) {
    final t = value.clamp(0.0, 1.0);
    if (t == 0) return source;
    if (t == 1) return target;
    double fieldBlend(int field) => transitionProgress == null
        ? t
        : fluidColourTransitionBlend(
            transitionProgress,
            stagedFields?[field] ?? source.stagesFieldTo(target, field),
          );
    Color mix(Color a, Color b, double blend) => Color.from(
      alpha: 1,
      red: a.r * a.a + (b.r * b.a - a.r * a.a) * blend,
      green: a.g * a.a + (b.g * b.a - a.g * a.a) * blend,
      blue: a.b * a.a + (b.b * b.a - a.b * a.a) * blend,
    );
    return FluidPalette(
      mix(source.first, target.first, fieldBlend(3)),
      mix(source.second, target.second, fieldBlend(0)),
      mix(source.third, target.third, fieldBlend(1)),
      mix(source.fourth, target.fourth, fieldBlend(2)),
      motionColors: List<Color>.unmodifiable(
        List.generate(4 * fluidMotionColourCount, (i) {
          final field = i ~/ fluidMotionColourCount,
              variant = i % fluidMotionColourCount;
          return mix(
            source.motionColor(field, variant),
            target.motionColor(field, variant),
            fieldBlend(field),
          );
        }),
      ),
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
          layeredRolesLocked == other.layeredRolesLocked &&
          listEquals(motionColors, other.motionColors);

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
    Object.hashAll(motionColors),
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
    motionColors: incoming.motionColors,
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
