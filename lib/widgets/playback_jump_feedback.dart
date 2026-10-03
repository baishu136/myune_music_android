import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Local feedback for an explicit seek, NOT an artificial playback delay.
/// The caller ends pending on decoder position acknowledgement, failure, a new
/// gesture or a song change. A short minimum display avoids a one-frame flash.
class PlaybackJumpFeedback extends StatefulWidget {
  const PlaybackJumpFeedback({super.key, required this.pending});
  final ValueListenable<bool> pending;
  @override
  State<PlaybackJumpFeedback> createState() => _PlaybackJumpFeedbackState();
}

class _PlaybackJumpFeedbackState extends State<PlaybackJumpFeedback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _visibility = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );
  Timer? _minimum;
  bool _minimumElapsed = true;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _visibility.addStatusListener(_status);
    widget.pending.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(covariant PlaybackJumpFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pending != widget.pending) {
      oldWidget.pending.removeListener(_sync);
      widget.pending.addListener(_sync);
      _sync();
    }
  }

  void _sync() {
    if (widget.pending.value) {
      _minimum?.cancel();
      _minimumElapsed = false;
      _minimum = Timer(const Duration(milliseconds: 200), () {
        _minimumElapsed = true;
        if (!widget.pending.value) _visibility.reverse();
      });
      _visibility.forward();
    } else if (_minimumElapsed) {
      _visibility.reverse();
    }
  }

  void _status(AnimationStatus status) {
    final visible = status != AnimationStatus.dismissed;
    if (_visible != visible) setState(() => _visible = visible);
  }

  @override
  void dispose() {
    widget.pending.removeListener(_sync);
    _minimum?.cancel();
    _visibility.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: TickerMode(
      enabled: _visible,
      child: RepaintBoundary(
        child: FadeTransition(
          opacity: _visibility,
          // Only this small indicator paints; never fade or relayout the lyrics.
          child: const Align(
            alignment: Alignment(0, .72),
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ),
    ),
  );
}
