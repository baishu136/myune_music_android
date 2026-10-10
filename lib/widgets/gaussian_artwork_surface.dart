import 'dart:async';
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
    this.transitionDuration = Duration.zero,
    this.adaptiveColorTransition = false,
  });

  final ImageProvider<Object> provider;
  final double sigma;
  final Key? imageKey;
  final ImageErrorWidgetBuilder? errorBuilder;
  final Duration transitionDuration;
  final bool adaptiveColorTransition;

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
      return _ArtworkTransition(
        image: decoded,
        sigma: sigma,
        duration: transitionDuration,
        adaptiveColorTransition: adaptiveColorTransition,
        fallback: child,
      );
    },
  );
}

/// Image State may release its old frame as soon as a decode completes. Own
/// clones until the fade finishes; rapid changes retain only the latest queue.
class _ArtworkTransition extends StatefulWidget {
  const _ArtworkTransition({
    required this.image,
    required this.sigma,
    required this.duration,
    required this.adaptiveColorTransition,
    required this.fallback,
  });
  final ui.Image? image;
  final double sigma;
  final Duration duration;
  final bool adaptiveColorTransition;
  final Widget fallback;
  @override
  State<_ArtworkTransition> createState() => _ArtworkTransitionState();
}

class _ArtworkTransitionState extends State<_ArtworkTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;
  late final Animation<double> _opacity;
  ui.Image? _current, _previous, _pending;
  Future<Uint8List?>? _currentProfile;
  int _revision = 0;
  bool get _animate =>
      widget.duration > Duration.zero &&
      !MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    _current = widget.image?.clone();
    if (widget.adaptiveColorTransition && _current != null) {
      _currentProfile = _sampleBackground(_current!);
    }
    _fade = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener(_finished);
    _opacity = CurvedAnimation(parent: _fade, curve: Curves.easeInOutCubic);
  }

  @override
  void didUpdateWidget(covariant _ArtworkTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    final image = widget.image;
    if (image == null) return;
    final latest = _pending ?? _current;
    if (latest != null && image.isCloneOf(latest)) return;
    final next = image.clone();
    if (_previous != null && _animate) {
      _pending?.dispose();
      _pending = next;
      return;
    }
    _adopt(next);
  }

  void _adopt(ui.Image next) {
    _previous?.dispose();
    _previous = _current;
    final previousProfile = _currentProfile;
    _current = next;
    _currentProfile = widget.adaptiveColorTransition
        ? _sampleBackground(next)
        : null;
    _revision++;
    if (_previous != null && _animate) {
      _fade.duration = widget.duration;
      _fade.value = 0;
      if (widget.adaptiveColorTransition) {
        unawaited(
          _prepareFade(
            _revision,
            previousProfile ?? _sampleBackground(_previous!),
            _currentProfile!,
          ),
        );
      } else {
        _fade.forward(from: 0);
      }
    } else {
      _previous?.dispose();
      _previous = null;
    }
  }

  Future<void> _prepareFade(
    int revision,
    Future<Uint8List?> before,
    Future<Uint8List?> after,
  ) async {
    final profiles = await Future.wait([before, after]);
    if (!mounted || revision != _revision || _previous == null) return;
    if (!_animate) {
      _fade.value = 1;
      return;
    }
    if (profiles[0] != null && profiles[1] != null) {
      _fade.duration = _colorSpanDuration(profiles[0]!, profiles[1]!);
    }
    _fade.forward(from: 0);
  }

  void _finished(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() {
      _previous?.dispose();
      _previous = null;
      final next = _pending;
      _pending = null;
      if (next != null) _adopt(next);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_animate && _previous != null) _fade.value = 1;
  }

  @override
  void dispose() {
    _fade.removeStatusListener(_finished);
    (_opacity as CurvedAnimation).dispose();
    _fade.dispose();
    _current?.dispose();
    _previous?.dispose();
    _pending?.dispose();
    super.dispose();
  }

  Widget _surface(ui.Image? image, int revision, Animation<double> opacity) =>
      FadeTransition(
        key: ValueKey(revision),
        opacity: opacity,
        child: RepaintBoundary(
          child: _GaussianFrame(
            image: image,
            sigma: widget.sigma,
            fallback: widget.fallback,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_previous != null)
          _surface(_previous, _revision - 1, const AlwaysStoppedAnimation(1)),
        _surface(
          _current,
          _revision,
          _previous == null ? const AlwaysStoppedAnimation(1) : _opacity,
        ),
      ],
    );
  }
}

// Sample the already-decoded texture once at 16x16; never read back the full
// artwork or repeat the work on animation frames. Picture owns its draw refs
// until toImage finishes even if the widget releases its original clone.
Future<Uint8List?> _sampleBackground(ui.Image image) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    const Rect.fromLTWH(0, 0, 16, 16),
    Paint()..filterQuality = FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  ui.Image? sample;
  try {
    sample = await picture.toImage(16, 16);
    return (await sample.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))?.buffer.asUint8List();
  } catch (_) {
    return null; // Keep the caller's fixed duration if a readback is unavailable.
  } finally {
    sample?.dispose();
    picture.dispose();
  }
}

Duration _colorSpanDuration(Uint8List before, Uint8List after) {
  var squared = 0.0;
  for (var i = 0; i < before.length; i += 4) {
    final a = before[i + 3] / 255, b = after[i + 3] / 255;
    // rawRgba is already premultiplied: apply opacity exactly once.
    final r = (before[i] - after[i]) / 255;
    final g = (before[i + 1] - after[i + 1]) / 255;
    final blue = (before[i + 2] - after[i + 2]) / 255;
    squared +=
        .30 * r * r + .40 * g * g + .30 * blue * blue + .20 * (a - b) * (a - b);
  }
  final span = (math.sqrt(squared / (before.length / 4)) / .70).clamp(0.0, 1.0);
  final smooth = span * span * (3 - 2 * span);
  return Duration(milliseconds: (280 + 620 * smooth).round());
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
