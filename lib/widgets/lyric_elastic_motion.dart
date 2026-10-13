import 'package:flutter/animation.dart';
import 'lyric_normalized_motion.dart';

enum LyricElasticRole { departing, arriving, surrounding }

double _bell(double t, double start, double end) {
  final u = ((t - start) / (end - start)).clamp(0.0, 1.0);
  final b = u * (1 - u);
  return 64 * b * b * b;
}

/// A finite correction above the unchanged list path. No delay or second
/// full-distance spring; C2 wave endpoints and bounded, single mild rebound.
double lyricElasticWave(double t, LyricElasticRole role) => switch (role) {
  LyricElasticRole.departing => _bell(t, 0, .68) - .24 * _bell(t, .68, 1),
  LyricElasticRole.arriving => -.65 * _bell(t, .40, 1),
  LyricElasticRole.surrounding => _bell(t, 0, .66) - .22 * _bell(t, .66, 1),
};

class LyricElasticSegment {
  LyricElasticSegment({
    required this.amplitude,
    required this.role,
    this.initialOffset = 0,
    this.initialVelocity = 0,
    this.seconds = .68,
  });
  final double amplitude, initialOffset, initialVelocity, seconds;
  final LyricElasticRole role;
  double value(double elapsed) {
    final t = (elapsed / seconds).clamp(0.0, 1.0), q = 1 - t;
    final smooth = t * t * t * (t * (t * 6 - 15) + 10);
    return initialOffset * (1 - smooth) +
        initialVelocity * seconds * t * q * q * q +
        amplitude * lyricElasticWave(t, role);
  }

  double velocity(double elapsed) {
    // Analytical derivative: no frame integration or sampling drift.
    final t = (elapsed / seconds).clamp(0.0, 1.0), q = 1 - t;
    double derivative(double a, double b) {
      final u = (t - a) / (b - a);
      if (u <= 0 || u >= 1) return 0;
      return 192 * u * u * (1 - u) * (1 - u) * (1 - 2 * u) / (b - a);
    }

    final wave = switch (role) {
      LyricElasticRole.departing =>
        derivative(0, .68) - .24 * derivative(.68, 1),
      LyricElasticRole.arriving => -.65 * derivative(.40, 1),
      LyricElasticRole.surrounding =>
        derivative(0, .66) - .22 * derivative(.66, 1),
    };
    return (-initialOffset * 30 * t * t * q * q +
            initialVelocity * seconds * q * q * (1 - 4 * t) +
            amplitude * wave) /
        seconds;
  }
}

class LyricElasticRetreatCurve extends Curve {
  const LyricElasticRetreatCurve();
  @override
  double transformInternal(double t) {
    if (t < .76) {
      final u = t / .76;
      // Slow beginning, then accelerate; settle smoothly before the recoil.
      return u * u * u * (u * (u * 6 - 15) + 10);
    }
    return 1 + .055 * _bell(t, .76, 1);
  }
}

class LyricElasticArrivalCurve extends Curve {
  const LyricElasticArrivalCurve();
  @override
  double transformInternal(double t) =>
      lyricTransitionCurve.transform(t) + .045 * _bell(t, .70, 1);
}
