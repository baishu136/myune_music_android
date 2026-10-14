import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/fluid_background_controller.dart';
import 'fluid_frame_uniforms.dart';

class FluidBackgroundPainter extends CustomPainter {
  FluidBackgroundPainter({
    required this.shader,
    required this.controller,
    required this.dim,
  }) : _paint = (Paint()..shader = shader),
       super(repaint: controller);

  final ui.FragmentShader shader;
  final FluidBackgroundController controller;
  final double dim;
  final Paint _paint;
  final FluidFrameUniforms _uniforms = FluidFrameUniforms();
  Size? _paintSize;
  Rect _paintBounds = Rect.zero;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) return;
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
      oldDelegate.dim != dim;
}
