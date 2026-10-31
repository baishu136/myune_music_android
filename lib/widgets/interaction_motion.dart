import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Motion is local to a control. Losing visibility cancels it instead of
/// catching up with a stale animation when the route/app becomes visible.
abstract class InteractionMotionState<T extends StatefulWidget> extends State<T>
    with WidgetsBindingObserver {
  bool _visible = true, _foreground = true, _reduced = false;
  bool get motionAllowed => _visible && _foreground && !_reduced;
  void resetMotion();

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    // Accessible navigation changes timeouts/focus behaviour; it is not a
    // request to suppress decorative motion. Honour the dedicated flag.
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (!motionAllowed) resetMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!motionAllowed) resetMotion();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Observes pointer feedback without owning tap/long-press recognizers.
/// Layout, semantics, hit targets and callback timing remain with the button.
class ButtonPressMotion extends StatefulWidget {
  const ButtonPressMotion({
    super.key,
    required this.child,
    this.enabled = true,
  });
  final Widget child;
  final bool enabled;
  @override
  State<ButtonPressMotion> createState() => _ButtonPressMotionState();
}

class _ButtonPressMotionState extends InteractionMotionState<ButtonPressMotion>
    with SingleTickerProviderStateMixin {
  late final _press = AnimationController.unbounded(vsync: this);
  final _pointers = <int>{};
  int _pressRevision = 0;
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 520,
    damping: 29,
  );

  @override
  void resetMotion() {
    _pressRevision++;
    _pointers.clear();
    _press.stop();
    if (_press.value != 0) _press.value = 0;
  }

  @override
  void didUpdateWidget(covariant ButtonPressMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) resetMotion();
  }

  void _down(PointerDownEvent event) {
    if (!widget.enabled || !motionAllowed) return;
    if (_pointers.isEmpty) {
      _pressRevision++;
      _press.animateTo(
        1,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOutCubic,
      );
    }
    _pointers.add(event.pointer);
  }

  void _up(PointerEvent event, {bool finishQuickTap = true}) {
    if (!_pointers.remove(event.pointer) || _pointers.isNotEmpty) return;
    if (!motionAllowed || !widget.enabled) {
      resetMotion();
      return;
    }
    if (finishQuickTap && _press.value < .65) {
      // A tap can start and end between two display frames. Its action has
      // already fired; finish a brief visible compression before releasing.
      unawaited(_finishQuickTap(_pressRevision));
    } else {
      _releasePress();
    }
  }

  void _releasePress() {
    if (_press.value.abs() < .001) {
      _press.stop();
      _press.value = 0;
      return;
    }
    _press.animateWith(SpringSimulation(_spring, _press.value, 0, 0));
  }

  Future<void> _finishQuickTap(int revision) async {
    try {
      await _press
          .animateTo(
            1,
            duration: const Duration(milliseconds: 60),
            curve: Curves.easeOutCubic,
          )
          .orCancel;
      if (mounted &&
          revision == _pressRevision &&
          _pointers.isEmpty &&
          motionAllowed &&
          widget.enabled) {
        _releasePress();
      }
    } on TickerCanceled {
      // A new press, backgrounding, hiding or disposal owns the next frame.
    }
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _down,
    onPointerUp: _up,
    onPointerCancel: (event) => _up(event, finishQuickTap: false),
    child: RepaintBoundary(
      child: AnimatedBuilder(
        animation: _press,
        child: widget.child,
        builder: (_, child) {
          final pressure = _press.value.clamp(-.2, 1.0);
          return Transform(
            key: const ValueKey('button-press-transform'),
            alignment: Alignment.center,
            transformHitTests: false,
            transform: Matrix4.diagonal3Values(
              1 - .035 * pressure,
              1 - .045 * pressure,
              1,
            ),
            child: child,
          );
        },
      ),
    ),
  );
}

/// First composition is settled; only a real state change plays one sequence.
class OneShotMotion extends StatefulWidget {
  const OneShotMotion({
    super.key,
    required this.trigger,
    required this.builder,
    this.child,
    this.enabled = true,
    this.restartOnTrigger = true,
    this.duration = const Duration(milliseconds: 420),
  });
  final Object trigger;
  final bool enabled;
  final bool restartOnTrigger;
  final Duration duration;
  final Widget? child;
  final Widget Function(BuildContext, double, Widget?) builder;
  @override
  State<OneShotMotion> createState() => _OneShotMotionState();
}

class _OneShotMotionState extends InteractionMotionState<OneShotMotion>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    value: 1,
    duration: widget.duration,
    animationBehavior: AnimationBehavior.preserve,
  );
  @override
  void resetMotion() {
    _controller.stop();
    if (_controller.value != 1) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant OneShotMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    if (!motionAllowed || !widget.enabled) {
      resetMotion();
    } else if (oldWidget.trigger != widget.trigger &&
        (widget.restartOnTrigger || !_controller.isAnimating)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) =>
          widget.builder(context, _controller.value, child),
    ),
  );
}

