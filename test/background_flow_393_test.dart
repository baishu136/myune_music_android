import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/playback_background/fluid_frame_uniforms.dart';

void main() {
  const h = .0001;
  double speed(double t, int field) =>
      (fluidOrbitAngle(t + h, field, 1) - fluidOrbitAngle(t - h, field, 1)) /
      (2 * h);

  test(
    'long ramps increase and decrease speed linearly over most of each orbit',
    () {
      for (var field = 0; field < 4; field++) {
        final stagger = field * .20;
        for (final half in [0.0, math.pi]) {
          final sign = half == 0 ? 1 : -1;
          final start = half + .15 - stagger;
          for (var sample = 1; sample <= 18; sample++) {
            final t = start + sample * .15;
            expect(
              speed(t, field) - speed(start, field),
              closeTo(sign * .8 / math.pi * sample * .15, 1e-7),
            );
          }
          // A ramp crosses a substantial part of the screen, not a short pulse.
          expect(
            fluidOrbitAngle(start + 2.7, field, 1) -
                fluidOrbitAngle(start, field, 1),
            greaterThan(2.5),
          );
        }
      }
    },
  );

  test(
    'linear ramps retain continuous speed and acceleration at rounded corners',
    () {
      for (var field = 0; field < 4; field++) {
        for (final phase in [
          0.0,
          .12,
          math.pi - .12,
          math.pi,
          math.pi + .12,
          2 * math.pi - .12,
          2 * math.pi,
        ]) {
          final t = phase - field * .20;
          expect(speed(t - h, field), closeTo(speed(t + h, field), .00006));
          final left = (speed(t, field) - speed(t - .001, field)) / .001;
          final right = (speed(t + .001, field) - speed(t, field)) / .001;
          expect(left, closeTo(right, .003));
        }
        expect(
          fluidOrbitAngle(2 * math.pi, field, 1) - fluidOrbitAngle(0, field, 1),
          closeTo(2 * math.pi, 1e-8),
        );
      }
    },
  );
}
