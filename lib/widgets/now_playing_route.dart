import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'optional_shader_mask.dart';

double pageMotionSmooth(double t) {
  final x = t.clamp(0.0, 1.0);
  return x * x * x * (10 + x * (-15 + 6 * x));
}

double pageEdgeOpacity(double progress, double fraction) =>
    1 - (1 - pageMotionSmooth(progress)) * (1 - pageMotionSmooth(fraction));

/// Stable-width C2 feather, sampled only in paint. The settled child keeps its
/// Element and bypasses the shader layer. No widget rebuild on animation ticks.
class PageEdgeDissolve extends SingleChildRenderObjectWidget {
  const PageEdgeDissolve({
    super.key,
    required this.progress,
    this.fromRight = false,
    this.edgeResolver,
    super.child,
  });
  final Animation<double> progress;
  final bool fromRight;
  final bool Function()? edgeResolver;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderPageEdgeDissolve(progress, fromRight, edgeResolver);
  @override
  void updateRenderObject(
    BuildContext context,
    RenderPageEdgeDissolve renderObject,
  ) => renderObject.configure(progress, fromRight, edgeResolver);
}

class RenderPageEdgeDissolve extends RenderOptionalShaderMask {
  RenderPageEdgeDissolve(this._progress, this._fromRight, this._edgeResolver)
    : super(
        active: _progress.value < 1,
        shaderCallback: _opaque,
        blendMode: BlendMode.dstIn,
      ) {
    shaderCallback = _shader;
  }
  Animation<double> _progress;
  bool _fromRight;
  bool Function()? _edgeResolver;
  Rect? _cachedBounds;
  double? _cachedProgress;
  bool? _cachedRight;
  ui.Shader? _cachedShader;
  static ui.Shader _opaque(Rect bounds) => ui.Gradient.linear(
    bounds.topLeft,
    bounds.topRight,
    const [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
  );
  void configure(
    Animation<double> progress,
    bool fromRight,
    bool Function()? resolver,
  ) {
    if (_progress != progress) {
      if (attached) _progress.removeListener(_tick);
      _progress = progress;
      if (attached) _progress.addListener(_tick);
    }
    _fromRight = fromRight;
    _edgeResolver = resolver;
    _tick();
  }

  void _tick() {
    final moving = _progress.value >= 0 && _progress.value < 1;
    active = moving;
    if (!moving) _cachedShader = null;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(_tick);
  }

  @override
  void detach() {
    _progress.removeListener(_tick);
    super.detach();
  }

  ui.Shader _shader(Rect bounds) {
    final p = _progress.value.clamp(0.0, 1.0);
    final right = _edgeResolver?.call() ?? _fromRight;
    if (_cachedShader != null &&
        _cachedBounds == bounds &&
        _cachedProgress == p &&
        _cachedRight == right) {
      return _cachedShader!;
    }
    _cachedBounds = bounds;
    _cachedProgress = p;
    _cachedRight = right;
    final width =
        (bounds.width * .18).clamp(32.0, 88.0) *
        (1 - .35 * pageMotionSmooth(p));
    final near = right ? bounds.topRight : bounds.topLeft;
    return _cachedShader = ui.Gradient.linear(
      near,
      near + Offset(right ? -width : width, 0),
      [
        for (var i = 0; i <= 8; i++)
          Color.from(
            alpha: pageEdgeOpacity(p, i / 8),
            red: 1,
            green: 1,
            blue: 1,
          ),
      ],
      const [0, .125, .25, .375, .5, .625, .75, .875, 1],
    );
  }
}

class _NowPlayingSurface extends StatelessWidget {
  const _NowPlayingSurface({
    required this.progress,
    required this.child,
    required this.secondary,
    required this.fromRight,
  });
  final Animation<double> progress, secondary;
  final Widget child;
  final bool fromRight;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return ScaleTransition(
      key: const ValueKey('player-secondary-scale'),
      scale: secondary.drive(Tween(begin: 1.0, end: .965)),
      child: ScaleTransition(
        key: const ValueKey('player-entry-scale'),
        scale: progress.drive(Tween(begin: 1.035, end: 1.0)),
        child: PageEdgeDissolve(
          key: const ValueKey('player-left-edge-dissolve'),
          progress: progress,
          fromRight: fromRight,
          child: RepaintBoundary(child: child),
        ),
      ),
    );
  }
}

/// Player-only depth and feather; Cupertino owns sliding, Hero and back gestures.
class NowPlayingRoute extends CupertinoPageRoute<void> {
  NowPlayingRoute({required super.builder, super.allowSnapshotting});
  @override
  Duration get transitionDuration => const Duration(milliseconds: 620);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 460);
  @override
  DelegatedTransitionBuilder get delegatedTransition => _underlay;
  static Widget _underlay(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondary,
    bool snapshotting,
    Widget? child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return child ?? const SizedBox.shrink();
    }
    return ScaleTransition(
      key: const ValueKey('player-home-scale'),
      scale: secondary
          .drive(CurveTween(curve: Curves.easeInOutCubic))
          .drive(Tween(begin: 1.0, end: .965)),
      child: CupertinoPageTransition.delegatedTransition(
        context,
        animation,
        secondary,
        snapshotting,
        child,
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    if (fullscreenDialog) {
      return super.buildTransitions(
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    return super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      _NowPlayingSurface(
        progress: animation.drive(CurveTween(curve: Curves.easeInOutCubic)),
        secondary: secondaryAnimation.drive(
          CurveTween(curve: Curves.easeInOutCubic),
        ),
        fromRight: Directionality.of(context) == TextDirection.rtl,
        child: child,
      ),
    );
  }
}
