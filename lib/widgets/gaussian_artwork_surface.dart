import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A single native Gaussian path for the entire image lifetime. Mirrored
/// source texels extend beyond the viewport BEFORE blur; clipping happens last.
class GaussianArtworkSurface extends StatelessWidget {
  const GaussianArtworkSurface({
    super.key,
    required this.provider,
    required this.sigma,
    this.imageKey,
    this.errorBuilder,
  });

  final ImageProvider<Object> provider;
  final double sigma;
  final Key? imageKey;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) => Image(
    key: imageKey,
    image: provider,
    gaplessPlayback: true,
    excludeFromSemantics: true,
    fit: BoxFit.cover,
    filterQuality: FilterQuality.medium,
    errorBuilder: errorBuilder,
    frameBuilder: (_, child, frame, synchronous) {
      // Native Android Image supplies RawImage when semantics are excluded.
      // Retain a normal filtered fallback for other image backends.
      final decoded = child is RawImage ? child.image : null;
      return _GaussianFrame(image: decoded, sigma: sigma, fallback: child);
    },
  );
}

class _GaussianFrame extends StatefulWidget {
  const _GaussianFrame({
    required this.image,
    required this.sigma,
    required this.fallback,
  });
  final ui.Image? image;
  final double sigma;
  final Widget fallback;
  @override
  State<_GaussianFrame> createState() => _GaussianFrameState();
}

class _GaussianFrameState extends State<_GaussianFrame> {
  ui.ImageShader? _shader;
  Object? _samplingInputs;
  ui.ImageFilter? _filter;
  double? _filterSigma;

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) {
      final viewport = constraints.biggest;
      if (viewport.isEmpty || !viewport.isFinite) return widget.fallback;
      final strength = math.max(0.0, widget.sigma);
      final zoom = (1 + strength / 450).clamp(1.0, 1.20);
      // Match the original transform's displayed sigma, without stretching a
      // pre-cropped filtered texture. Three sigma bounds the Gaussian support.
      final displayedSigma = strength * zoom;
      final padding = (displayedSigma * 3).ceilToDouble();
      final size = Size(
        viewport.width + padding * 2,
        viewport.height + padding * 2,
      );
      if (_filterSigma != displayedSigma) {
        _filterSigma = displayedSigma;
        _filter = ui.ImageFilter.blur(
          sigmaX: displayedSigma,
          sigmaY: displayedSigma,
          tileMode: TileMode.decal,
        );
      }
      final bitmap = widget.image;
      final inputs = (bitmap, viewport, strength);
      if (_samplingInputs != inputs) {
        _samplingInputs = inputs;
        _shader?.dispose();
        _shader = null;
        if (bitmap != null) {
          final scale =
              math.max(
                viewport.width / bitmap.width,
                viewport.height / bitmap.height,
              ) *
              zoom;
          final matrix = Float64List(16)
            ..[0] = scale
            ..[5] = scale
            ..[10] = 1
            ..[15] = 1
            ..[12] = (size.width - bitmap.width * scale) / 2
            ..[13] = (size.height - bitmap.height * scale) / 2;
          _shader = ui.ImageShader(
            bitmap,
            TileMode.mirror,
            TileMode.mirror,
            matrix,
            filterQuality: FilterQuality.medium,
          );
        }
      }
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.center,
          minWidth: size.width,
          maxWidth: size.width,
          minHeight: size.height,
          maxHeight: size.height,
          child: SizedBox.fromSize(
            size: size,
            child: ImageFiltered(
              enabled: strength > 0,
              imageFilter: _filter!,
              child: CustomPaint(
                isComplex: true,
                willChange: false,
                painter: _MirroredArtworkPainter(_shader),
                child: bitmap == null ? widget.fallback : null,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _MirroredArtworkPainter extends CustomPainter {
  const _MirroredArtworkPainter(this.shader);
  final ui.ImageShader? shader;
  @override
  void paint(Canvas canvas, Size size) {
    if (shader == null) return;
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_MirroredArtworkPainter oldDelegate) =>
      oldDelegate.shader != shader;
}
