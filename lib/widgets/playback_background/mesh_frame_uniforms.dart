import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../models/fluid_background_state.dart';
import 'fluid_frame_uniforms.dart';

const meshGridStep = .1;
const meshLocalDiameterFraction = .70;

double _hash(int slot, int salt) {
  var x = (slot * 0x45d9f3b ^ salt * 0x27d4eb2d) & 0xffffffff;
  x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0xffffffff;
  x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0xffffffff;
  return (x ^ (x >> 16)) / 4294967296;
}

/// Relative HSL saturation boost; lightness and neutral colours are preserved.
void boostMeshSaturation(Float32List values, int offset) {
  final r = values[offset], g = values[offset + 1], b = values[offset + 2];
  final hi = math.max(r, math.max(g, b));
  final lo = math.min(r, math.min(g, b));
  final chroma = hi - lo;
  if (chroma < 1e-8) return;
  final light = (hi + lo) * .5;
  final scale = math.min(1.10, (1 - (2 * light - 1).abs()) / chroma);
  values[offset] = light + (r - light) * scale;
  values[offset + 1] = light + (g - light) * scale;
  values[offset + 2] = light + (b - light) * scale;
}

class MeshFrameUniforms {
  final values = Float32List(34);
  final _written = Float32List(34)..fillRange(0, 34, double.nan);
  final _paletteFrame = FluidFrameUniforms();
  final _anchor = Float64List(3);
  ui.FragmentShader? _lastShader;
  double maximumLocalDiameter = 0;

  void update({
    required ui.Size size,
    required double time,
    required double motion,
    required double dim,
    required FluidPalette source,
    required FluidPalette target,
    double paletteProgress = 1,
    List<bool>? stagedFields,
  }) {
    _paletteFrame.update(
      size: size,
      time: time,
      motion: motion,
      dim: dim,
      source: source,
      target: target,
      paletteProgress: paletteProgress,
      stagedFields: stagedFields,
    );
    final old = _paletteFrame.values;
    values[0] = size.width;
    values[1] = size.height;
    values[2] = motion.clamp(0.0, 1.0);
    values[3] = dim.clamp(0.0, .60);
    final phase = wrapFluidPhase(time) / fluidPhaseCycle;
    values[4] = phase * 10;
    values[5] = math.sin(phase * 2 * math.pi);
    // The three existing lead/accent/secondary slots provide the travelling
    // colours. Dark pigment is separated smoothly rather than sorted per frame.
    var total = 0.0;
    final anchor = _anchor..fillRange(0, 3, 0);
    for (var field = 0; field < 3; field++) {
      final i = 14 + field * 3;
      final luma = .30 * old[i] + .40 * old[i + 1] + .30 * old[i + 2];
      final weight = .001 + luma * luma;
      total += weight;
      for (var c = 0; c < 3; c++) {
        anchor[c] += old[i + c] * weight;
      }
    }
    for (var c = 0; c < 3; c++) {
      anchor[c] /= total;
    }
    var darkTotal = 0.0, lowest = 1.0;
    for (var c = 0; c < 3; c++) {
      values[15 + c] = 0;
    }
    for (var field = 0; field < 4; field++) {
      final i = 14 + field * 3;
      final luma = .30 * old[i] + .40 * old[i + 1] + .30 * old[i + 2];
      lowest = math.min(lowest, luma);
      final darkWeight = 1 / math.pow(.01 + luma, 2);
      darkTotal += darkWeight;
      for (var c = 0; c < 3; c++) {
        values[15 + c] += old[i + c] * darkWeight;
      }
      if (field < 3) {
        final keep = fluidPaletteBlend(((luma - .08) / .30).clamp(0.0, 1.0));
        for (var c = 0; c < 3; c++) {
          values[6 + field * 3 + c] =
              anchor[c] + (old[i + c] - anchor[c]) * keep;
        }
        boostMeshSaturation(values, 6 + field * 3);
      }
    }
    for (var c = 0; c < 3; c++) {
      values[15 + c] /= darkTotal;
      values[18 + c] = old[26 + c];
    }
    boostMeshSaturation(values, 15);
    boostMeshSaturation(values, 18);
    values[21] = 1 - fluidPaletteBlend(((lowest - .08) / .32).clamp(0.0, 1.0));
    // Bound the entire visible event, including the interpolation support, to
    // 70% of the smaller diameter of every corresponding previous blob.
    var previousDiameter = double.infinity;
    for (var field = 0; field < 4; field++) {
      final i = 29 + field * 4;
      final rx = 1 / math.sqrt(old[i] * old[i] + old[i + 1] * old[i + 1]);
      final ry =
          1 / math.sqrt(old[i + 2] * old[i + 2] + old[i + 3] * old[i + 3]);
      previousDiameter = math.min(previousDiameter, 2 * math.min(rx, ry));
    }
    maximumLocalDiameter = previousDiameter * meshLocalDiameterFraction;
    const support = math.sqrt2 * meshGridStep;
    final radius = math.max(0.0, maximumLocalDiameter * .5 - support);
    final shortSide = math.max(1.0, size.shortestSide);
    for (var event = 0; event < 3; event++) {
      final count = const [20, 15, 12][event];
      final p = (phase * count + event / 3) % count;
      final slot = p.floor(), part = p - p.floor();
      final pulse = fluidPaletteBlend(part < .5 ? part * 2 : (1 - part) * 2);
      final i = 22 + event * 4;
      values[i] =
          ((_hash(slot, event + 3) * size.width / shortSide) / meshGridStep)
              .round() *
          meshGridStep;
      values[i + 1] =
          ((_hash(slot, event + 31) * size.height / shortSide) / meshGridStep)
              .round() *
          meshGridStep;
      values[i + 2] = radius;
      values[i + 3] = radius > 0
          ? pulse * (_hash(slot, event + 67) > .5 ? .16 : -.16) * values[2]
          : 0;
    }
  }

  void write(
    ui.FragmentShader shader, {
    required ui.Size size,
    required double time,
    required double motion,
    required double dim,
    required FluidPalette source,
    required FluidPalette target,
    double paletteProgress = 1,
    List<bool>? stagedFields,
  }) {
    update(
      size: size,
      time: time,
      motion: motion,
      dim: dim,
      source: source,
      target: target,
      paletteProgress: paletteProgress,
      stagedFields: stagedFields,
    );
    final changed = !identical(shader, _lastShader);
    for (var i = 0; i < values.length; i++) {
      if (changed || values[i] != _written[i]) {
        shader.setFloat(i, values[i]);
        _written[i] = values[i];
      }
    }
    _lastShader = shader;
  }
}
