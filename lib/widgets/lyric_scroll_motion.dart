import 'dart:math' as math;

/// A continuously running, retargetable spring for lyric-list offsets.
///
/// Updating [target] never clears [velocity], so rapid lyric changes preserve
/// both positional and velocity continuity instead of restarting a separate
/// `animateTo` operation for every line.
class LyricScrollMotion {
  LyricScrollMotion({this.dampingRatio = .90, this.frequency = 11});

  final double dampingRatio;
  final double frequency;

  double offset = 0;
  double target = 0;
  double velocity = 0;
  double viewportExtent = 1;

  bool get isSettled =>
      (target - offset).abs() < .35 && velocity.abs() < 4.0;

  void sync(
    double value, {
    bool resetVelocity = true,
    double? viewportExtent,
  }) {
    offset = value;
    target = value;
    if (resetVelocity) velocity = 0;
    if (viewportExtent != null && viewportExtent > 0) {
      this.viewportExtent = viewportExtent;
    }
  }

  void retarget(double value, {double? viewportExtent}) {
    target = value;
    if (viewportExtent != null && viewportExtent > 0) {
      this.viewportExtent = viewportExtent;
    }
  }

  /// Advances the spring by [elapsedSeconds] and returns its new offset.
  ///
  /// Large frame gaps are divided into small integration steps to avoid an
  /// unstable leap after the application resumes or the UI thread stalls.
  double advance(double elapsedSeconds) {
    if (elapsedSeconds <= 0 || isSettled) {
      if (isSettled) {
        offset = target;
        velocity = 0;
      }
      return offset;
    }

    var remaining = elapsedSeconds.clamp(0.0, .05);
    const maxStep = 1 / 120;
    final stiffness = frequency * frequency;
    final damping = 2 * dampingRatio * frequency;

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

    if (isSettled) {
      offset = target;
      velocity = 0;
    }
    return offset;
  }
}
