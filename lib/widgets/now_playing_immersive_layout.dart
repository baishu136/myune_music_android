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
  });

  static const transitionDuration = Duration(milliseconds: 280);
  final bool immersive;
  final Widget header;
  final Widget visual;
  final Widget controls;
  final bool tablet;
  final bool split;

  @override
  State<NowPlayingImmersiveLayout> createState() => _ImmersiveLayoutState();
}

class _ImmersiveLayoutState extends State<NowPlayingImmersiveLayout>
    with SingleTickerProviderStateMixin {
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
  void didUpdateWidget(covariant NowPlayingImmersiveLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.immersive != widget.immersive) {
      widget.immersive ? _controller.reverse() : _controller.forward();
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
  Widget build(BuildContext context) => Column(
    children: [
      _chrome(SizedBox(height: kToolbarHeight, child: widget.header)),
      Expanded(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                widget.tablet ? 28 : 16,
                widget.tablet ? 20 : 8,
                widget.tablet ? 28 : 16,
                widget.tablet ? 22 : 12,
              ),
              child: widget.split
                  ? LayoutBuilder(
                      builder: (context, constraints) => AnimatedBuilder(
                        animation: _visibility,
                        builder: (context, child) => Row(
                          children: [
                            Expanded(child: widget.visual),
                            SizedBox(width: 32 * _visibility.value),
                            _chrome(child!, axis: Axis.horizontal),
                          ],
                        ),
                        // Preserve the normal 6:5 ratio without mounting a
                        // second fullscreen visual or changing its element.
                        child: SizedBox(
                          width: (constraints.maxWidth - 32) * 5 / 11,
                          child: widget.controls,
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        Expanded(child: widget.visual),
                        _chrome(
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 16),
                              widget.controls,
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    ],
  );
}
