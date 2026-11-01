import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/fluid_background_state.dart';
import 'fluid_colour_motion.dart';

// The colour interpolation's normalized derivative is 16*p²*(1-p)².
// Include its changing phase rate, so a slowly changing pigment also slows
// down. Find the shared peak once, never integrate or scan on animation ticks.
double _colourActivity(double time, int field) {
  final u = fluidColourPhase(time * fluidShaderTimeScale, field) * 2 / math.pi;
  final p = u - u.floor();
  return fluidColourRate(time * fluidShaderTimeScale, field) *
      16 *
      p *
      p *
      (1 - p) *
      (1 - p);
}

double _peakColourActivity() {
  const count = 2048;
  const step = fluidOrbitPeriod / (2 * count);
  var best = 0;
  for (var i = 1; i < count; i++) {
    if (_colourActivity(i * step, 0) > _colourActivity(best * step, 0)) {
      best = i;
    }
  }
  var low = (best - 1) * step, high = (best + 1) * step;
  for (var i = 0; i < 40; i++) {
    final a = (2 * low + high) / 3, b = (low + 2 * high) / 3;
    if (_colourActivity(a, 0) < _colourActivity(b, 0)) {
      low = a;
    } else {
      high = b;
    }
  }
  return _colourActivity((low + high) / 2, 0);
}

final _peakActivity = _peakColourActivity();
final _integralScale =
    (8 / 15) / (_peakActivity * fluidShaderTimeScale * 2 / math.pi);

double _smoothedPosition(double u) =>
    u.floor() + fluidPaletteBlend(u - u.floor());

final _initialPositions = List<double>.generate(
  4,
  (field) => _smoothedPosition(fluidColourPhase(0, field) * 2 / math.pi),
  growable: false,
);

/// Normal speed at colour rests, +250% (3.5x) at the fastest colour change.
/// Both acceleration and deceleration are continuous at colour boundaries.
double fluidTravelSpeed(double time, int field) =>
    1 + 2.5 * _colourActivity(time, field) / _peakActivity;

/// Analytic integral of that speed. Evaluating any timestamp gives the same
/// position, independent of frame rate, repaint history, palette or navigation.
double fluidTravelTime(double time, int field, {double? colourPosition}) {
  final u =
      colourPosition ??
      fluidColourPhase(time * fluidShaderTimeScale, field) * 2 / math.pi;
  return time +
      2.5 * _integralScale * (_smoothedPosition(u) - _initialPositions[field]);
}

// Keep the original route's base distance. The shared ten-orbit clock now
// closes three routes at 1.5x, without speeding up the colour changes.
final _travelCycle = fluidGeometryCycle + 2.5 * _integralScale * 40;
final _route = _FluidRoute();
// Stagger along the folded route to keep fields distributed over its complete
// loop. Equal quarter offsets repeatedly bunch up at the centre crossings.
const _routeOffsets = [0.0, .816, .898, .723];

double fluidFieldTravelDistance(
  double time,
  int field, {
  double? colourPosition,
}) =>
    fluidMotionSpeedScale *
    fluidTravelTime(time, field, colourPosition: colourPosition) /
    _travelCycle;

/// Write straight into the painter's existing buffer; no per-frame objects.
void writeFluidFieldPosition(
  Float32List values,
  int field,
  double time,
  double colourPosition,
  double amplitude,
) {
  final distance =
      (fluidFieldTravelDistance(time, field, colourPosition: colourPosition) +
          _routeOffsets[field]) %
      1;
  _route.write(values, 6 + field * 2, distance);
  // Keep the existing reduced-motion layout and smooth rhythm envelope.
  final angle = field * math.pi / 2;
  final x = .5 + .46 * math.cos(angle);
  final y = .5 + .46 * math.sin(angle) * 1.08;
  values[6 + field * 2] = x + (values[6 + field * 2] - x) * amplitude;
  values[7 + field * 2] = y + (values[7 + field * 2] - y) * amplitude;
}

/// A closed, smooth route through the centre, edges and all screen quadrants.
/// Arc-length lookup separates spatial curvature from the colour-driven speed;
/// rounded inverse interpolation keeps velocity continuous between samples.
class _FluidRoute {
  static const _points = <double>[
    .10,
    .15,
    .50,
    .48,
    .90,
    .85,
    .86,
    .12,
    .48,
    .52,
    .12,
    .88,
    .08,
    .48,
    .50,
    .12,
    .92,
    .48,
    .52,
    .88,
    .18,
    .65,
    .76,
    .32,
  ];
  static const _segments = 12, _samples = 96, _count = _segments * _samples;
  final _coefficients = Float64List(_segments * 8);
  final _lengths = Float64List(_count + 1);
  final _inverseSpeeds = Float64List(_count + 1);

  _FluidRoute() {
    for (var segment = 0; segment < _segments; segment++) {
      for (var axis = 0; axis < 2; axis++) {
        double p(int shift) =>
            _points[((segment + shift) % _segments) * 2 + axis];
        final a = p(-1), b = p(0), c = p(1), d = p(2);
        final offset = segment * 8 + axis * 4;
        _coefficients[offset] = b;
        _coefficients[offset + 1] = .5 * (c - a);
        _coefficients[offset + 2] = a - 2.5 * b + 2 * c - .5 * d;
        _coefficients[offset + 3] = .5 * (d - a) + 1.5 * (b - c);
      }
    }
    var x = _coordinate(0, 0), y = _coordinate(0, 1);
    for (var i = 0; i <= _count; i++) {
      final u = i / _samples;
      final nextX = _coordinate(u, 0), nextY = _coordinate(u, 1);
      if (i > 0) {
        final dx = nextX - x, dy = nextY - y;
        _lengths[i] = _lengths[i - 1] + math.sqrt(dx * dx + dy * dy);
      }
      final vx = _coordinate(u, 0, derivative: true);
      final vy = _coordinate(u, 1, derivative: true);
      _inverseSpeeds[i] = _samples / math.sqrt(vx * vx + vy * vy);
      x = nextX;
      y = nextY;
    }
  }

  double _coordinate(double u, int axis, {bool derivative = false}) {
    final whole = u.floor(), t = u - whole;
    final offset = (whole % _segments) * 8 + axis * 4;
    final a = _coefficients[offset + 1];
    final b = _coefficients[offset + 2], c = _coefficients[offset + 3];
    return derivative
        ? a + t * (2 * b + t * 3 * c)
        : _coefficients[offset] + t * (a + t * (b + t * c));
  }

  void write(Float32List values, int index, double progress) {
    final target = progress * _lengths.last;
    var low = 0, high = _count;
    while (high - low > 1) {
      final middle = (low + high) ~/ 2;
      if (_lengths[middle] <= target) {
        low = middle;
      } else {
        high = middle;
      }
    }
    final span = _lengths[high] - _lengths[low];
    final p = (target - _lengths[low]) / span;
    final square = p * p, cube = square * p;
    final u =
        (low +
            3 * square -
            2 * cube +
            (cube - 2 * square + p) * span * _inverseSpeeds[low] +
            (cube - square) * span * _inverseSpeeds[high]) /
        _samples;
    final x = _coordinate(u, 0), y = _coordinate(u, 1);
    values[index] = x;
    values[index + 1] = y;
  }
}
