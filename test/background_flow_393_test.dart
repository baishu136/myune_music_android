import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/widgets/playback_background/fluid_field_travel.dart';

void main() {
  const h = .0001;
  double speed(double t, int field) =>
      (fluidTravelTime(t + h, field) - fluidTravelTime(t - h, field)) / (2 * h);

  test(
    'colour-driven distance integrates actual speed without position jumps',
    () {
      for (var field = 0; field < 4; field++) {
        for (var step = 0; step <= 2400; step++) {
          final t = fluidPhaseCycle * step / 2400;
          expect(speed(t, field), closeTo(fluidTravelSpeed(t, field), 1e-6));
        }
      }
    },
  );

  test(
    'buffered speed and acceleration stay continuous throughout the loop',
    () {
      for (var field = 0; field < 4; field++) {
        double acceleration(double t) =>
            (fluidTravelSpeed(t + h, field) - fluidTravelSpeed(t - h, field)) /
            (2 * h);
        for (var step = 0; step <= 2400; step++) {
          final t = fluidPhaseCycle * step / 2400;
          expect(
            fluidTravelSpeed(t - h, field),
            closeTo(fluidTravelSpeed(t + h, field), .001),
          );
          expect(acceleration(t - h), closeTo(acceleration(t + h), .004));
        }
        expect(
          fluidTravelSpeed(0, field),
          closeTo(fluidTravelSpeed(fluidPhaseCycle, field), 1e-10),
        );
        expect(acceleration(0), closeTo(acceleration(fluidPhaseCycle), 1e-8));
      }
    },
  );
}
