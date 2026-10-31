import 'dart:async';
import 'package:flutter/material.dart';
import 'playback_interaction_guard.dart';
import 'interaction_motion.dart';

class TransportSkipButton extends StatefulWidget {
  const TransportSkipButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onSkip,
    this.onHoldStart,
    this.onError,
  });

  final String tooltip;
  final IconData icon;
  final Future<void> Function() onSkip;
  final VoidCallback Function()? onHoldStart;
  final void Function(Object, StackTrace)? onError;

  @override
  State<TransportSkipButton> createState() => _TransportSkipButtonState();
}

class _TransportSkipButtonState extends State<TransportSkipButton> {
  Timer? _repeat;
  bool _busy = false;
  bool _holding = false, _disposing = false;
  int _pulse = 0;
  VoidCallback? _releaseHold;
  late final PlaybackInteractionGuard _guard;

  @override
  void initState() {
    super.initState();
    _guard = PlaybackInteractionGuard(onCancel: _stop);
  }

  void _stop() {
    _repeat?.cancel();
    _repeat = null;
    final release = _releaseHold;
    _releaseHold = null;
    release?.call();
    if (_holding) {
      _holding = false;
      if (mounted && !_disposing) setState(() {});
    }
  }

  Future<void> _skip() async {
    if (_busy || !mounted) return;
    if (!_guard.allows) {
      _stop();
      return;
    }
    _busy = true;
    if (!_holding) setState(() => _pulse++);
    try {
      await widget.onSkip();
    } catch (error, stack) {
      _stop();
      if (!mounted) return;
      if (widget.onError case final report?) {
        report(error, stack);
      } else if (_guard.allows) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('切歌失败，请重试')));
      }
    } finally {
      _busy = false;
    }
  }

  void _start() {
    _stop();
    if (!_guard.allows) return;
    _releaseHold = widget.onHoldStart?.call();
    _repeat = Timer.periodic(const Duration(milliseconds: 600), (_) => _skip());
    setState(() => _holding = true);
    unawaited(_skip());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _guard.updateContext(context);
  }

  @override
  void dispose() {
    _disposing = true;
    _stop();
    _guard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.tooltip,
    triggerMode: TooltipTriggerMode.manual,
    child: Listener(
      onPointerDown: _guard.pointerDown,
      onPointerCancel: (event) {
        _guard.pointerEnd(event);
        _stop();
      },
      onPointerUp: (event) {
        _guard.pointerEnd(event);
        _stop();
      },
      child: GestureDetector(
        onLongPressStart: (_) => _start(),
        onLongPressEnd: (_) => _stop(),
        onLongPressCancel: _stop,
        child: ButtonPressMotion(
          enabled: !_holding,
          child: IconButton(
            icon: ActionMotionIcon(
              trigger: _pulse,
              enabled: !_holding,
              kind: widget.icon == Icons.skip_previous
                  ? IconMotion.previous
                  : IconMotion.next,
              child: Icon(widget.icon, size: 38),
            ),
            onPressed: _skip,
          ),
        ),
      ),
    ),
  );
}
