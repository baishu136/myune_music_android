import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import '../../models/fluid_background_state.dart';

double fluidColourPhase(double orbit, int field) {
  orbit *= 2;
  final phase = orbit - field * math.pi / 2;
  return orbit +
      .8 * math.sin(phase) +
      .15 * math.sin(2 * phase) +
      (.08 / 3) * math.sin(3 * phase);
}

double fluidColourRate(double orbit, int field) {
  orbit *= 2;
  final phase = orbit - field * math.pi / 2;
  return 2 *
      (1 +
          .8 * math.cos(phase) +
          .30 * math.cos(2 * phase) +
          .08 * math.cos(3 * phase));
}

void cacheFluidColourVariants(Float64List buffer, FluidPalette palette) {
  for (var field = 0; field < 4; field++) {
    for (var variant = 0; variant < fluidMotionColourCount; variant++) {
      final colour = palette.motionColor(field, variant);
      final start = (field * fluidMotionColourCount + variant) * 3;
      buffer[start] = colour.r * colour.a;
      buffer[start + 1] = colour.g * colour.a;
      buffer[start + 2] = colour.b * colour.a;
    }
  }
}

double fluidColourPosition(double time, int field) {
  final position =
      (fluidColourPhase(time * fluidShaderTimeScale, field) * 2 / math.pi) %
      fluidMotionColourCount;
  return position >= fluidMotionColourCount ? 0 : position;
}

Color fluidFieldColourAtTime(FluidPalette palette, double time, int field) {
  final position = fluidColourPosition(time, field);
  final index = position.floor();
  final from = palette.motionColor(field, index);
  final to = palette.motionColor(field, (index + 1) % fluidMotionColourCount);
  final t = fluidPaletteBlend(position - index);
  return Color.from(
    alpha: 1,
    red: from.r * from.a + (to.r * to.a - from.r * from.a) * t,
    green: from.g * from.a + (to.g * to.a - from.g * from.a) * t,
    blue: from.b * from.a + (to.b * to.a - from.b * from.a) * t,
  );
}

/// A slow, staggered handoff around neighbouring fields. The envelope and its
/// derivatives remain continuous at the existing five-orbit clock wrap.
double fluidColourRelayWeight(double time, int field, double motion) {
  final pulse =
      .5 + .5 * math.sin(time * fluidShaderTimeScale - field * math.pi / 2);
  return .24 *
      motion.clamp(0.0, 1.0) *
      fluidPaletteBlend(pulse).clamp(0.0, 1.0);
}

/// Read only the four original pigments, so a handoff cannot recursively wash
/// all fields into one colour. Geometry, shader and the base remain unchanged.
/// Buffers belong to the painter; no per-frame Color/HSL/list allocations.
void writeFluidColourRelay(
  Float64List pigments,
  Float32List packed,
  double time,
  double motion,
) {
  final shortSide = math.max(1.0, math.min(packed[0], packed[1]));
  for (var field = 0; field < 4; field++) {
    final donor = (field + 3) % 4;
    final dx =
        (packed[6 + field * 2] - packed[6 + donor * 2]) * packed[0] / shortSide;
    final dy =
        (packed[7 + field * 2] - packed[7 + donor * 2]) * packed[1] / shortSide;
    final weight =
        fluidColourRelayWeight(time, field, motion) /
        (1 + .30 * (dx * dx + dy * dy));
    final own = field * 3, other = donor * 3;
    var r = pigments[own] + (pigments[other] - pigments[own]) * weight;
    var g =
        pigments[own + 1] + (pigments[other + 1] - pigments[own + 1]) * weight;
    var b =
        pigments[own + 2] + (pigments[other + 2] - pigments[own + 2]) * weight;
    final low = math.min(r, math.min(g, b)), high = math.max(r, math.max(g, b));
    final chroma = high - low;
    if (chroma > .000001) {
      final ownChroma =
          math.max(
            pigments[own],
            math.max(pigments[own + 1], pigments[own + 2]),
          ) -
          math.min(
            pigments[own],
            math.min(pigments[own + 1], pigments[own + 2]),
          );
      final donorChroma =
          math.max(
            pigments[other],
            math.max(pigments[other + 1], pigments[other + 2]),
          ) -
          math.min(
            pigments[other],
            math.min(pigments[other + 1], pigments[other + 2]),
          );
      final desired = ownChroma + (donorChroma - ownChroma) * weight;
      final midpoint = (high + low) * .5;
      // Bound chroma restoration; opposite pigments should not turn into grey
      // or acquire clipped, neon edges. Lightness stays at the mixed midpoint.
      final gain = math.max(
        1.0,
        math.min(
          1.15,
          math.min(
            desired / chroma,
            2 * math.min(midpoint, 1 - midpoint) / chroma,
          ),
        ),
      );
      r = midpoint + (r - midpoint) * gain;
      g = midpoint + (g - midpoint) * gain;
      b = midpoint + (b - midpoint) * gain;
    }
    packed[14 + own] = r;
    packed[15 + own] = g;
    packed[16 + own] = b;
  }
}
