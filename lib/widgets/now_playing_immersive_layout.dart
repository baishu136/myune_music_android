import 'package:flutter/material.dart';

/// One mounted visual surface; only the surrounding chrome collapses/fades.
/// Tapping the lyrics to return to artwork is still handled by that surface.
class NowPlayingImmersiveLayout extends StatefulWidget {
  const NowPlayingImmersiveLayout({
    super.key,
    required this.immersive,
    required this.header,
    required this.visual,
    required this.controls,
    this.tablet = false,
    this.split = false,
    this.stableLandscapeCanvas = false,
    this.landscapeFooter,
  });

  static const transitionDuration = Duration(milliseconds: 280);
  final bool immersive;
  final Widget header;
  final Widget visual;
  final Widget controls;
  final bool tablet;
  final bool split;
  final bool stableLandscapeCanvas;
  final Widget? landscapeFooter;

  @override
  State<NowPlayingImmersiveLayout> createState() => _ImmersiveLayoutState();
}

class _ImmersiveLayoutState extends State<NowPlayingImmersiveLayout>
    with SingleTickerProviderStateMixin {
  final _visualKey = GlobalKey();
  final _controlsKey = GlobalKey();
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: NowPlayingImmersiveLayout.transitionDuration,
    value: widget.immersive ? 0 : 1,
  );
  late final CurvedAnimation _visibility = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = widget.immersive ? 0 : 1;
    }
  }

  @override
  void didUpdateWidget(covariant NowPlayingImmersiveLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.immersive != widget.immersive) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = widget.immersive ? 0 : 1;
      } else {
        widget.immersive ? _controller.reverse() : _controller.forward();
      }
    }
  }

  @override
  void dispose() {
    _visibility.dispose();
    _controller.dispose();
    super.dispose();
  }

  Widget _chrome(Widget child, {Axis axis = Axis.vertical}) => IgnorePointer(
    ignoring: widget.immersive,
    child: ExcludeSemantics(
      excluding: widget.immersive,
      child: SizeTransition(
        sizeFactor: _visibility,
        axis: axis,
        alignment: Alignment.topLeft,
        child: FadeTransition(opacity: _visibility, child: child),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final visual = KeyedSubtree(key: _visualKey, child: widget.visual);
    final controls = KeyedSubtree(key: _controlsKey, child: widget.controls);
    if (widget.split) {
      return _ChromeMotionScope(
        visibility: _visibility,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: LayoutBuilder(
                builder: (context, constraints) => AnimatedBuilder(
                  animation: _visibility,
                  builder: (context, child) => Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _chrome(child!, axis: Axis.horizontal),
                      SizedBox(width: 24 * _visibility.value),
                      Expanded(
                        child: ClipRect(
                          clipBehavior: widget.stableLandscapeCanvas
                              ? Clip.none
                              : Clip.hardEdge,
                          child: OverflowBox(
                            alignment: Alignment.centerRight,
                            minWidth:
                                (widget.immersive ||
                                    widget.stableLandscapeCanvas)
                                ? constraints.maxWidth
                                : (constraints.maxWidth - 24) * .57,
                            maxWidth:
                                (widget.immersive ||
                                    widget.stableLandscapeCanvas)
                                ? constraints.maxWidth
                                : (constraints.maxWidth - 24) * .57,
                            minHeight: constraints.maxHeight,
                            maxHeight: constraints.maxHeight,
                            child: visual,
                          ),
                        ),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: (constraints.maxWidth - 24) * .43,
                    height: constraints.maxHeight,
                    child: Column(
                      children: [
                        SizedBox(height: 48, child: widget.header),
                        Expanded(
                          child: SingleChildScrollView(
                            reverse: false,
                            key: const PageStorageKey(
                              'landscape-playback-controls',
                            ),
                            child: controls,
                          ),
                        ),
                        if (widget.landscapeFooter != null)
                          widget.landscapeFooter!,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return _ChromeMotionScope(
      visibility: _visibility,
      child: Column(
        children: [
          _chrome(SizedBox(height: kToolbarHeight, child: widget.header)),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    children: [
                      Expanded(child: visual),
                      _chrome(
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [const SizedBox(height: 16), controls],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChromeMotionScope extends InheritedWidget {
  const _ChromeMotionScope({required this.visibility, required super.child});
  final Animation<double> visibility;
  @override
  bool updateShouldNotify(_ChromeMotionScope oldWidget) =>
      visibility != oldWidget.visibility;
}

/// Individual foreground controls share the layout clock, with slight offsets.
class NowPlayingChromeFade extends StatelessWidget {
  const NowPlayingChromeFade({
    super.key,
    required this.order,
    required this.child,
  });
  final int order;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final animation = context
        .dependOnInheritedWidgetOfExactType<_ChromeMotionScope>()
        ?.visibility;
    if (animation == null) return child;
    final delay = (order * .025).clamp(0.0, .2);
    return FadeTransition(
      key: ValueKey('immersive-control-fade-$order'),
      opacity: animation.drive(
        CurveTween(curve: Interval(delay, .8 + delay, curve: Curves.easeInOut)),
      ),
      child: child,
    );
  }
}
