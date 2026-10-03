import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// Bounded, pre-created filters. Edge motion uses .2 steps; focus handoffs keep
// their existing .05 precision. No native filter construction while scrolling.
final _filters = List<ui.ImageFilter>.generate(
  121,
  (step) => ui.ImageFilter.blur(
    sigmaX: step / 20,
    sigmaY: step / 20,
    tileMode: ui.TileMode.decal,
  ),
  growable: false,
);

ui.ImageFilter cachedLyricBlur(double sigma) =>
    _filters[(sigma.clamp(0.0, 6.0) * 20).round()];

double lyricViewportBlurSigma({
  required double baseSigma,
  required double centerY,
  required double viewportHeight,
  required bool edgeEnabled,
}) {
  final base = baseSigma.isFinite ? baseSigma.clamp(0.0, 3.0) : 0.0;
  if (!edgeEnabled ||
      !centerY.isFinite ||
      !viewportHeight.isFinite ||
      viewportHeight <= 0) {
    return base;
  }
  final band = (viewportHeight * .24).clamp(80.0, 180.0);
  final distance = math.min(centerY, viewportHeight - centerY);
  final t = (1 - distance / band).clamp(0.0, 1.0);
  final smooth = t * t * (3 - 2 * t);
  return base + (2.4 * smooth * 5).round() / 5;
}

/// One filtered compositing layer, not a second blur over an existing filter.
/// Scroll updates only its cached filter; neither widgets nor child text layout
/// are rebuilt. Center coordinates come from the list's measured geometry.
class LyricViewportBlur extends ImageFiltered {
  LyricViewportBlur({
    super.key,
    required this.sigma,
    required this.contentCenter,
    required this.viewportHeight,
    required this.edgeEnabled,
    required this.scrollController,
    required super.child,
  }) : super(imageFilter: cachedLyricBlur(sigma), enabled: sigma > .01);

  final double sigma;
  final double contentCenter;
  final double viewportHeight;
  final bool edgeEnabled;
  final ScrollController scrollController;

  @override
  RenderLyricViewportBlur createRenderObject(BuildContext context) =>
      RenderLyricViewportBlur(this);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLyricViewportBlur renderObject,
  ) => renderObject.configure(this);
}

class RenderLyricViewportBlur extends RenderProxyBox {
  RenderLyricViewportBlur(LyricViewportBlur config) : _config = config {
    _refresh();
  }

  LyricViewportBlur _config;
  double sigma = 0;
  ui.ImageFilter _filter = cachedLyricBlur(0);
  bool get _enabled => _config.enabled;

  void configure(LyricViewportBlur value) {
    final old = _config;
    if (attached && old.scrollController != value.scrollController) {
      old.scrollController.removeListener(_refresh);
      value.scrollController.addListener(_refresh);
    }
    _config = value;
    if (old.enabled != value.enabled) {
      markNeedsCompositingBitsUpdate();
      markNeedsPaint();
    }
    _refresh();
  }

  void _refresh() {
    final position = _config.scrollController;
    final next = lyricViewportBlurSigma(
      baseSigma: _config.sigma,
      centerY:
          _config.contentCenter -
          (position.hasClients
              ? position.offset
              : position.initialScrollOffset),
      viewportHeight: _config.viewportHeight,
      edgeEnabled: _config.edgeEnabled,
    );
    final nextFilter = cachedLyricBlur(next);
    sigma = next;
    if (nextFilter == _filter) return;
    _filter = nextFilter;
    markNeedsCompositedLayerUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _config.scrollController.addListener(_refresh);
    _refresh();
  }

  @override
  void detach() {
    _config.scrollController.removeListener(_refresh);
    super.detach();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _enabled;
  @override
  bool get isRepaintBoundary => alwaysNeedsCompositing;
  @override
  ImageFilterLayer updateCompositedLayer({
    required covariant ImageFilterLayer? oldLayer,
  }) {
    final layer = oldLayer ?? ImageFilterLayer();
    layer.imageFilter = _filter;
    return layer;
  }
}
