import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/widgets/playback_background/fluid_frame_uniforms.dart';
import 'package:myune_music/widgets/playback_background/fluid_colour_motion.dart';
import 'package:myune_music/widgets/playback_background/fluid_field_travel.dart';

void main() {
  void position(Float32List buffer, double t, int field) =>
      writeFluidFieldPosition(
        buffer,
        field,
        t,
        fluidColourPhase(t * fluidShaderTimeScale, field) * 2 / math.pi,
        1,
      );

  test(
    'actual curve speed follows colour speed without curve-entry surges',
    () {
      final before = Float32List(45), after = Float32List(45);
      for (var field = 0; field < 4; field++) {
        var minimum = double.infinity, maximum = 0.0;
        for (var step = 0; step < 12000; step++) {
          final t = fluidPhaseCycle * step / 12000;
          position(before, t - .005, field);
          position(after, t + .005, field);
          final dx = after[6 + field * 2] - before[6 + field * 2];
          final dy = after[7 + field * 2] - before[7 + field * 2];
          final baseSpeed =
              math.sqrt(dx * dx + dy * dy) / (.01 * fluidTravelSpeed(t, field));
          minimum = math.min(minimum, baseSpeed);
          maximum = math.max(maximum, baseSpeed);
          expect(before[6 + field * 2].isFinite, isTrue);
          expect(before[7 + field * 2].isFinite, isTrue);
        }
        expect(maximum / minimum, lessThan(1.015));
        position(before, -0.001, field);
        position(after, fluidPhaseCycle - .001, field);
        expect(before, orderedEquals(after));
      }
    },
  );

  test('colour rests restore normal speed with buffered entry and exit', () {
    for (var field = 0; field < 4; field++) {
      for (var colour = 1; colour <= 7; colour++) {
        var low = 0.0, high = fluidOrbitPeriod;
        for (var i = 0; i < 60; i++) {
          final t = (low + high) / 2;
          final u =
              fluidColourPhase(t * fluidShaderTimeScale, field) * 2 / math.pi;
          if (u < colour) {
            low = t;
          } else {
            high = t;
          }
        }
        final t = (low + high) / 2;
        expect(fluidTravelSpeed(t, field), closeTo(1, 1e-10));
        expect(fluidTravelSpeed(t - .001, field), closeTo(1, .00002));
        expect(fluidTravelSpeed(t + .001, field), closeTo(1, .00002));
      }
    }
  });

  testWidgets(
    'repaint history, resizing and palette retargets do not reset travel',
    (tester) async {
      await tester.runAsync(() async {
        final shader = (await ui.FragmentProgram.fromAsset(
          'shaders/fluid_background.frag',
        )).fragmentShader();
        final palette = FluidPalette.fallback(Colors.blue);
        final target = FluidPalette.fallback(Colors.orange);
        final retained = FluidFrameUniforms();
        try {
          for (final hz in [24, 60, 120]) {
            for (var frame = 0; frame < hz * 3; frame++) {
              retained.write(
                shader,
                size: const Size(240, 400),
                time: frame / hz,
                motion: 1,
                dim: .3,
                source: palette,
                target: target,
                paletteProgress: (frame / hz / 3).clamp(0, 1),
              );
            }
            for (final time in [3.0, 83.0, .0, fluidPhaseCycle, -1e-17]) {
              final direct = FluidFrameUniforms();
              direct.write(
                shader,
                size: const Size(640, 360),
                time: time,
                motion: 1,
                dim: .3,
                source: palette,
                target: palette,
              );
              retained.write(
                shader,
                size: const Size(240, 400),
                time: time,
                motion: 1,
                dim: .3,
                source: target,
                target: palette,
                paletteProgress: .3,
              );
              expect(
                retained.values.sublist(6, 14),
                direct.values.sublist(6, 14),
              );
            }
          }
        } finally {
          shader.dispose();
        }
      });
    },
  );

  testWidgets('every field crosses the centre and all nine screen regions', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final shader = (await ui.FragmentProgram.fromAsset(
        'shaders/fluid_background.frag',
      )).fragmentShader();
      final uniforms = FluidFrameUniforms();
      final palette = FluidPalette.fallback(Colors.blue);
      try {
        for (final size in [const Size(240, 400), const Size(640, 360)]) {
          final regions = List.generate(4, (_) => <int>{});
          final centre = List.filled(4, false);
          for (var step = 0; step < 2400; step++) {
            uniforms.write(
              shader,
              size: size,
              time: fluidPhaseCycle * step / 2400,
              motion: 1,
              dim: .3,
              source: palette,
              target: palette,
            );
            for (var field = 0; field < 4; field++) {
              final x = uniforms.values[6 + field * 2];
              final y = uniforms.values[7 + field * 2];
              regions[field].add(
                (y * 3).floor().clamp(0, 2) * 3 + (x * 3).floor().clamp(0, 2),
              );
              if ((x - .5).abs() < .06 && (y - .5).abs() < .06) {
                centre[field] = true;
              }
            }
          }
          for (var field = 0; field < 4; field++) {
            expect(regions[field].length, 9, reason: '$size field $field');
            expect(centre[field], isTrue, reason: '$size field $field');
          }
        }
      } finally {
        shader.dispose();
      }
    });
  });
}
