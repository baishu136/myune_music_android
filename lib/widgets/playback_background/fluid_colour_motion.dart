import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/fluid_background_state.dart';

double fluidColourPhase(double orbit, int field) {
  final phase = orbit - field * math.pi / 2;
  return orbit +
      .8 * math.sin(phase) +
      .15 * math.sin(2 * phase) +
      (.08 / 3) * math.sin(3 * phase);
}

double fluidColourRate(double orbit, int field) {
  final phase = orbit - field * math.pi / 2;
  return 1 +
      .8 * math.cos(phase) +
      .30 * math.cos(2 * phase) +
      .08 * math.cos(3 * phase);
}

void cacheFluidColourVariants(Float64List buffer, FluidPalette palette) {
  for (var field = 0; field < 4; field++) {
    final colour = palette[field == 3 ? 0 : field + 1];
    final r = colour.r * colour.a,
        g = colour.g * colour.a,
        b = colour.b * colour.a;
    for (var variant = 0; variant < 4; variant++) {
      final scale = const [1.0, .94, .90, .97][variant];
      final tint = const [0.0, .10, .10, .05][variant];
      final reverse = variant == 2;
      final start = (field * 4 + variant) * 3;
      buffer[start] = scale * (r + ((reverse ? b : g) - r) * tint);
      buffer[start + 1] = scale * (g + ((reverse ? r : b) - g) * tint);
      buffer[start + 2] = scale * (b + ((reverse ? g : r) - b) * tint);
    }
  }
}
