import 'dart:async';
import 'package:flutter/widgets.dart';

/// Invalidates an in-flight gesture when its surface loses visibility/focus.
/// Resuming permits a new press, never a completion from the previous press.
class PlaybackInteractionGuard with WidgetsBindingObserver {
  PlaybackInteractionGuard({required this.onCancel}) {
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }
  final VoidCallback onCancel;
  final _pointers = <int>{};
  bool _foreground = true, _visible = true, _disposed = false;
  int _generation = 0, _sequence = 0;
  int? _pointerGeneration;
  BuildContext? _context;

  bool get allows =>
      !_disposed &&
      _foreground &&
      _visible &&
      (_context?.mounted ?? false) &&
      TickerMode.valuesOf(_context!).enabled &&
      (ModalRoute.of(_context!)?.isCurrent ?? true) &&
      (_pointerGeneration == null || _pointerGeneration == _generation);

  void updateContext(BuildContext context) {
    _context = context;
    final next =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    final lost = _visible && !next;
    _visible = next;
    if (lost) cancel();
  }

  void pointerDown(PointerDownEvent event) {
    if (_pointers.isEmpty) {
      _sequence++;
      _pointerGeneration = _generation;
    }
    _pointers.add(event.pointer);
  }

  void pointerEnd(PointerEvent event) {
    _pointers.remove(event.pointer);
    final sequence = _sequence;
    // Gesture recognizers process this pointer-up before the microtask. Keep
    // its generation until then, while keyboard/semantics actions stay usable.
    scheduleMicrotask(() {
      if (!_disposed && _sequence == sequence && _pointers.isEmpty) {
        _pointerGeneration = null;
      }
    });
  }

  void cancel() {
    if (_disposed) return;
    _generation++;
    _sequence++;
    _pointers.clear();
    onCancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) cancel();
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _pointers.clear();
    _context = null;
  }
}
