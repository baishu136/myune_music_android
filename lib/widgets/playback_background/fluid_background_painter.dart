import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/fluid_background_state.dart';
import '../../services/fluid_background_controller.dart';

class FluidBackgroundPainter extends CustomPainter {
  FluidBackgroundPainter({
    required this.shader,
    required this.controller,
    required this.dim,
  }) : super(repaint: controller);

  final ui.FragmentShader shader;
  final FluidBackgroundController controller;
  final double dim;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) return;
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, controller.effectiveTime);
    shader.setFloat(3, controller.motionScale);
    shader.setFloat(4, dim.clamp(.2, .9));
    shader.setFloat(5, controller.paletteProgress);
    _writePalette(6, controller.sourcePalette);
    _writePalette(22, controller.targetPalette);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  void _writePalette(int start, FluidPalette palette) {
    var index = start;
    for (var slot = 0; slot < 4; slot++) {
      final color = palette[slot];
      // Colors are opaque, but keep the documented premultiplied contract.
      shader.setFloat(index++, color.r * color.a);
      shader.setFloat(index++, color.g * color.a);
      shader.setFloat(index++, color.b * color.a);
      shader.setFloat(index++, color.a);
    }
  }

  @override
  bool shouldRepaint(covariant FluidBackgroundPainter oldDelegate) =>
      oldDelegate.shader != shader ||
      oldDelegate.controller != controller ||
      oldDelegate.dim != dim;
}
