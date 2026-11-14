import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'home_tab_viewport.dart';
import 'interaction_motion.dart';

double playlistGrowthProgress(double t) {
  final x = t.clamp(0.0, 1.0);
  return 1 - math.pow(1 - x, 4).toDouble();
}

/// One clock for the visible playlist cards. Cached/offscreen children are
/// sampled once at entry, and cards later scrolled into view stay settled.
class PlaylistEntranceMotion extends StatefulWidget {
  const PlaylistEntranceMotion({
    super.key,
    required this.navigation,
    required this.child,
  });
  final HomeTabController navigation;
  final Widget child;

  @override
  State<PlaylistEntranceMotion> createState() => _PlaylistEntranceMotionState();
}

class _PlaylistEntranceMotionState
    extends InteractionMotionState<PlaylistEntranceMotion>
    with SingleTickerProviderStateMixin {
  late final _clock = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(microseconds: 272000),
  );
  final _items = <_PlaylistEntranceItemState>{};
  final _activeItems = <_PlaylistEntranceItemState>{};
  int _target = -1, _revision = 0;
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    _clock.addStatusListener(_status);
    widget.navigation.addListener(_navigate);
    _target = widget.navigation.targetIndex;
    _pending = _target == 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pending && motionAllowed) _schedule();
  }

  @override
  void didUpdateWidget(covariant PlaylistEntranceMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigation != widget.navigation) {
      oldWidget.navigation.removeListener(_navigate);
      widget.navigation.addListener(_navigate);
      _navigate();
    }
  }

  void _navigate() {
    final next = widget.navigation.targetIndex;
    if (next == _target) return;
    _target = next;
    _pending = next == 1;
    if (_pending) {
      _schedule();
    } else {
      resetMotion();
    }
  }

  void _schedule() {
    final revision = ++_revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _revision || !_pending) return;
      if (!motionAllowed || ModalRoute.of(context)?.isCurrent == false) return;
      final visible = _items.where((item) => item.visible).toList()
        ..sort((a, b) => a.widget.index.compareTo(b.widget.index));
      _settleItems();
      for (var i = 0; i < visible.length; i++) {
        visible[i]._setOrder(i);
        _activeItems.add(visible[i]);
      }
      _pending = false;
      _clock.forward(from: 0);
    });
    // Settled items no longer listen to the clock; entry must request its own
    // sampling frame, including when navigation has no attached viewport.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _status(AnimationStatus status) {
    if (status == AnimationStatus.completed) _settleItems();
  }

  void _settleItems() {
    for (final item in _activeItems) {
      item._setOrder(null);
    }
    _activeItems.clear();
  }

  @override
  void resetMotion() {
    _revision++;
    _clock.stop();
    _clock.value = 1;
    _settleItems();
  }

  @override
  void dispose() {
    widget.navigation.removeListener(_navigate);
    _clock.removeStatusListener(_status);
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _PlaylistEntranceScope(state: this, child: widget.child);
}

class _PlaylistEntranceScope extends InheritedWidget {
  const _PlaylistEntranceScope({required this.state, required super.child});
  final _PlaylistEntranceMotionState state;
  @override
  bool updateShouldNotify(_PlaylistEntranceScope oldWidget) =>
      oldWidget.state != state;
}

class PlaylistEntranceItem extends StatefulWidget {
  const PlaylistEntranceItem({
    super.key,
    required this.index,
    required this.child,
  });
  final int index;
  final Widget child;
  @override
  State<PlaylistEntranceItem> createState() => _PlaylistEntranceItemState();
}

class _PlaylistEntranceItemState extends State<PlaylistEntranceItem> {
  _PlaylistEntranceMotionState? _motion;
  int? _order;
  double _delay = 0;
  void _setOrder(int? order) {
    if (!mounted || _order == order) return;
    setState(() {
      _order = order;
      _delay = order == null ? 0 : math.min(order * .055, .36);
    });
  }

  bool get visible {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return false;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport is! RenderBox) return false;
    final viewportBox = viewport as RenderBox;
    if (!viewportBox.hasSize) return false;
    return (box.localToGlobal(Offset.zero, ancestor: viewportBox) & box.size)
        .overlaps(Offset.zero & viewportBox.size);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context
        .dependOnInheritedWidgetOfExactType<_PlaylistEntranceScope>()
        ?.state;
    if (_motion != next) {
      _motion?._items.remove(this);
      _motion?._activeItems.remove(this);
      _order = null;
      _motion = next;
      _motion?._items.add(this);
    }
  }

  @override
  void didUpdateWidget(covariant PlaylistEntranceItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _motion?._activeItems.remove(this);
      _order = null;
    }
  }

  @override
  void dispose() {
    _motion?._items.remove(this);
    _motion?._activeItems.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = _motion;
    if (motion == null) return widget.child;
    return AnimatedBuilder(
      animation: _order == null
          ? const AlwaysStoppedAnimation<double>(1)
          : motion._clock,
      child: widget.child,
      builder: (_, child) {
        final t = _order == null
            ? 1.0
            : ((motion._clock.value - _delay) / (1 - _delay)).clamp(0.0, 1.0);
        final spring = playlistGrowthProgress(t);
        final scale = .40 + .60 * spring;
        // Counterclockwise accent while expanding, then a tiny spring return.
        final angle = -.24 * math.sin(math.pi * spring) * (1 - spring);
        return Transform(
          key: ValueKey('playlist-entrance-${widget.index}'),
          alignment: Alignment.center,
          transformHitTests: false,
          transform: Matrix4.identity()
            ..rotateZ(angle)
            ..scaleByDouble(scale, scale, 1, 1),
          child: child,
        );
      },
    );
  }
}
