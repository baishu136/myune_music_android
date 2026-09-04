import 'dart:async';

/// Coordinates work that is safe to postpone while the user is actively
/// scrolling or while a page transition is producing frames.
///
/// This controller deliberately has no UI listeners: reporting interaction
/// activity must not itself cause a widget rebuild.
enum InteractionPhase { idle, interacting, fling, transition }

enum InteractionWorkPriority {
  currentVisual,
  userVisible,
  background,
  maintenance,
}

class InteractionWorkLease {
  InteractionWorkLease._(this._onRelease);

  final void Function() _onRelease;
  bool _released = false;

  bool get isGranted => !_released;

  void release() {
    if (_released) return;
    _released = true;
    _onRelease();
  }
}

class _InteractionWorkRequest {
  _InteractionWorkRequest(this.priority, this.sequence, this.isStillNeeded);

  final InteractionWorkPriority priority;
  final int sequence;
  final bool Function()? isStillNeeded;
  final Completer<InteractionWorkLease> completer =
      Completer<InteractionWorkLease>();
}

class InteractionPerformanceController {
  InteractionPerformanceController._();

  static final InteractionPerformanceController instance =
      InteractionPerformanceController._();

  final Stopwatch _clock = Stopwatch()..start();
  final Set<Completer<void>> _idleWaiters = {};
  final List<_InteractionWorkRequest> _workQueue = [];
  Timer? _settlePoll;
  Timer? _workDrainTimer;
  InteractionPhase _phase = InteractionPhase.idle;
  int _lastPulseMicros = 0;
  int _settleAfterMicros = 0;
  int _workSequence = 0;
  bool _workLeaseActive = false;

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
    _workDrainTimer?.cancel();
    _workDrainTimer = null;
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

  /// Grants expensive, deferrable work one lease at a time after interaction
  /// has settled. Releasing leases one frame apart prevents artwork, palette,
  /// lyric and maintenance tasks from all starting on the transition's final
  /// frame.
  Future<InteractionWorkLease> acquireIdleWork({
    InteractionWorkPriority priority = InteractionWorkPriority.background,
    bool Function()? isStillNeeded,
  }) {
    final request = _InteractionWorkRequest(
      priority,
      _workSequence++,
      isStillNeeded,
    );
    _workQueue.add(request);
    _scheduleWorkDrain(Duration.zero);
    return request.completer.future;
  }

  void _scheduleWorkDrain(Duration delay) {
    if (_workLeaseActive || _workQueue.isEmpty || isCritical) return;
    _workDrainTimer ??= Timer(delay, () {
      _workDrainTimer = null;
      _drainWorkQueue();
    });
  }

  void _drainWorkQueue() {
    if (_workLeaseActive || _workQueue.isEmpty || isCritical) return;
    _workQueue.sort((first, second) {
      final priority = first.priority.index.compareTo(second.priority.index);
      return priority != 0
          ? priority
          : first.sequence.compareTo(second.sequence);
    });
    var request = _workQueue.removeAt(0);
    while (request.isStillNeeded?.call() == false) {
      final cancelledLease = InteractionWorkLease._(() {})..release();
      request.completer.complete(cancelledLease);
      if (_workQueue.isEmpty) return;
      request = _workQueue.removeAt(0);
    }
    _workLeaseActive = true;
    request.completer.complete(
      InteractionWorkLease._(() {
        if (!_workLeaseActive) return;
        _workLeaseActive = false;
        _scheduleWorkDrain(const Duration(milliseconds: 16));
      }),
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
    _scheduleWorkDrain(Duration.zero);
  }
}
