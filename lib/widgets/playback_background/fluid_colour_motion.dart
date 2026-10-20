import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import '../../models/fluid_background_state.dart';

double fluidColourPhase(double orbit, int field) {
  orbit *= .8;
  final phase = orbit - field * math.pi / 2;
  return orbit +
      .8 * math.sin(phase) +
      .15 * math.sin(2 * phase) +
      (.08 / 3) * math.sin(3 * phase);
}

double fluidColourRate(double orbit, int field) {
  orbit *= .8;
  final phase = orbit - field * math.pi / 2;
  return .8 *
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

/// Deterministic random seeds spread to nearby edges, with no timers or RNG
/// in paint. Pulses finish before their slot ends, including the wrap seam.
class FluidColourRelayFrame {
  final donors = Int32List(4);
  final strengths = Float64List(4);

  void update(double time, Float32List uniforms) {
    final position = wrapFluidPhase(time) / fluidPhaseCycle * 20;
    final slot = position.floor();
    final part = position - slot;
    final hash = ((slot + 11) * 1103515245 + 12345) & 0x7fffffff;
    final seed = (hash >> 12) & 3;
    final direction = (hash & 0x10000) == 0 ? 1 : -1;
    final width = uniforms[0], height = uniforms[1];
    final shortSide = math.max(1.0, math.min(width, height));
    for (var field = 0; field < 4; field++) {
      final hop = ((field - seed) * direction) % 4;
      final donor = (field - direction) % 4;
      donors[field] = donor;
      final phase = (part - hop * .12) / .58;
      if (hop == 0 || phase <= 0 || phase >= 1) {
        strengths[field] = 0;
        continue;
      }
      final dx =
          (uniforms[6 + field * 2] - uniforms[6 + donor * 2]) *
          width /
          shortSide;
      final dy =
          (uniforms[7 + field * 2] - uniforms[7 + donor * 2]) *
          height /
          shortSide;
      final proximity = fluidPaletteBlend(
        ((1.28 - math.sqrt(dx * dx + dy * dy)) / .7).clamp(0.0, 1.0),
      );
      final pulse = fluidPaletteBlend(1 - (2 * phase - 1).abs());
      strengths[field] = .35 * proximity * pulse;
    }
  }
}
