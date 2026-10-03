import 'package:flutter/material.dart';

/// Fullscreen lyrics only. A horizontal gesture competes normally with the
/// child's vertical scroll; it never observes raw pointer-up as a song change.
/// Fade the ONE retained lyric surface out before changing media, then back in.
/// No second live lyric list, screenshot readback, or per-song image cache.
class LyricsSongSwipeTransition extends StatefulWidget {
  const LyricsSongSwipeTransition({
    super.key,
    required this.enabled,
    required this.songIdentity,
    required this.onNext,
    required this.onPrevious,
    required this.child,
    this.onSwipeStart,
    this.onError,
  });
  final bool enabled;
  final Object songIdentity;
  final Future<void> Function() onNext;
  final Future<void> Function() onPrevious;
  final VoidCallback? onSwipeStart;
  final void Function(Object error, StackTrace stack)? onError;
  final Widget child;
  @override
  State<LyricsSongSwipeTransition> createState() => _LyricsSongSwipeState();
}

class _LyricsSongSwipeState extends State<LyricsSongSwipeTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 220),
  );
  bool _switching = false, _entering = false, _multiTouch = false;
  int _generation = 0, _pointers = 0;
  double _distance = 0, _direction = -1;

  @override
  void didUpdateWidget(covariant LyricsSongSwipeTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _generation++;
      _controller.stop();
      _controller.value = 1;
      _switching = false;
      _distance = 0;
    } else if (oldWidget.songIdentity != widget.songIdentity && !_switching) {
      _entering = true;
      _controller.forward(from: 0);
    }
  }

  Future<void> _switchSong(bool next) async {
    if (_switching || !widget.enabled) return;
    final generation = ++_generation;
    setState(() {
      _switching = true;
      _entering = false;
      _direction = next ? -1 : 1;
    });
    try {
      await _controller
          .animateTo(
            0,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeInCubic,
          )
          .orCancel;
      if (!mounted || generation != _generation || !widget.enabled) return;
      await (next ? widget.onNext() : widget.onPrevious());
    } on TickerCanceled {
      return;
    } catch (error, stack) {
      if (mounted && generation == _generation) {
        if (widget.onError case final report?) {
          report(error, stack);
        } else {
          FlutterError.reportError(
            FlutterErrorDetails(exception: error, stack: stack),
          );
        }
      }
    } finally {
      // Errors still restore the current content; player error notifications
      // are handled by the caller. No stale completion can hide a newer page.
      if (mounted && generation == _generation) {
        setState(() => _entering = true);
        _controller
            .animateTo(1, curve: Curves.easeOutCubic)
            .whenCompleteOrCancel(() {
              if (mounted && generation == _generation) {
                setState(() => _switching = false);
              }
            });
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) {
      _pointers++;
      if (_pointers > 1) _multiTouch = true;
    },
    onPointerUp: (_) {
      if (_pointers > 0) _pointers--;
    },
    onPointerCancel: (_) {
      if (_pointers > 0) _pointers--;
    },
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: !widget.enabled || _switching
          ? null
          : (_) {
              _distance = 0;
              _multiTouch = _pointers > 1;
              widget.onSwipeStart?.call();
            },
      onHorizontalDragUpdate: !widget.enabled || _switching
          ? null
          : (event) {
              _distance += event.primaryDelta ?? 0;
            },
      onHorizontalDragEnd: !widget.enabled || _switching
          ? null
          : (event) {
              final speed = event.primaryVelocity ?? 0;
              if (!_multiTouch &&
                  (_distance.abs() >= 64 ||
                      (_distance.abs() >= 24 && speed.abs() >= 650))) {
                _switchSong(_distance < 0);
              }
              _distance = 0;
            },
      onHorizontalDragCancel: !widget.enabled || _switching
          ? null
          : () => _distance = 0,
      child: IgnorePointer(
        ignoring: _switching,
        child: AnimatedBuilder(
          animation: _controller,
          child: RepaintBoundary(child: widget.child),
          builder: (context, child) => FadeTransition(
            key: const ValueKey('lyrics_song_handoff'),
            opacity: _controller,
            child: Transform.translate(
              offset: Offset(
                (_entering ? -_direction : _direction) *
                    20 *
                    (1 - _controller.value),
                0,
              ),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}
