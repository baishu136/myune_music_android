import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../services/interaction_performance_controller.dart';
import 'lyric_raster_pool.dart';
import 'lyric_plain_prewarm.dart';

int debugLyricPlainRasterPreparations = 0;
int debugLyricPlainRasterPaints = 0;
int debugLyricPlainNativePaints = 0;

/// Retain the native paragraph for layout, fallback and semantics. Only paint
/// uses a ready native-RGB image; alpha stays outside this render boundary.
class LyricPlainRaster extends SingleChildRenderObjectWidget {
  const LyricPlainRaster({
    super.key,
    required this.identity,
    required this.pixelRatio,
    required this.rank,
    this.prepared,
    this.managed = false,
    this.inkColor = const Color(0xFFFFFFFF),
    required super.child,
  });
  final Object identity;
  final double pixelRatio;
  final int rank;
  final LyricPlainPrepared? prepared;
  final bool managed;
  final Color inkColor;
  @override
  RenderLyricPlainRaster createRenderObject(BuildContext context) =>
      RenderLyricPlainRaster(identity, pixelRatio, rank)..configure(
        identity,
        pixelRatio,
        rank,
        prepared: prepared,
        managed: managed,
        color: inkColor,
      );
  @override
  void updateRenderObject(
    BuildContext context,
    RenderLyricPlainRaster renderObject,
  ) => renderObject.configure(
    identity,
    pixelRatio,
    rank,
    prepared: prepared,
    managed: managed,
    color: inkColor,
  );
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
  LyricPlainPrepared? _prepared;
  bool _managed = false;
  Color _color = const Color(0xFFFFFFFF);
  int debugLayoutCount = 0;

  ui.Image? get debugImage => _managed
      ? hasSize && _prepared?.sourceFor(_color, size) != null
            ? _prepared?.imageFor(_color)
            : null
      : _image;
  ui.Image? get debugRetainedImage => _prepared?.image ?? _image;
  @override
  int get rasterDemand => _failed ? 0 : _pixels;
  @override
  int get rasterRank => _rank * 2;
  @override
  int get rasterSequence => _sequence;
  @override
  bool get rasterReserved => _job != null;

  void configure(
    Object identity,
    double dpr,
    int rank, {
    LyricPlainPrepared? prepared,
    bool managed = false,
    Color color = const Color(0xFFFFFFFF),
  }) {
    if (_prepared != prepared) {
      _prepared?.removeListener(markNeedsPaint);
      _prepared = prepared;
      if (attached) _prepared?.addListener(markNeedsPaint);
      markNeedsPaint();
    }
    if (_managed != managed || _color != color) {
      _managed = managed;
      _color = color;
      markNeedsPaint();
    }
    if (_identity != identity || _dpr != dpr) {
      _discard();
      _identity = identity;
      _dpr = dpr;
      _failed = false;
      // Paragraph metric changes propagate layout themselves. A paint-only
      // colour change must never force the wrapper to lay out the row again.
      markNeedsPaint();
      _updateDemand();
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
    _prepared?.addListener(markNeedsPaint);
    _sequence = LyricRasterPool.register(this);
    _updateDemand();
  }

  @override
  void detach() {
    LyricRasterPool.unregister(this);
    _prepared?.removeListener(markNeedsPaint);
    _discard();
    super.detach();
  }

  @override
  void performLayout() {
    assert(() {
      debugLayoutCount++;
      return true;
    }());
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
        !_managed &&
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
    if (_managed) {
      final prepared = _prepared;
      final image = prepared?.imageFor(_color);
      final source = prepared?.sourceFor(_color, size);
      if (image != null && source != null) {
        debugLyricPlainRasterPaints++;
        context.canvas.drawImageRect(
          image,
          source,
          Rect.fromLTWH(
            offset.dx - _padding,
            offset.dy - _padding,
            source.width / _dpr,
            source.height / _dpr,
          ),
          _paint,
        );
      } else {
        debugLyricPlainNativePaints++;
        super.paint(context, offset);
      }
      return;
    }
    final image = _image;
    if (image == null) {
      debugLyricPlainNativePaints++;
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
    _prepared?.removeListener(markNeedsPaint);
    _prepared = null;
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
