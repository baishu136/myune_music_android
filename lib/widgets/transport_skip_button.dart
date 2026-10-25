import 'dart:async';
import 'package:flutter/material.dart';
import 'playback_interaction_guard.dart';

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
  }

  Future<void> _skip() async {
    if (_busy || !mounted) return;
    if (!_guard.allows) {
      _stop();
      return;
    }
    _busy = true;
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
    unawaited(_skip());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _guard.updateContext(context);
  }

  @override
  void dispose() {
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
        child: IconButton(icon: Icon(widget.icon, size: 38), onPressed: _skip),
      ),
    ),
  );
}
