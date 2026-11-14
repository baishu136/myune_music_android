import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'interaction_motion.dart';
import '../services/interaction_performance_controller.dart';

enum LibraryEntranceStyle { list, indexed }

/// Samples actual laid-out rows once, including partially visible bottom rows.
/// The shell supplies startup intent; the local clock waits for visible rows.
/// Cached and subsequently scrolled rows settle without replaying.
class LibraryEntranceMotion extends StatefulWidget {
  const LibraryEntranceMotion({
    super.key,
    required this.animation,
    required this.child,
  });
  final Animation<double> animation;
  final Widget child;
  @override
  State<LibraryEntranceMotion> createState() => _LibraryEntranceMotionState();
}

class _LibraryEntranceMotionState
    extends InteractionMotionState<LibraryEntranceMotion>
    with SingleTickerProviderStateMixin {
  late final _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );
  bool _requested = false, _scheduled = false;
  InteractionWorkLease? _work;
  final _items = <_LibraryEntranceItemState>{};
  final _active = <_LibraryEntranceItemState>{};
  bool _sampled = false;
  @override
  void initState() {
    super.initState();
    _requested = widget.animation.value > 0;
    _clock.addStatusListener((status) {
      if (status == AnimationStatus.completed) resetMotion();
    });
    widget.animation.addStatusListener(_status);
  }

  @override
  void didUpdateWidget(covariant LibraryEntranceMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeStatusListener(_status);
      widget.animation.addStatusListener(_status);
      _requested = widget.animation.value > 0;
      for (final item in _items) {
        item._setOrder(null);
      }
      _active.clear();
    }
  }

  void _status(AnimationStatus status) {
    if (status == AnimationStatus.forward ||
        status == AnimationStatus.completed) {
      _requested = true;
      _schedule();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  void _schedule() {
    if (!_requested || _sampled || _scheduled || !motionAllowed) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || _sampled || !motionAllowed) return;
      _start();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _start() {
    final visible = _items.where((item) => item.visible).toList()
      ..sort((a, b) => a.widget.order.compareTo(b.widget.order));
    if (visible.isEmpty) return;
    _sampled = true;
    final orders = {for (var i = 0; i < visible.length; i++) visible[i]: i};
    for (final item in _items) {
      final order = motionAllowed ? orders[item] : null;
      item._setOrder(order);
      if (order != null) _active.add(item);
    }
    _work ??= InteractionPerformanceController.instance.beginVisualAnimation();
    _clock.forward(from: 0);
  }

  @override
  void resetMotion() {
    if (!_sampled) return;
    _clock.stop();
    _work?.release();
    _work = null;
    for (final item in _active) {
      item._setOrder(null);
    }
    _active.clear();
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_status);
    _work?.release();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _LibraryEntranceScope(state: this, child: widget.child);
}

class _LibraryEntranceScope extends InheritedWidget {
  const _LibraryEntranceScope({required this.state, required super.child});
  final _LibraryEntranceMotionState state;
  @override
  bool updateShouldNotify(_LibraryEntranceScope oldWidget) =>
      state != oldWidget.state;
}

Widget buildLibrarySongEntranceTransition({
  required Animation<double>? animation,
  required int order,
  required Widget child,
  LibraryEntranceStyle style = LibraryEntranceStyle.list,
}) => animation == null
    ? child
    : LibraryEntranceItem(
        animation: animation,
        order: order,
        style: style,
        child: child,
      );

class LibraryEntranceItem extends StatefulWidget {
  const LibraryEntranceItem({
    super.key,
    required this.animation,
    required this.order,
    required this.style,
    required this.child,
  });
  final Animation<double> animation;
  final int order;
  final LibraryEntranceStyle style;
  final Widget child;
  @override
  State<LibraryEntranceItem> createState() => _LibraryEntranceItemState();
}

class _LibraryEntranceItemState extends State<LibraryEntranceItem> {
  _LibraryEntranceMotionState? _motion;
  int? _order;
  bool get visible {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport is! RenderBox) return false;
    final viewportBox = viewport as RenderBox;
    return viewportBox.hasSize &&
        (box.localToGlobal(Offset.zero, ancestor: viewportBox) & box.size)
            .overlaps(Offset.zero & viewportBox.size);
  }

  void _setOrder(int? order) {
    if (mounted) setState(() => _order = order);
  }

  void _unregister() {
    _motion?._items.remove(this);
    _motion?._active.remove(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context
        .dependOnInheritedWidgetOfExactType<_LibraryEntranceScope>()
        ?.state;
    if (_motion != next) {
      _unregister();
      _motion = next;
      _motion?._items.add(this);
      _motion?._schedule();
      _order = null;
    }
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = _motion == null || !_motion!._sampled ? widget.order : _order;
    final indexed = widget.style == LibraryEntranceStyle.indexed;
    final start = math.min((order ?? 0) * (indexed ? .038 : .055), .38);
    final end = math.min(start + (indexed ? .48 : .58), 1.0);
    final Animation<double> progress =
        order == null || MediaQuery.disableAnimationsOf(context)
        ? const AlwaysStoppedAnimation(1)
        : (_motion?._clock ?? widget.animation).drive(
            CurveTween(
              curve: Interval(start, end, curve: const Cubic(.16, 1, .3, 1)),
            ),
          );
    Widget result = SlideTransition(
      position: progress.drive(
        Tween(begin: Offset(0, indexed ? .10 : .18), end: Offset.zero),
      ),
      child: RepaintBoundary(child: widget.child),
    );
    if (indexed) {
      result = ScaleTransition(
        scale: progress.drive(Tween(begin: .965, end: 1.0)),
        alignment: Alignment.topCenter,
        child: result,
      );
    }
    return FadeTransition(
      key: ValueKey('library-entrance-${widget.order}'),
      opacity: progress,
      child: result,
    );
  }
}
