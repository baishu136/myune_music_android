import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/fluid_background_state.dart';
import '../../services/fluid_background_controller.dart';

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
  Size? _paintSize;
  Rect _paintBounds = Rect.zero;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) return;
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, controller.effectiveTime);
    shader.setFloat(3, controller.motionScale);
    shader.setFloat(4, dim.clamp(0.0, .60));
    shader.setFloat(5, controller.paletteProgress);
    _writePalette(6, controller.sourcePalette);
    _writePalette(22, controller.targetPalette);
    _writeColor(38, controller.sourcePalette.baseColor);
    _writeColor(42, controller.targetPalette.baseColor);
    shader.setFloat(46, controller.sourcePalette.glowStrength);
    shader.setFloat(47, controller.targetPalette.glowStrength);
    if (_paintSize != size) {
      _paintSize = size;
      _paintBounds = Offset.zero & size;
    }
    canvas.drawRect(_paintBounds, _paint);
  }

  void _writePalette(int start, FluidPalette palette) {
    for (var slot = 0; slot < 4; slot++) {
      _writeColor(start + slot * 4, palette[slot]);
    }
  }

  void _writeColor(int start, Color color) {
    shader.setFloat(start, color.r * color.a);
    shader.setFloat(start + 1, color.g * color.a);
    shader.setFloat(start + 2, color.b * color.a);
    shader.setFloat(start + 3, color.a);
  }

  @override
  bool shouldRepaint(covariant FluidBackgroundPainter oldDelegate) =>
      oldDelegate.shader != shader ||
      oldDelegate.controller != controller ||
      oldDelegate.dim != dim;
}
