import 'dart:async';

/// Coordinates work that is safe to postpone while the user is actively
/// scrolling or while a page transition is producing frames.
///
/// This controller deliberately has no UI listeners: reporting interaction
/// activity must not itself cause a widget rebuild.
enum InteractionPhase { idle, interacting, fling, transition }

class InteractionPerformanceController {
  InteractionPerformanceController._();

  static final InteractionPerformanceController instance =
      InteractionPerformanceController._();

  final Stopwatch _clock = Stopwatch()..start();
  final Set<Completer<void>> _idleWaiters = {};
  Timer? _settlePoll;
  InteractionPhase _phase = InteractionPhase.idle;
  int _lastPulseMicros = 0;
  int _settleAfterMicros = 0;

  InteractionPhase get phase => _phase;
  bool get isCritical => _phase != InteractionPhase.idle;

  void pulse(
    InteractionPhase phase, {
    Duration settleAfter = const Duration(milliseconds: 160),
  }) {
    if (phase == InteractionPhase.idle) {
      _setIdle();
      return;
    }
    _phase = phase;
    _lastPulseMicros = _clock.elapsedMicroseconds;
    _settleAfterMicros = settleAfter.inMicroseconds;
    _settlePoll ??= Timer.periodic(
      const Duration(milliseconds: 48),
      (_) => _pollForIdle(),
    );
  }

  Future<void> waitForIdle({
    Duration maxWait = const Duration(milliseconds: 400),
  }) {
    if (!isCritical) return Future<void>.value();
    final completer = Completer<void>();
    _idleWaiters.add(completer);
    return completer.future.timeout(
      maxWait,
      onTimeout: () {
        _idleWaiters.remove(completer);
      },
    );
  }

  void _pollForIdle() {
    if (_clock.elapsedMicroseconds - _lastPulseMicros < _settleAfterMicros) {
      return;
    }
    _setIdle();
  }

  void _setIdle() {
    _phase = InteractionPhase.idle;
    _settlePoll?.cancel();
    _settlePoll = null;
    final waiters = _idleWaiters.toList(growable: false);
    _idleWaiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }
}
