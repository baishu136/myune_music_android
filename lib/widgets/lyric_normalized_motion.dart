import 'package:flutter/animation.dart';

import 'lyric_scroll_motion.dart';

const lyricTransitionDuration = Duration(milliseconds: 420);
const lyricTransitionCurve = LyricTransitionCurve();

/// C2 position envelope: integrate a smoothstep velocity ramp, then its
/// reversed ramp. Rest speed/acceleration and endpoint speed/acceleration are
/// zero; peak speed is at 60ms for a 420ms move. No numerical spring stepping.
/// An in-flight forward retarget blends this envelope with a monotone boundary
/// slope, preserving current velocity without adding a second displacement.
class LyricTransitionCurve extends Curve {
  const LyricTransitionCurve({this.initialSlope = 0})
    : assert(initialSlope >= 0 && initialSlope <= 3);

  final double initialSlope;
  static const _ramp = 1 / 7;

  static double _integral(double u) => u * u * u * (1 - .5 * u);
  static double _smooth(double u) => u * u * (3 - 2 * u);

  @override
  double transformInternal(double t) {
    final base = t <= _ramp
        ? 2 * _ramp * _integral(t / _ramp)
        : 1 - 2 * (1 - _ramp) * _integral((1 - t) / (1 - _ramp));
    final q = 1 - t;
    final blend = initialSlope / 3;
    return base * (1 - blend) + (1 - q * q * q) * blend;
  }

  double derivative(double t) {
    if (t >= 1) return 0;
    final base = 2 * _smooth(t <= _ramp ? t / _ramp : (1 - t) / (1 - _ramp));
    final q = 1 - t;
    final blend = initialSlope / 3;
    return base * (1 - blend) + 3 * q * q * blend;
  }
}

/// Wall-time duration, independent of media playback rate. Long/wrapped rows
/// get up to 60ms extra; cap avoids long settling tails after large moves.
Duration lyricTransitionDurationForDistance(
  double distance, {
  Duration base = lyricTransitionDuration,
}) => Duration(
  microseconds:
      base.inMicroseconds +
      (60000 * ((distance.abs() - 70) / 70).clamp(0.0, 1.0)).round(),
);

/// One normalized, wall-time trajectory for the entire karaoke list.
///
/// Ordinary motion uses [lyricTransitionCurve], lasting 420--480 wall-time ms.
/// Speed ramps smoothly then decreases to exactly zero;
/// neither a spring integration nor a displacement threshold ends the move.
/// Per-frame bounds checks may retarget the same target without restarting.
///
/// A new target during flight reuses the current slope in a monotone envelope
/// segment, avoiding a velocity restart. A very near forward target shortens
/// the segment to keep that slope without overshooting. Farther targets may
/// require acceleration to cover the new distance: this is a redirection,
/// not a restart from zero at every ordinary lyric change.
class LyricNormalizedMotion implements LyricScrollDriver {
  LyricNormalizedMotion({this.duration = lyricTransitionDuration}) {
    if (duration <= Duration.zero) {
      throw RangeError.value(
        duration.inMicroseconds,
        'duration',
        'must be positive',
      );
    }
  }

  final Duration duration;
  @override
  double offset = 0;
  @override
  double target = 0;
  @override
  double velocity = 0;
  double _start = 0;
  double _distance = 0;
  double _elapsed = 0;
  double _seconds = 0;
  LyricTransitionCurve transitionCurve = lyricTransitionCurve;
  Duration transitionDuration = lyricTransitionDuration;
  bool _moving = false;

  @override
  bool get isSettled => !_moving;

  @override
  void sync(double value, {bool resetVelocity = true, double? viewportExtent}) {
    if (!value.isFinite) return;
    offset = target = _start = value;
    _elapsed = _distance = 0;
    _moving = false;
    if (resetVelocity) velocity = 0;
    transitionCurve = lyricTransitionCurve;
    transitionDuration = Duration.zero;
  }

  @override
  void retarget(
    double value, {
    double? viewportExtent,
    bool launchFromRest = false,
  }) {
    if (!value.isFinite || (value - target).abs() < 1e-9) return;
    final distance = value - offset;
    if (distance.abs() < 1e-9) {
      sync(value);
      return;
    }
    transitionDuration = lyricTransitionDurationForDistance(
      distance,
      base: duration,
    );
    var seconds =
        transitionDuration.inMicroseconds / Duration.microsecondsPerSecond;
    var slope = 0.0;
    if (_moving && velocity * distance > 0) {
      slope = velocity * seconds / distance;
      if (slope > 3) {
        seconds = 3 * distance / velocity;
        slope = 3;
        transitionDuration = Duration(
          microseconds: (seconds * 1000000).round(),
        );
      }
    }
    _start = offset;
    target = value;
    _distance = distance;
    _seconds = seconds;
    transitionCurve = slope == 0
        ? lyricTransitionCurve
        : LyricTransitionCurve(initialSlope: slope);
    _elapsed = 0;
    _moving = true;
    velocity = _distance * slope / _seconds;
  }

  @override
  double advance(double elapsedSeconds) {
    if (!_moving || !elapsedSeconds.isFinite || elapsedSeconds <= 0) {
      return offset;
    }
    _elapsed += elapsedSeconds;
    if (_elapsed >= _seconds - 1e-12) {
      offset = target;
      velocity = 0;
      _moving = false;
      return offset;
    }
    final t = _elapsed / _seconds;
    final progress = transitionCurve.transform(t);
    final derivative = transitionCurve.derivative(t);
    offset = _start + _distance * progress;
    velocity = _distance * derivative / _seconds;
    return offset;
  }
}
