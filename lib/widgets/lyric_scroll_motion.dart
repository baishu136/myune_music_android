import 'dart:math' as math;

/// Shared list-offset contract. Karaoke and ordinary lyrics select one driver;
/// they never sum two independent vertical trajectories.
abstract interface class LyricScrollDriver {
  double get offset;
  set offset(double value);
  double get target;
  double get velocity;
  set velocity(double value);
  bool get isSettled;
  void sync(double value, {bool resetVelocity = true, double? viewportExtent});
  void retarget(
    double value, {
    double? viewportExtent,
    bool launchFromRest = false,
  });
  double advance(double elapsedSeconds);
}

/// A continuously running, retargetable spring for lyric-list offsets.
///
/// Updating [target] never clears [velocity], so rapid lyric changes preserve
/// both positional and velocity continuity instead of restarting a separate
/// `animateTo` operation for every line.
class LyricScrollMotion implements LyricScrollDriver {
  LyricScrollMotion({this.dampingRatio = .92, this.frequency = 8});

  double dampingRatio;
  double frequency;

  @override
  double offset = 0;
  @override
  double target = 0;
  @override
  double velocity = 0;
  double viewportExtent = 1;
  double? _tailStart;
  double _tailVelocity = 0, _tailElapsed = 0;
  static const _tailSeconds = .08;

  void updateDynamics({required double frequency, double? dampingRatio}) {
    if (!frequency.isFinite || frequency <= 0) return;
    this.frequency = frequency;
    if (dampingRatio != null && dampingRatio.isFinite && dampingRatio > 0) {
      this.dampingRatio = dampingRatio;
    }
  }

  @override
  bool get isSettled => offset == target && velocity == 0;

  @override
  void sync(double value, {bool resetVelocity = true, double? viewportExtent}) {
    _tailStart = null;
    offset = value;
    target = value;
    if (resetVelocity) velocity = 0;
    if (viewportExtent != null && viewportExtent > 0) {
      this.viewportExtent = viewportExtent;
    }
  }

  @override
  void retarget(
    double value, {
    double? viewportExtent,
    bool launchFromRest = false,
  }) {
    if (value != target) _tailStart = null;
    target = value;
    if (viewportExtent != null && viewportExtent > 0) {
      this.viewportExtent = viewportExtent;
    }
    // Keep launchFromRest source-compatible, but never inject velocity. The
    // spring accelerates from rest, and a mid-flight retarget inherits speed.
    // At .92/8 the dominant (95%) travel takes ~520 ms; the tiny tail settles
    // naturally. Neither 520 ms nor the next lyric boundary cuts it short.
  }

  /// Advances the spring by [elapsedSeconds] and returns its new offset.
  ///
  /// Large frame gaps are divided into small integration steps to avoid an
  /// unstable leap after the application resumes or the UI thread stalls.
  @override
  double advance(double elapsedSeconds) {
    if (elapsedSeconds <= 0 || !elapsedSeconds.isFinite || isSettled) {
      return offset;
    }
    if (_tailStart != null ||
        ((target - offset).abs() < .35 && velocity.abs() < 1.2)) {
      return _advanceTail(elapsedSeconds);
    }
    // Analytic solutions remain stable across delayed frames. Discarding the
    // time after 50ms made the list visibly lag behind its wall-time trajectory.
    final elapsed = elapsedSeconds;
    final stiffness = frequency * frequency;
    final damping = 2 * dampingRatio * frequency;

    // Keep the critical-damping solution for callers that select it. The
    // production karaoke list uses the .92 underdamped solution below. Both
    // analytic branches cost one update per vsync, without integration bias.
    if ((dampingRatio - 1).abs() < .0001) {
      final displacement = offset - target;
      final coefficient = velocity + frequency * displacement;
      final decay = math.exp(-frequency * elapsed);
      offset = target + (displacement + coefficient * elapsed) * decay;
      velocity = (velocity - frequency * coefficient * elapsed) * decay;
      return offset;
    }

    if (dampingRatio > 0 && dampingRatio < 1) {
      // Closed-form damped spring: identical motion at 60/90/120 Hz, retaining
      // offset and velocity when retargeted. No Euler-integration timestep bias.
      final displacement = offset - target;
      final decayRate = dampingRatio * frequency;
      final dampedFrequency =
          frequency * math.sqrt(1 - dampingRatio * dampingRatio);
      final phase = dampedFrequency * elapsed;
      final coefficient =
          (velocity + decayRate * displacement) / dampedFrequency;
      final cosine = math.cos(phase);
      final sine = math.sin(phase);
      final decay = math.exp(-decayRate * elapsed);
      final wave = displacement * cosine + coefficient * sine;
      offset = target + decay * wave;
      velocity =
          decay *
          (-decayRate * wave +
              dampedFrequency * (-displacement * sine + coefficient * cosine));
      return offset;
    }

    var remaining = elapsed.clamp(0.0, .05);
    const maxStep = 1 / 120;

    while (remaining > 0) {
      final dt = math.min(remaining, maxStep);
      final distance = target - offset;
      final acceleration = stiffness * distance - damping * velocity;
      velocity += acceleration * dt;

      final farTarget = distance.abs() > viewportExtent * 2.5;
      final velocityLimit = viewportExtent * (farTarget ? 12.0 : 5.5);
      velocity = velocity.clamp(-velocityLimit, velocityLimit);
      offset += velocity * dt;
      remaining -= dt;
    }

    return offset;
  }

  // Join the former .35px snap with a short C1 tail. No new ticker, layout,
  // numerical integration, or prolonged asymptotic settling is needed.
  double _advanceTail(double seconds) {
    if (_tailStart == null) {
      _tailStart = offset;
      _tailVelocity = velocity;
      _tailElapsed = 0;
    }
    _tailElapsed += seconds;
    if (_tailElapsed >= _tailSeconds) {
      offset = target;
      velocity = 0;
      _tailStart = null;
      return offset;
    }
    final t = _tailElapsed / _tailSeconds;
    final distance = _tailStart! - target;
    final slope = _tailVelocity * _tailSeconds;
    offset =
        target +
        (2 * t * t * t - 3 * t * t + 1) * distance +
        (t * t * t - 2 * t * t + t) * slope;
    velocity =
        ((6 * t * t - 6 * t) * distance + (3 * t * t - 4 * t + 1) * slope) /
        _tailSeconds;
    return offset;
  }
}
