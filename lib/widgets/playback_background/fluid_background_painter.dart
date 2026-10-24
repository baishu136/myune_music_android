import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/fluid_background_controller.dart';
import 'fluid_frame_uniforms.dart';
import 'mesh_frame_uniforms.dart';

class FluidBackgroundPainter extends CustomPainter {
  FluidBackgroundPainter({
    required this.shader,
    required this.controller,
    required this.dim,
    this.mesh = false,
  }) : _paint = (Paint()..shader = shader),
       super(repaint: controller);

  final ui.FragmentShader shader;
  final FluidBackgroundController controller;
  final double dim;
  final bool mesh;
  final Paint _paint;
  late final FluidFrameUniforms _uniforms = FluidFrameUniforms();
  late final MeshFrameUniforms _meshUniforms = MeshFrameUniforms();
  Size? _paintSize;
  Rect _paintBounds = Rect.zero;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) return;
    if (mesh) {
      _meshUniforms.write(
        shader,
        size: size,
        time: controller.effectiveTime,
        motion: controller.motionScale,
        dim: dim,
        source: controller.sourcePalette,
        target: controller.targetPalette,
        paletteProgress: controller.paletteProgress,
        stagedFields: controller.stagedFields,
      );
    } else {
      _uniforms.write(
        shader,
        size: size,
        time: controller.effectiveTime,
        motion: controller.motionScale,
        dim: dim,
        source: controller.sourcePalette,
        target: controller.targetPalette,
        paletteProgress: controller.paletteProgress,
        stagedFields: controller.stagedFields,
      );
    }
    if (_paintSize != size) {
      _paintSize = size;
      _paintBounds = Offset.zero & size;
    }
    canvas.drawRect(_paintBounds, _paint);
  }

  @override
  bool shouldRepaint(covariant FluidBackgroundPainter oldDelegate) =>
      oldDelegate.shader != shader ||
      oldDelegate.controller != controller ||
      oldDelegate.dim != dim ||
      oldDelegate.mesh != mesh;
}
