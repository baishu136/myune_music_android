import 'package:flutter/material.dart';
import 'lyric_shared_focus.dart';

/// Flutter replaces the curve before sampling a running tween. A dense lyric
/// retarget can therefore change the displayed value without elapsed time.
/// Freeze every tween using the OLD curve first, then start the new segment
/// from that value. Also rephase an unchanged target if it is still in flight.
/// This runs only on widget updates, not on animation frames.
mixin LyricPhaseRetarget<T extends ImplicitlyAnimatedWidget>
    on ImplicitlyAnimatedWidgetState<T> {
  LyricSharedFocus? _sharedPhase;
  int _sharedGeneration = -1;
  bool get rebuildOnSharedPhase => false;
  void sharedPhaseChanged() {}
  @override
  Animation<double> get animation => _sharedPhase ?? super.animation;

  void _sharedChanged() {
    final phase = _sharedPhase!;
    if (_sharedGeneration != phase.generation) {
      final old = AlwaysStoppedAnimation(phase.previousValue);
      forEachTween((tween, target, constructor) {
        if (tween != null) {
          tween
            ..begin = tween.evaluate(old)
            ..end = target;
        }
        return tween;
      });
      _sharedGeneration = phase.generation;
    }
    sharedPhaseChanged();
    if (rebuildOnSharedPhase && mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = LyricSharedFocusScope.of(context);
    if (next == _sharedPhase) return;
    final previous = animation.value;
    forEachTween((tween, target, constructor) {
      if (tween != null) {
        tween.begin = tween.evaluate(AlwaysStoppedAnimation(previous));
      }
      return tween;
    });
    _sharedPhase?.removeListener(_sharedChanged);
    _sharedPhase = next;
    _sharedGeneration = next?.generation ?? -1;
    next?.addListener(_sharedChanged);
    if (next != null) {
      controller.stop();
    } else {
      controller.forward(from: 0);
    }
    didUpdateTweens();
  }

  @override
  void dispose() {
    _sharedPhase?.removeListener(_sharedChanged);
    super.dispose();
  }

  bool get preserveLyricPhase => true;
  // Hidden entry preparation and explicit seeks use exact target poses.
  // Duration.zero alone cannot finish a tween whose TickerMode is muted.
  bool get snapLyricPhase => false;

  @override
  void didUpdateWidget(covariant T oldWidget) {
    if (_sharedPhase == null &&
        preserveLyricPhase &&
        !snapLyricPhase &&
        (oldWidget.curve != widget.curve ||
            oldWidget.duration != widget.duration)) {
      final previousAnimation = animation;
      forEachTween((tween, target, constructor) {
        if (tween != null) {
          final displayed = tween.evaluate(previousAnimation);
          tween
            ..begin = displayed
            ..end = displayed;
        }
        return tween;
      });
    }
    super.didUpdateWidget(oldWidget);
    if (_sharedPhase != null) controller.stop();
    if (snapLyricPhase) {
      forEachTween((tween, target, constructor) {
        if (target == null) return null;
        return (tween ?? constructor(target))
          ..begin = target
          ..end = target;
      });
      controller.stop();
      controller.value = 1;
      didUpdateTweens();
    }
  }
}

/// The original focus spread, with the same phase safety as scale/opacity.
class LyricPhaseSlide extends AnimatedSlide {
  const LyricPhaseSlide({
    super.key,
    required super.offset,
    required super.duration,
    super.curve,
    super.onEnd,
    super.child,
    this.snapToTarget = false,
  });
  final bool snapToTarget;

  @override
  ImplicitlyAnimatedWidgetState<AnimatedSlide> createState() =>
      _LyricPhaseSlideState();
}

class _LyricPhaseSlideState extends ImplicitlyAnimatedWidgetState<AnimatedSlide>
    with LyricPhaseRetarget<AnimatedSlide> {
  @override
  bool get snapLyricPhase => (widget as LyricPhaseSlide).snapToTarget;
  Tween<Offset>? _offset;
  late Animation<Offset> _value;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _offset =
        visitor(
              _offset,
              widget.offset,
              (value) => Tween<Offset>(begin: value as Offset),
            )
            as Tween<Offset>?;
  }

  @override
  void didUpdateTweens() => _value = animation.drive(_offset!);

  @override
  Widget build(BuildContext context) =>
      SlideTransition(position: _value, child: widget.child);
}

