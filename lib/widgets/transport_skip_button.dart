import 'dart:async';
import 'package:flutter/material.dart';

class TransportSkipButton extends StatefulWidget {
  const TransportSkipButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onSkip,
    this.onHoldStart,
  });

  final String tooltip;
  final IconData icon;
  final Future<void> Function() onSkip;
  final VoidCallback Function()? onHoldStart;

  @override
  State<TransportSkipButton> createState() => _TransportSkipButtonState();
}

class _TransportSkipButtonState extends State<TransportSkipButton>
    with WidgetsBindingObserver {
  Timer? _repeat;
  bool _busy = false;
  VoidCallback? _releaseHold;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
      _stop();
      return;
    }
    _busy = true;
    try {
      await widget.onSkip();
    } finally {
      _busy = false;
    }
  }

  void _start() {
    _stop();
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    _releaseHold = widget.onHoldStart?.call();
    unawaited(_skip());
    _repeat = Timer.periodic(
      const Duration(milliseconds: 600),
      (_) => _skip(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled) _stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _stop();
  }

  @override
  void dispose() {
    _stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.tooltip,
    triggerMode: TooltipTriggerMode.manual,
    child: Listener(
      onPointerCancel: (_) => _stop(),
      onPointerUp: (_) => _stop(),
      child: GestureDetector(
        onLongPressStart: (_) => _start(),
        onLongPressEnd: (_) => _stop(),
        onLongPressCancel: _stop,
        child: IconButton(icon: Icon(widget.icon, size: 38), onPressed: _skip),
      ),
    ),
  );
}
