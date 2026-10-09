import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../services/interaction_performance_controller.dart';

part 'home_tab_controller.dart';
part 'home_tab_scene.dart';

const homeTabTransitionDuration = Duration(milliseconds: 300);
const homeTabTransitionCurve = Curves.easeOutCubic;

/// Lazy endpoint-only navigation. Visited pages retain State; only source and
/// destination participate in navigation layout/paint, never intermediate tabs.
class HomePagePreparationPlaceholder extends StatelessWidget {
  const HomePagePreparationPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );
}

class HomeTabViewport extends StatefulWidget {
  const HomeTabViewport({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
    required this.onPageChanged,
    this.scrollEnabled = true,
    this.progressiveWarmup = false,
    this.preparePage,
    this.loadingBuilder,
  }) : assert(itemCount > 0);
  final HomeTabController controller;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int> onPageChanged;
  final bool scrollEnabled;
  final bool progressiveWarmup;
  final Future<void> Function(int index)? preparePage;
  final IndexedWidgetBuilder? loadingBuilder;
  @override
  State<HomeTabViewport> createState() => _HomeTabViewportState();
}

class _HomeTabViewportState extends State<HomeTabViewport>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion;
  final Set<int> _visited = {};
  final Set<int> _prepared = {};
  final Set<int> _dataReady = {};
  final Set<int> _preparing = {};
  final Map<int, Object> _preparationErrors = {};
  int? _warming;
  bool _warmLoopRunning = false;
  bool _foreground = true;
  late int _current;
  int? _source, _destination;
  double _direction = 1;
  int _revision = 0;
  _HomeTabRequest? _active, _pending;
  bool _dragging = false;
  double _dragDistance = 0, _dragExtent = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _motion = AnimationController(vsync: this);
    _current = widget.controller.index.clamp(0, widget.itemCount - 1);
    _visited.add(_current);
    _prepared.add(_current);
    _dataReady.add(_current);
    widget.controller._attach(this, _current);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleWarmup());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _scheduleWarmup();
  }

  void _scheduleWarmup() {
    if (!mounted || !widget.progressiveWarmup || _warmLoopRunning) return;
    _warmLoopRunning = true;
    unawaited(_warmPages());
  }

  void _startPagePreparation(int index) {
    if (_dataReady.contains(index) ||
        _preparationErrors.containsKey(index) ||
        !_preparing.add(index)) {
      return;
    }
    unawaited(() async {
      try {
        await widget.preparePage?.call(index);
        if (mounted) _dataReady.add(index);
      } catch (error, stack) {
        if (mounted) setState(() => _preparationErrors[index] = error);
        debugPrint('Home page preparation failed: $error\n$stack');
      } finally {
        _preparing.remove(index);
        if (mounted) _scheduleWarmup();
      }
    }());
  }

  Future<void> _warmPages() async {
    final work = InteractionPerformanceController.instance;
    try {
      while (mounted && _prepared.length < widget.itemCount) {
        final lease = await work.acquireIdleWork(
          priority: _prepared.contains(widget.controller.targetIndex)
              ? InteractionWorkPriority.maintenance
              : InteractionWorkPriority.userVisible,
          priorityForWork: () =>
              _prepared.contains(widget.controller.targetIndex)
              ? InteractionWorkPriority.maintenance
              : InteractionWorkPriority.userVisible,
          isStillNeeded: () => mounted,
        );
        try {
          if (!mounted || !lease.isGranted) return;
          if (!_foreground || ModalRoute.of(context)?.isCurrent == false) {
            return;
          }
          if (_dragging || _source != null) {
            lease.release();
            await Future<void>.delayed(const Duration(milliseconds: 120));
            continue;
          }
          final preferred = widget.controller.targetIndex;
          final candidates = [
            preferred,
            for (var i = 0; i < widget.itemCount; i++)
              if (i != preferred) i,
          ].where((i) => !_prepared.contains(i)).toList();
          lease.release();
          // A slow group/search request must not hold up unrelated pages.
          for (final index in candidates) {
            _startPagePreparation(index);
          }
          // Let immediately completed preparation publish its readiness.
          await Future<void>.value();
          final ready = candidates.where(_dataReady.contains).toList();
          if (ready.isEmpty) return; // Completion schedules another pass.
          final mountLease = await work.acquireIdleWork(
            priority: !_prepared.contains(widget.controller.targetIndex)
                ? InteractionWorkPriority.userVisible
                : InteractionWorkPriority.maintenance,
            priorityForWork: () =>
                _prepared.contains(widget.controller.targetIndex)
                ? InteractionWorkPriority.maintenance
                : InteractionWorkPriority.userVisible,
            isStillNeeded: () => mounted,
          );
          try {
            if (!mounted || !mountLease.isGranted) return;
            if (_dragging ||
                !_foreground ||
                _source != null ||
                work.isCritical ||
                ModalRoute.of(context)?.isCurrent == false) {
              continue;
            }
            // The requested target may have changed while acquiring the lease.
            final target = widget.controller.targetIndex;
            final index = ready.contains(target) ? target : ready.first;
            setState(() {
              _visited.add(index);
              _prepared.add(index);
              _warming = index;
            });
            await WidgetsBinding.instance.endOfFrame;
            if (!mounted) return;
            setState(() => _warming = null);
          } finally {
            mountLease.release();
          }
        } finally {
          lease.release();
        }
      }
    } finally {
      _warmLoopRunning = false;
    }
  }

  @override
  void didUpdateWidget(covariant HomeTabViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _cancelRequests();
      oldWidget.controller._detach(this);
      _source = _destination = null;
      _current = widget.controller.index.clamp(0, widget.itemCount - 1);
      _visited.add(_current);
      widget.controller._attach(this, _current);
    }
    if (oldWidget.itemCount != widget.itemCount ||
        _current >= widget.itemCount ||
        (_destination != null && _destination! >= widget.itemCount)) {
      _snap(_current.clamp(0, widget.itemCount - 1));
    }
    _visited.removeWhere((index) => index >= widget.itemCount);
    _prepared.removeWhere((index) => index >= widget.itemCount);
    _scheduleWarmup();
    if (!widget.scrollEnabled && _dragging) _snap(_current);
  }

  void _validate(int index) {
    if (index < 0 || index >= widget.itemCount) {
      throw RangeError.range(index, 0, widget.itemCount - 1, 'index');
    }
  }

  Future<void> _navigate(int index, Duration duration, Curve curve) {
    _validate(index);
    _dragging = false;
    final request = _HomeTabRequest(index, duration, curve);
    if (_source == null) {
      _begin(request);
    } else if (index == _source || index == _destination) {
      // Reversal keeps both current transforms, without snapping a page.
      _pending?.complete();
      _pending = null;
      _active?.complete();
      _active = request;
      widget.controller._report(_current, index, true);
      _drive(request, index == _source ? 0 : 1);
    } else {
      // A third destination cannot replace a half-visible page. Coalesce to
      // the latest request, then start it when this two-page scene settles.
      _pending?.complete();
      _pending = request;
      widget.controller._report(_current, index, true);
    }
    return request.done.future;
  }

  void _begin(_HomeTabRequest request) {
    if (request.index == _current) {
      widget.controller._report(_current, _current, false);
      request.complete();
      return;
    }
    final rtl = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    _motion.value = 0;
    final revision = ++_revision;
    setState(() {
      _source = _current;
      _destination = request.index;
      _direction = (request.index > _current ? 1 : -1) * rtl.toDouble();
      _visited.add(request.index);
      _active = request;
    });
    widget.controller._report(_current, request.index, true);
    // Prepare the destination at the edge for one frame before moving it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && revision == _revision) _drive(request, 1);
    });
  }

  void _drive(_HomeTabRequest request, double end) {
    final revision = ++_revision;
    widget.onPageChanged(request.index);
    unawaited(() async {
      try {
        await _motion
            .animateTo(end, duration: request.duration, curve: request.curve)
            .orCancel;
      } on TickerCanceled {
        return;
      }
      if (!mounted || revision != _revision) return;
      final next = end == 0 ? _source! : _destination!;
      final pending = _pending;
      _pending = null;
      setState(() {
        _current = next;
        _source = _destination = null;
        _active = null;
      });
      widget.controller._report(next, pending?.index ?? next, pending != null);
      request.complete();
      _scheduleWarmup();
      if (pending != null) _begin(pending);
    }());
  }

  void _cancelRequests() {
    _revision++;
    _motion.stop();
    _active?.complete();
    _pending?.complete();
    _active = _pending = null;
    _dragging = false;
  }

  void _snap(int index) {
    _validate(index);
    _cancelRequests();
    setState(() {
      _current = index;
      _source = _destination = null;
      _visited.add(index);
    });
    widget.controller._report(index, index, false);
    widget.onPageChanged(index);
    _scheduleWarmup();
  }

  void _dragStart(DragStartDetails details) {
    if (_source != null) return;
    if (widget.progressiveWarmup) {
      InteractionPerformanceController.instance.pulse(
        InteractionPhase.interacting,
      );
    }
    _dragging = true;
    _dragDistance = 0;
    _dragExtent = (context.findRenderObject()! as RenderBox).size.width;
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (!_dragging || _dragExtent <= 0) return;
    if (widget.progressiveWarmup) {
      InteractionPerformanceController.instance.pulse(
        InteractionPhase.interacting,
      );
    }
    _dragDistance += details.delta.dx;
    final rtl = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    final logical = _dragDistance * rtl;
    final index = _current + (logical < 0 ? 1 : -1);
    if (index < 0 || index >= widget.itemCount) {
      _motion.value = 0;
      return;
    }
    if (_destination != index) {
      setState(() {
        _source = _current;
        _destination = index;
        _direction = logical < 0 ? rtl.toDouble() : -rtl.toDouble();
        _visited.add(index);
      });
      widget.controller._report(_current, index, true);
    }
    _motion.value = (_dragDistance.abs() / _dragExtent).clamp(0.0, 1.0);
  }

  void _dragEnd(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;
    if (_source == null) return;
    final forwardVelocity = -details.velocity.pixelsPerSecond.dx * _direction;
    final commit = _motion.value >= .25 || forwardVelocity > 500;
    final request = _HomeTabRequest(
      commit ? _destination! : _source!,
      homeTabTransitionDuration,
      homeTabTransitionCurve,
    );
    _active = request;
    widget.controller._report(_current, request.index, true);
    _drive(request, commit ? 1 : 0);
  }

  void _dragCancel() {
    if (!_dragging) return;
    _dragging = false;
    if (_source == null) return;
    final request = _HomeTabRequest(
      _source!,
      homeTabTransitionDuration,
      homeTabTransitionCurve,
    );
    _active = request;
    widget.controller._report(_current, request.index, true);
    _drive(request, 0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelRequests();
    widget.controller._detach(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    clipBehavior: Clip.hardEdge,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: widget.scrollEnabled ? _dragStart : null,
      onHorizontalDragUpdate: widget.scrollEnabled ? _dragUpdate : null,
      onHorizontalDragEnd: widget.scrollEnabled ? _dragEnd : null,
      onHorizontalDragCancel: widget.scrollEnabled ? _dragCancel : null,
      child: _HomeTabScene(
        motion: _motion,
        source: _source ?? _current,
        destination: _destination,
        direction: _direction,
        warming: _warming,
        children: [
          for (final index in _visited)
            _HomePageSlot(
              key: ValueKey('home-page-$index'),
              index: index,
              child: TickerMode(
                enabled:
                    index == (_source ?? _current) || index == _destination,
                child: ExcludeFocus(
                  excluding:
                      index != (_source ?? _current) && index != _destination,
                  child: RepaintBoundary(
                    child:
                        !widget.progressiveWarmup || _prepared.contains(index)
                        ? widget.itemBuilder(context, index)
                        : _preparationErrors.containsKey(index)
                        ? Center(
                            child: TextButton(
                              onPressed: () {
                                setState(
                                  () => _preparationErrors.remove(index),
                                );
                                _scheduleWarmup();
                              },
                              child: const Text('加载失败，点击重试'),
                            ),
                          )
                        : widget.loadingBuilder?.call(context, index) ??
                              const SizedBox.expand(
                                key: ValueKey('home-preparing'),
                              ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
