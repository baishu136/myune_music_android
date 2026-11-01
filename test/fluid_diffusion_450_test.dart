import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/widgets/playback_background/fluid_field_travel.dart';
import 'package:myune_music/widgets/playback_background/fluid_colour_motion.dart';
import 'package:myune_music/widgets/playback_background/fluid_frame_uniforms.dart';

void main() {
  test(
    'travel is 50 percent faster at every colour phase and closes three routes',
    () {
      const h = .001;
      for (var field = 0; field < 4; field++) {
        final previousRoute =
            fluidTravelTime(fluidGeometryCycle, field) -
            fluidTravelTime(0, field);
        for (var step = 0; step < 1600; step++) {
          final t = fluidPhaseCycle * step / 1600;
          final previousSpeed =
              (fluidTravelTime(t + h, field) - fluidTravelTime(t - h, field)) /
              previousRoute;
          final speed =
              fluidFieldTravelDistance(t + h, field) -
              fluidFieldTravelDistance(t - h, field);
          expect(speed / previousSpeed, closeTo(1.5, 1e-6));
        }
        expect(
          fluidFieldTravelDistance(fluidPhaseCycle, field) -
              fluidFieldTravelDistance(0, field),
          closeTo(3, 1e-10),
        );
      }
    },
  );

  testWidgets(
    'small fields retain a broad minimum footprint and colour time is unchanged',
    (tester) async {
      await tester.runAsync(() async {
        final shader = (await ui.FragmentProgram.fromAsset(
          'shaders/fluid_background.frag',
        )).fragmentShader();
        final packed = FluidFrameUniforms();
        final palette = FluidPalette(
          Colors.red,
          Colors.green,
          Colors.blue,
          Colors.amber,
          motionWeights: List.filled(32, .55),
        );
        const size = Size(240, 400);
        try {
          packed.write(
            shader,
            size: size,
            time: 11.3,
            motion: 0,
            dim: .3,
            source: palette,
            target: palette,
          );
          final base = math.min(
            .52,
            size.longestSide / size.shortestSide / (3 * 1.16),
          );
          for (var field = 0; field < 4; field++) {
            final shape = 29 + field * 4;
            final radius =
                1 /
                math.sqrt(
                  math.pow(packed.values[shape], 2) +
                      math.pow(packed.values[shape + 1], 2),
                );
            expect(radius / base, closeTo(.65, 1e-6));
            final expected = fluidFieldColourAtTime(palette, 11.3, field);
            expect(packed.values[14 + field * 3], closeTo(expected.r, 1e-7));
            expect(packed.values[15 + field * 3], closeTo(expected.g, 1e-7));
            expect(packed.values[16 + field * 3], closeTo(expected.b, 1e-7));
          }
        } finally {
          shader.dispose();
        }
      });
    },
  );

  testWidgets(
    'a broad diffuse join connects colour fields without erasing their cores',
    (tester) async {
      await tester.runAsync(() async {
        final shader = (await ui.FragmentProgram.fromAsset(
          'shaders/fluid_background.frag',
        )).fragmentShader();
        final values = Float32List(57);
        values[0] = 320;
        values[1] = 160;
        for (var field = 0; field < 4; field++) {
          values[6 + field * 2] = field.isEven ? .22 : .78;
          values[7 + field * 2] = .5;
          values[14 + field * 3 + (field.isEven ? 0 : 2)] = 1;
          values[29 + field * 4] = values[32 + field * 4] = 1 / .42;
        }
        try {
          for (var i = 0; i < values.length; i++) {
            shader.setFloat(i, values[i]);
          }
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawRect(
            const Rect.fromLTWH(0, 0, 320, 160),
            Paint()..shader = shader,
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(320, 160);
          try {
            final rgba = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            double fraction(int x) {
              final i = (80 * 320 + x) * 4;
              return rgba[i] / (rgba[i] + rgba[i + 2]);
            }

            final mixed = List.generate(
              320,
              fraction,
            ).where((f) => f >= .1 && f <= .9).length;
            debugPrint(
              '450 overlap control: mixed=$mixed, red core=${fraction(70)}, blue core=${fraction(249)}',
            );
            expect(mixed, greaterThanOrEqualTo(100));
            expect(fraction(70), greaterThan(.90));
            expect(fraction(249), lessThan(.10));
            for (var i = 3; i < rgba.length; i += 4) {
              expect(rgba[i], 255);
            }
          } finally {
            image.dispose();
            picture.dispose();
          }
        } finally {
          shader.dispose();
        }
      });
    },
  );
}