enum IconMotion {
  library,
  playlist,
  artist,
  album,
  settings,
  heart,
  mode,
  next,
  previous,
}

Duration iconMotionDuration(IconMotion kind) => Duration(
  milliseconds: switch (kind) {
    IconMotion.album => 600,
    IconMotion.settings => 460,
    IconMotion.heart => 400,
    IconMotion.mode => 340,
    IconMotion.next || IconMotion.previous => 280,
    _ => 440,
  },
);

typedef IconMotionPose = ({
  double x,
  double y,
  double scaleX,
  double scaleY,
  double angle,
});
const _restPose = (x: 0.0, y: 0.0, scaleX: 1.0, scaleY: 1.0, angle: 0.0);

/// A decisive accent followed by a small, slower counter-movement. Both value
/// and velocity settle at the ends; delayed parts share the original ticker.
double iconMotionAccent(double phase, {double delay = 0}) {
  final t = ((phase - delay) / (1 - delay)).clamp(0.0, 1.0);
  if (t <= 0 || t >= 1) return 0;
  double smooth(double x) => x * x * (3 - 2 * x);
  if (t < .28) return smooth(t / .28);
  if (t < .64) return 1 - 1.12 * smooth((t - .28) / .36);
  return -.12 * (1 - smooth((t - .64) / .36));
}

IconMotionPose iconMotionPose(
  IconMotion kind,
  double phase, {
  bool active = true,
}) {
  if (phase <= 0 || phase >= 1) return _restPose;
  final strength = active ? 1.0 : .35;
  final bump = iconMotionAccent(phase) * strength;
  final heart = kind == IconMotion.heart
      ? (.84 * iconMotionAccent(phase * 1.65) +
                .24 * iconMotionAccent((phase - .34) / .66)) *
            strength
      : 0.0;
  return switch (kind) {
    IconMotion.library => (
      x: 0.0,
      y: -1.1 * bump,
      scaleX: 1 + .012 * bump,
      scaleY: 1 + .012 * bump,
      angle: 0.0,
    ),
    IconMotion.playlist => (
      x: 0.0,
      y: -.35 * bump,
      scaleX: 1.0,
      scaleY: 1.0,
      angle: 0.0,
    ),
    IconMotion.artist => (
      x: 0.0,
      y: -.3 * bump,
      scaleX: 1.0,
      scaleY: 1.0,
      angle: 0.0,
    ),
    IconMotion.album => (
      x: 0.0,
      y: 0.0,
      scaleX: 1 + .025 * bump,
      scaleY: 1 + .025 * bump,
      angle: 0.0,
    ),
    IconMotion.settings => (
      x: 0.0,
      y: 0.0,
      scaleX: 1 + .018 * bump,
      scaleY: 1 + .018 * bump,
      angle: 0.0,
    ),
    IconMotion.heart => (
      x: 0.0,
      y: -.6 * heart,
      scaleX: 1 + .16 * heart,
      scaleY: 1 + .16 * heart,
      angle: -.035 * heart,
    ),
    IconMotion.mode => (
      x: 0.0,
      y: 0.0,
      scaleX: 1 - .025 * bump,
      scaleY: 1 - .025 * bump,
      angle: .21 * bump,
    ),
    IconMotion.next => (
      x: 4.0 * bump,
      y: 0.0,
      scaleX: 1 - .05 * bump,
      scaleY: 1.0,
      angle: 0.0,
    ),
    IconMotion.previous => (
      x: -4.0 * bump,
      y: 0.0,
      scaleX: 1 - .05 * bump,
      scaleY: 1.0,
      angle: 0.0,
    ),
  };
}

Widget buildIconMotion(
  IconMotion kind,
  double phase,
  Widget child, {
  bool active = true,
}) {
  final pose = iconMotionPose(kind, phase, active: active);
  return Transform(
    key: ValueKey('icon-motion-${kind.name}'),
    alignment: Alignment.center,
    transformHitTests: false,
    transform: Matrix4.identity()
      ..translateByDouble(pose.x, pose.y, 0, 1)
      ..rotateZ(pose.angle)
      ..scaleByDouble(pose.scaleX, pose.scaleY, 1, 1),
    child: child,
  );
}

class ActionMotionIcon extends StatelessWidget {
  const ActionMotionIcon({
    super.key,
    required this.trigger,
    required this.kind,
    required this.child,
    this.active = true,
    this.enabled = true,
  });
  final Object trigger;
  final IconMotion kind;
  final Widget child;
  final bool active, enabled;
  @override
  Widget build(BuildContext context) => OneShotMotion(
    trigger: trigger,
    enabled: enabled,
    duration: iconMotionDuration(kind),
    child: child,
    builder: (_, phase, child) =>
        buildIconMotion(kind, phase, child!, active: active),
  );
}
