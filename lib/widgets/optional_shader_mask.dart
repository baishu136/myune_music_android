import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Render-time bypass without replacing the masked child's Element/State.
class OptionalShaderMask extends SingleChildRenderObjectWidget {
  const OptionalShaderMask({
    super.key,
    required this.active,
    required this.shaderCallback,
    this.blendMode = BlendMode.modulate,
    super.child,
  });
  final bool active;
  final ShaderCallback shaderCallback;
  final BlendMode blendMode;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderOptionalShaderMask(
        active: active,
        shaderCallback: shaderCallback,
        blendMode: blendMode,
      );
  @override
  void updateRenderObject(
    BuildContext context,
    RenderOptionalShaderMask renderObject,
  ) {
    renderObject
      ..active = active
      ..shaderCallback = shaderCallback
      ..blendMode = blendMode;
  }
}

class RenderOptionalShaderMask extends RenderShaderMask {
  RenderOptionalShaderMask({
    required bool active,
    required super.shaderCallback,
    required super.blendMode,
  }) : _active = active;
  bool _active;
  set active(bool value) {
    if (_active == value) return;
    _active = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _active && child != null;
  @override
  void paint(PaintingContext context, Offset offset) {
    if (_active) {
      super.paint(context, offset);
    } else {
      layer = null;
      if (child != null) context.paintChild(child!, offset);
    }
  }
}