/// Retain Flutter's render-layer ScaleTransition and stable child subtree.
class LyricPhaseScale extends AnimatedScale {
  const LyricPhaseScale({
    super.key,
    required super.scale,
    required super.duration,
    super.curve,
    super.alignment,
    super.filterQuality,
    super.onEnd,
    super.child,
    this.preservePhase = true,
    this.snapToTarget = false,
  });

  final bool preservePhase;
  final bool snapToTarget;

  @override
  ImplicitlyAnimatedWidgetState<AnimatedScale> createState() =>
      _LyricPhaseScaleState();
}

class _LyricPhaseScaleState extends ImplicitlyAnimatedWidgetState<AnimatedScale>
    with LyricPhaseRetarget<AnimatedScale> {
  Tween<double>? _scale;
  late Animation<double> _value;
  @override
  bool get preserveLyricPhase => (widget as LyricPhaseScale).preservePhase;
  @override
  bool get snapLyricPhase => (widget as LyricPhaseScale).snapToTarget;
  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _scale =
        visitor(
              _scale,
              widget.scale,
              (value) => Tween<double>(begin: value as double),
            )
            as Tween<double>?;
  }

  @override
  void didUpdateTweens() => _value = animation.drive(_scale!);
  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: _value,
    alignment: widget.alignment,
    filterQuality: widget.filterQuality,
    child: widget.child,
  );
}

class LyricPhaseOpacity extends AnimatedOpacity {
  const LyricPhaseOpacity({
    super.key,
    required super.opacity,
    required super.duration,
    super.curve,
    super.child,
    super.alwaysIncludeSemantics,
    super.onEnd,
    this.preservePhase = true,
    this.snapToTarget = false,
  });
  final bool preservePhase;
  final bool snapToTarget;
  @override
  ImplicitlyAnimatedWidgetState<AnimatedOpacity> createState() =>
      _LyricPhaseOpacityState();
}

class _LyricPhaseOpacityState
    extends ImplicitlyAnimatedWidgetState<AnimatedOpacity>
    with LyricPhaseRetarget<AnimatedOpacity> {
  Tween<double>? _opacity;
  late Animation<double> _value;
  @override
  bool get preserveLyricPhase => (widget as LyricPhaseOpacity).preservePhase;
  @override
  bool get snapLyricPhase => (widget as LyricPhaseOpacity).snapToTarget;
  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _opacity =
        visitor(
              _opacity,
              widget.opacity,
              (value) => Tween<double>(begin: value as double),
            )
            as Tween<double>?;
  }

  @override
  void didUpdateTweens() => _value = animation.drive(_opacity!);
  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _value,
    alwaysIncludeSemantics: widget.alwaysIncludeSemantics,
    child: widget.child,
  );
}

class LyricPhaseTextStyle extends AnimatedDefaultTextStyle {
  const LyricPhaseTextStyle({
    super.key,
    required super.style,
    required super.duration,
    required super.child,
    super.curve,
    super.textAlign,
    super.softWrap,
    super.overflow,
    super.maxLines,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.onEnd,
    this.preservePhase = true,
    this.snapToTarget = false,
  });
  final bool preservePhase;
  final bool snapToTarget;
  @override
  AnimatedWidgetBaseState<AnimatedDefaultTextStyle> createState() =>
      _LyricPhaseTextStyleState();
}

class _LyricPhaseTextStyleState
    extends AnimatedWidgetBaseState<AnimatedDefaultTextStyle>
    with LyricPhaseRetarget<AnimatedDefaultTextStyle> {
  TextStyleTween? _style;
  @override
  bool get rebuildOnSharedPhase => true;
  @override
  bool get preserveLyricPhase => (widget as LyricPhaseTextStyle).preservePhase;
  @override
  bool get snapLyricPhase => (widget as LyricPhaseTextStyle).snapToTarget;
  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _style =
        visitor(
              _style,
              widget.style,
              (value) => TextStyleTween(begin: value as TextStyle),
            )
            as TextStyleTween?;
  }

  @override
  Widget build(BuildContext context) => DefaultTextStyle(
    style: _style!.evaluate(animation),
    textAlign: widget.textAlign,
    softWrap: widget.softWrap,
    overflow: widget.overflow,
    maxLines: widget.maxLines,
    textWidthBasis: widget.textWidthBasis,
    textHeightBehavior: widget.textHeightBehavior,
    child: widget.child,
  );
}
