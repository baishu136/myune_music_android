import 'package:flutter/material.dart';

const nowPlayingCoverGlowDuration = Duration(milliseconds: 720);

/// Only the halo animates. The cover/Hero retain their elements and pixels.
class NowPlayingCoverGlow extends StatefulWidget {
  const NowPlayingCoverGlow({
    super.key,
    required this.enabled,
    required this.child,
    this.entranceComplete = true,
    this.coverTransition,
    this.pageEntrance,
    this.waitForImage = false,
  });

  final bool enabled, entranceComplete, waitForImage;
  final Animation<double>? coverTransition;
  final Animation<double>? pageEntrance;
  final Widget child;

  static void reportImageReady(BuildContext context, bool ready) {
    context.getInheritedWidgetOfExactType<_GlowImageScope>()?.report(ready);
  }

  @override
  State<NowPlayingCoverGlow> createState() => _NowPlayingCoverGlowState();
}

class _NowPlayingCoverGlowState extends State<NowPlayingCoverGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: nowPlayingCoverGlowDuration,
  );
  late bool _imageReady = !widget.waitForImage;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    widget.coverTransition?.addListener(_sync);
    widget.coverTransition?.addStatusListener(_status);
    widget.pageEntrance?.addListener(_sync);
    widget.pageEntrance?.addStatusListener(_status);
  }

  void _status(AnimationStatus status) => _sync();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant NowPlayingCoverGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverTransition != widget.coverTransition) {
      oldWidget.coverTransition?.removeListener(_sync);
      oldWidget.coverTransition?.removeStatusListener(_status);
      widget.coverTransition?.addListener(_sync);
      widget.coverTransition?.addStatusListener(_status);
    }
    if (oldWidget.waitForImage != widget.waitForImage) {
      _imageReady = !widget.waitForImage;
    }
    if (oldWidget.pageEntrance != widget.pageEntrance) {
      oldWidget.pageEntrance?.removeListener(_sync);
      oldWidget.pageEntrance?.removeStatusListener(_status);
      widget.pageEntrance?.addListener(_sync);
      widget.pageEntrance?.addStatusListener(_status);
    }
    _sync();
  }

  void _report(bool ready) {
    if (!mounted || _imageReady == ready) return;
    _imageReady = ready;
    _sync();
  }

  void _sync() {
    final transition = widget.coverTransition;
    final ready =
        widget.enabled &&
        widget.entranceComplete &&
        (widget.pageEntrance == null ||
            (!widget.pageEntrance!.isAnimating &&
                widget.pageEntrance!.value == 1)) &&
        (transition == null ||
            (!transition.isAnimating && transition.value == 0));
    if (!ready) {
      _ready = false;
      _controller.stop();
      _controller.value = 0;
    } else if (!_ready && _imageReady) {
      _ready = true;
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    widget.coverTransition?.removeListener(_sync);
    widget.coverTransition?.removeStatusListener(_status);
    widget.pageEntrance?.removeListener(_sync);
    widget.pageEntrance?.removeStatusListener(_status);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: _GlowImageScope(report: _report, child: widget.child),
    builder: (context, child) => DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: widget.enabled
            ? [
                BoxShadow(
                  color: Colors.white.withValues(
                    alpha:
                        .20 *
                        Curves.easeInOutCubic.transform(_controller.value),
                  ),
                  blurRadius: 10,
                  spreadRadius: 0,
                  blurStyle: BlurStyle.outer,
                ),
              ]
            : const [],
      ),
      child: child,
    ),
  );
}

class _GlowImageScope extends InheritedWidget {
  const _GlowImageScope({required this.report, required super.child});
  final ValueChanged<bool> report;
  @override
  bool updateShouldNotify(_GlowImageScope oldWidget) => false;
}
