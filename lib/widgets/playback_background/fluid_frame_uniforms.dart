import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../models/fluid_background_state.dart';
import 'fluid_colour_motion.dart';
import 'fluid_field_travel.dart';

/// Matches the shader: size(2), motion/dim(2), phases(2), centres(8),
/// pigments(12), base(3), shape matrices(16), weight deltas(4), protection(4),
/// pigment chroma(4), computed once per frame instead of once per pixel.
/// The original 45 floats retain their offsets; reuses all buffers.
class FluidFrameUniforms {
  final values = Float32List(57);
  final _written = Float32List(57)..fillRange(0, 57, double.nan);
  final _source = Float64List(19);
  final _target = Float64List(19);
  final _mixed = Float64List(19);
  final _fieldColours = Float64List(12);
  final _sourceVariants = Float64List(4 * fluidMotionColourCount * 3);
  final _targetVariants = Float64List(4 * fluidMotionColourCount * 3);
  final _sourceWeights = Float64List(4 * fluidMotionColourCount);
  final _targetWeights = Float64List(4 * fluidMotionColourCount);
  final _stagedFields = List<bool>.filled(4, false);
  FluidPalette? _sourcePalette, _targetPalette;
  ui.FragmentShader? _lastShader;

  void _cachePalette(Float64List buffer, FluidPalette palette) {
    for (var i = 0; i < 5; i++) {
      final color = i == 4 ? palette.baseColor : palette[i];
      buffer[i * 3] = color.r * color.a;
      buffer[i * 3 + 1] = color.g * color.a;
      buffer[i * 3 + 2] = color.b * color.a;
    }
    final anchor = palette.mixAnchor ?? palette.second;
    buffer[15] = anchor.r * anchor.a;
    buffer[16] = anchor.g * anchor.a;
    buffer[17] = anchor.b * anchor.a;
    buffer[18] = palette.mixProtection;
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
    final paletteChanged = _sourcePalette != source || _targetPalette != target;
    if (_sourcePalette != source) {
      _sourcePalette = source;
      _cachePalette(_source, source);
      cacheFluidColourVariants(_sourceVariants, source);
      for (var i = 0; i < _sourceWeights.length; i++) {
        _sourceWeights[i] = source.motionWeight(
          i ~/ fluidMotionColourCount,
          i % fluidMotionColourCount,
        );
      }
    }
    if (paletteChanged || stagedFields != null) {
      for (var field = 0; field < 4; field++) {
        _stagedFields[field] =
            stagedFields?[field] ?? source.stagesFieldTo(target, field);
      }
    }
    if (_targetPalette != target) {
      _targetPalette = target;
      _cachePalette(_target, target);
      cacheFluidColourVariants(_targetVariants, target);
      for (var i = 0; i < _targetWeights.length; i++) {
        _targetWeights[i] = target.motionWeight(
          i ~/ fluidMotionColourCount,
          i % fluidMotionColourCount,
        );
      }
    }
    final blend = fluidPaletteBlend(paletteProgress);
    for (var i = 0; i < 19; i++) {
      _mixed[i] = _source[i] + (_target[i] - _source[i]) * blend;
    }
    final colourOrbit = time * fluidShaderTimeScale;
    final orbit = colourOrbit * fluidMotionSpeedScale;
    final shapePhase = orbit * 1.6;
    final phase =
        orbit + .28 * math.sin(orbit) + .06 * math.sin(2 * orbit + 1.7);
    final phase2 =
        orbit + .26 * math.sin(orbit + 2.1) + .04 * math.sin(2 * orbit + .8);
    final amplitude = motion.clamp(0.0, 1.0);
    final shortSide = math.min(size.width, size.height);
    final radiusBase = math.min(.52, size.longestSide / shortSide / (3 * 1.16));
    values[0] = size.width;
    values[1] = size.height;
    values[2] = amplitude;
    values[3] = dim.clamp(0.0, .60);
    values[4] = phase;
    values[5] = phase2;
    for (var field = 0; field < 4; field++) {
      final offset = field * math.pi / 2;
      final colourPhase = fluidColourPhase(colourOrbit, field) * 2 / math.pi;
      writeFluidFieldPosition(values, field, time, colourPhase, amplitude);
      final radiusX =
          radiusBase *
          (1 + .16 * amplitude * math.sin(shapePhase + offset + .8));
      final radiusY =
          radiusBase *
          (1 + .16 * amplitude * math.sin(2 * shapePhase - offset + 1.2));
      final rotation = .35 * amplitude * math.sin(shapePhase - offset + .4);
      final cosine = math.cos(rotation), sine = math.sin(rotation);
      final shape = 29 + field * 4;
      values[shape] = cosine / radiusX;
      values[shape + 1] = sine / radiusX;
      values[shape + 2] = -sine / radiusY;
      values[shape + 3] = cosine / radiusY;
      final wrappedPosition = colourPhase % fluidMotionColourCount;
      final colourPosition = wrappedPosition >= fluidMotionColourCount
          ? 0.0
          : wrappedPosition;
      final variant = colourPosition.floor();
      final nextVariant = (variant + 1) % fluidMotionColourCount;
      // Quintic smoothstep gives zero endpoint velocity with continuously varying
      // phase speed; the four doubled rates share a constant budget of eight.
      final part = colourPosition - variant;
      final colourBlend = fluidPaletteBlend(part);
      final fieldBlend = fluidColourTransitionBlend(
        paletteProgress,
        _stagedFields[field],
      );
      final weightStart = field * fluidMotionColourCount + variant;
      final weightEnd = field * fluidMotionColourCount + nextVariant;
      final sourceWeight =
          _sourceWeights[weightStart] +
          (_sourceWeights[weightEnd] - _sourceWeights[weightStart]) *
              colourBlend;
      final targetWeight =
          _targetWeights[weightStart] +
          (_targetWeights[weightEnd] - _targetWeights[weightStart]) *
              colourBlend;
      values[45 + field] =
          (sourceWeight + (targetWeight - sourceWeight) * fieldBlend).clamp(
            .55,
            1.65,
          ) -
          1;
      final influence = 1 + values[45 + field];
      final radiusInfluence = influence < 1
          ? .65 + .35 * fluidPaletteBlend((influence - .55) / .45)
          : 1 + .1 * fluidPaletteBlend((influence - 1) / .65);
      for (var component = 0; component < 4; component++) {
        values[shape + component] /= radiusInfluence;
      }
      for (var channel = 0; channel < 3; channel++) {
        final start = (field * fluidMotionColourCount + variant) * 3 + channel;
        final end =
            (field * fluidMotionColourCount + nextVariant) * 3 + channel;
        final from =
            _sourceVariants[start] +
            (_sourceVariants[end] - _sourceVariants[start]) * colourBlend;
        final to =
            _targetVariants[start] +
            (_targetVariants[end] - _targetVariants[start]) * colourBlend;
        _fieldColours[field * 3 + channel] = from + (to - from) * fieldBlend;
      }
    }
    writeFluidColourRelay(_fieldColours, values, time, amplitude);
    for (var field = 0; field < 4; field++) {
      final i = 14 + field * 3;
      values[53 + field] =
          math.max(values[i], math.max(values[i + 1], values[i + 2])) -
          math.min(values[i], math.min(values[i + 1], values[i + 2]));
    }
    for (var channel = 0; channel < 3; channel++) {
      values[26 + channel] = _mixed[12 + channel];
      values[49 + channel] = _mixed[15 + channel];
    }
    values[52] = _mixed[18].clamp(0.0, .20);
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
