import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../models/fluid_background_state.dart';
import 'fluid_colour_motion.dart';

/// Integrated low-frequency velocity, not random per-frame speeds. The angular
/// rate stays .52–1.48 times the base rate; acceleration and jerk are continuous
/// across the cycle seam. Separate offsets give each blob its own slow ramp.
double fluidOrbitAngle(double orbit, int field, double amplitude) {
  final offset = field * math.pi / 2;
  return orbit +
      offset +
      amplitude *
          (.32 * math.sin(orbit) +
              .04 * math.sin(2 * orbit + 1.7) +
              .08 * math.sin(orbit + offset + .9));
}

/// Matches the shader: size(2), motion/dim(2), phases(2), centres(8),
/// pigments(12), base(3), shape matrices(16). Reuses all buffers.
class FluidFrameUniforms {
  final values = Float32List(45);
  final _written = Float32List(45)..fillRange(0, 45, double.nan);
  final _source = Float64List(15);
  final _target = Float64List(15);
  final _mixed = Float64List(15);
  final _sourceVariants = Float64List(48);
  final _targetVariants = Float64List(48);
  FluidPalette? _sourcePalette, _targetPalette;
  ui.FragmentShader? _lastShader;

  void _cachePalette(Float64List buffer, FluidPalette palette) {
    for (var i = 0; i < 5; i++) {
      final color = i == 4 ? palette.baseColor : palette[i];
      buffer[i * 3] = color.r * color.a;
      buffer[i * 3 + 1] = color.g * color.a;
      buffer[i * 3 + 2] = color.b * color.a;
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
  }) {
    if (_sourcePalette != source) {
      _sourcePalette = source;
      _cachePalette(_source, source);
      cacheFluidColourVariants(_sourceVariants, source);
    }
    if (_targetPalette != target) {
      _targetPalette = target;
      _cachePalette(_target, target);
      cacheFluidColourVariants(_targetVariants, target);
    }
    final blend = fluidPaletteBlend(paletteProgress);
    for (var i = 0; i < 15; i++) {
      _mixed[i] = _source[i] + (_target[i] - _source[i]) * blend;
    }
    final orbit = time * fluidShaderTimeScale;
    final phase =
        orbit + .28 * math.sin(orbit) + .06 * math.sin(2 * orbit + 1.7);
    final phase2 =
        orbit + .26 * math.sin(orbit + 2.1) + .04 * math.sin(2 * orbit + .8);
    final amplitude = motion.clamp(0.0, 1.0);
    final hubX = .5 + amplitude * .085 * math.sin(2 * orbit + .9);
    final hubY = .5 + amplitude * .075 * math.cos(3 * orbit - .4);
    values[0] = size.width;
    values[1] = size.height;
    values[2] = amplitude;
    values[3] = dim.clamp(0.0, .60);
    values[4] = phase;
    values[5] = phase2;
    for (var field = 0; field < 4; field++) {
      final offset = field * math.pi / 2;
      final angle = fluidOrbitAngle(orbit, field, amplitude);
      final radius =
          .39 +
          amplitude *
              (.16 * math.sin(orbit + offset + .7) +
                  .09 * math.sin(2 * orbit - offset));
      values[6 + field * 2] = hubX + radius * math.cos(angle);
      values[7 + field * 2] = hubY + radius * math.sin(angle) * 1.08;
      final radiusX =
          .44 * (1 + .12 * amplitude * math.sin(orbit + offset + .8));
      final radiusY =
          .44 * (1 + .12 * amplitude * math.sin(2 * orbit - offset + 1.2));
      final rotation = .35 * amplitude * math.sin(orbit - offset + .4);
      final cosine = math.cos(rotation), sine = math.sin(rotation);
      final shape = 29 + field * 4;
      values[shape] = cosine / radiusX;
      values[shape + 1] = sine / radiusX;
      values[shape + 2] = -sine / radiusY;
      values[shape + 3] = cosine / radiusY;
      final colourPosition =
          (fluidColourPhase(orbit, field) * 2 / math.pi + field) % 4;
      final variant = colourPosition.floor();
      final nextVariant = (variant + 1) % 4;
      // Quintic smoothstep gives zero endpoint velocity with continuously varying
      // phase speed; the four rates share a constant budget of four.
      final part = colourPosition - variant;
      final colourBlend = fluidPaletteBlend(part);
      for (var channel = 0; channel < 3; channel++) {
        final start = (field * 4 + variant) * 3 + channel;
        final end = (field * 4 + nextVariant) * 3 + channel;
        final from =
            _sourceVariants[start] +
            (_sourceVariants[end] - _sourceVariants[start]) * colourBlend;
        final to =
            _targetVariants[start] +
            (_targetVariants[end] - _targetVariants[start]) * colourBlend;
        values[14 + field * 3 + channel] = from + (to - from) * blend;
      }
    }
    for (var channel = 0; channel < 3; channel++) {
      values[26 + channel] = _mixed[12 + channel];
    }
    final changedShader = !identical(shader, _lastShader);
    for (var i = 0; i < values.length; i++) {
      if (changedShader || _written[i] != values[i]) {
        shader.setFloat(i, values[i]);
        _written[i] = values[i];
      }
    }
    _lastShader = shader;
  }
}
