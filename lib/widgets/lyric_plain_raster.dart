import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../services/interaction_performance_controller.dart';
import 'lyric_raster_pool.dart';

int debugLyricPlainRasterPreparations = 0;
int debugLyricPlainRasterPaints = 0;

/// Retain the native paragraph for layout, fallback and semantics. Only paint
/// uses a ready native-RGB image; alpha stays outside this render boundary.
class LyricPlainRaster extends SingleChildRenderObjectWidget {
  const LyricPlainRaster({
    super.key,
    required this.identity,
    required this.pixelRatio,
    required this.rank,
    required super.child,
  });
  final Object identity;
  final double pixelRatio;
  final int rank;
  @override
  RenderLyricPlainRaster createRenderObject(BuildContext context) =>
      RenderLyricPlainRaster(identity, pixelRatio, rank);
  @override
  void updateRenderObject(
    BuildContext context,
    RenderLyricPlainRaster renderObject,
  ) => renderObject.configure(identity, pixelRatio, rank);
}

class RenderLyricPlainRaster extends RenderProxyBox
    implements LyricRasterClient {
  RenderLyricPlainRaster(this._identity, this._dpr, this._rank);
  Object _identity;
  double _dpr;
  int _rank;
  int _sequence = 0, _pixels = 0;
  bool _failed = false;
  ui.Image? _image;
  _InkJob? _job;
  static const _padding = 32.0;
  final _paint = Paint()..filterQuality = FilterQuality.low;

  ui.Image? get debugImage => _image;
  @override
  int get rasterDemand => _failed ? 0 : _pixels;
  @override
  int get rasterRank => _rank * 2;
  @override
  int get rasterSequence => _sequence;
  @override
  bool get rasterReserved => _job != null;

  void configure(Object identity, double dpr, int rank) {
    if (_identity != identity || _dpr != dpr) {
      _discard();
      _identity = identity;
      _dpr = dpr;
      _failed = false;
      markNeedsLayout();
    }
    if (_rank != rank) {
      _rank = rank;
      _updateDemand();
      LyricRasterPool.schedule();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _sequence = LyricRasterPool.register(this);
    _updateDemand();
  }

  @override
  void detach() {
    LyricRasterPool.unregister(this);
    _discard();
    super.detach();
  }

  @override
  void performLayout() {
    final previous = hasSize ? size : null;
    super.performLayout();
    if (previous != size) {
      _discard();
      _failed = false;
    }
    _updateDemand();
  }

  void _updateDemand() {
    final width = hasSize ? ((size.width + 2 * _padding) * _dpr).ceil() : 0;
    final height = hasSize ? ((size.height + 2 * _padding) * _dpr).ceil() : 0;
    // No downsampling, no full-song cache. Far rows retain native painting.
    final eligible =
        attached &&
        _rank % 10000 <= 2 &&
        _dpr >= 1 &&
        _dpr <= 4 &&
        width > 0 &&
        height > 0 &&
        width <= 4096 &&
        height <= 4096 &&
        width * height <= 2097152;
    final demand = eligible ? width * height : 0;
    if (_pixels != demand) {
      _pixels = demand;
      LyricRasterPool.schedule();
    }
  }

  InteractionWorkPriority _priority() => _rank <= 1
      ? InteractionWorkPriority.currentVisual
      : _rank <= 3
      ? InteractionWorkPriority.userVisible
      : InteractionWorkPriority.background;

  @override
  void reserveRaster() {
    if (_job != null || !attached || rasterDemand == 0) return;
    final job = _InkJob(LyricRasterReservation(rasterDemand));
    _job = job;
    bool needed() => attached && _job == job;
    job.needed = needed;
    unawaited(() async {
      final lease = await InteractionPerformanceController.instance
          .acquireIdleWork(
            priority: _priority(),
            priorityForWork: _priority,
            isStillNeeded: needed,
          );
      OffsetLayer? capture;
      try {
        if (!lease.isGranted || !needed()) return;
        final target = child;
        if (target is! RenderParagraph) return;
        // Record only at idle, after native layout. Never record from paint or
        // during a lyric transition, route gesture or a real scroll.
        capture = OffsetLayer();
        _InkPaintingContext(capture, Offset.zero & size).record(target);
        job.started = true;
        debugLyricPlainRasterPreparations++;
        final image = await capture.toImage(
          Rect.fromLTWH(
            0,
            0,
            size.width + 2 * _padding,
            size.height + 2 * _padding,
          ),
          pixelRatio: _dpr,
        );
        if (!needed()) {
          image.dispose();
          return;
        }
        _image = image;
        markNeedsPaint();
      } catch (_) {
        if (needed()) _failed = true;
      } finally {
        capture?.dispose();
        job.finished = true;
        if (!needed() || _image == null) {
          job.reservation.release();
          if (_job == job) {
            _job = null;
            _failed = true;
          }
        }
        lease.release();
      }
    }());
  }

  void _discard() {
    final job = _job;
    _job = null;
    if (job != null) {
      InteractionPerformanceController.instance.cancelIdleWork(job.needed);
      if (!job.started || job.finished) job.reservation.release();
    }
    _image?.dispose();
    _image = null;
    if (attached) markNeedsPaint();
  }

  @override
  void evictRaster() => _discard();

  @override
  void paint(PaintingContext context, Offset offset) {
    final image = _image;
    if (image == null) {
      super.paint(context, offset);
      return;
    }
    debugLyricPlainRasterPaints++;
    context.canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(
        offset.dx - _padding,
        offset.dy - _padding,
        image.width / _dpr,
        image.height / _dpr,
      ),
      _paint,
    );
  }

  @override
  void dispose() {
    _discard();
    super.dispose();
  }
}

class _InkJob {
  _InkJob(this.reservation);
  final LyricRasterReservation reservation;
  late final bool Function() needed;
  bool started = false, finished = false;
}

class _InkPaintingContext extends PaintingContext {
  _InkPaintingContext(super.containerLayer, super.estimatedBounds);
  void record(RenderParagraph paragraph) {
    paintChild(paragraph, const Offset(32, 32));
    stopRecordingIfNeeded();
  }
}
