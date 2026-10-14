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
