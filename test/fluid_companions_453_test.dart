import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/services/artwork_palette_cache.dart';
import 'package:myune_music/widgets/playback_background/fluid_frame_uniforms.dart';

FluidPalette cover(List<Color> colors) => buildWeightedFluidPalette(
  colors.map((c) => FluidColorSample(c, 1 / colors.length)).toList(),
  fallbackSeed: Colors.blue,
);

void main() {
  test('one/two colour families get one child each, three get none', () {
    for (final colors in [
      [const Color(0xFFB83A50)],
      [const Color(0xFFB83A50), const Color(0xFF245AB0)],
      [
        const Color(0xFFB83A50),
        const Color(0xFF245AB0),
        const Color(0xFFE0AE36),
      ],
    ]) {
      final p = cover(colors);
      expect(p.companionMix.length, 8);
      expect(
        p.companionMix.reduce((a, b) => a + b),
        colors.length < 3 ? colors.length : 0,
      );
    }
    final shades = cover([const Color(0xFFB83A50), const Color(0xFF7B2430)]);
    expect(shades.companionMix.reduce((a, b) => a + b), 1);
  });

  testWidgets(
    'children follow live parents and fade continuously on retarget',
    (tester) async {
      await tester.runAsync(() async {
        final shader = (await ui.FragmentProgram.fromAsset(
          'shaders/fluid_background.frag',
        )).fragmentShader();
        final u = FluidFrameUniforms();
        final two = cover([const Color(0xFFB83A50), const Color(0xFF245AB0)]);
        final three = cover([
          const Color(0xFFB83A50),
          const Color(0xFF245AB0),
          const Color(0xFFE0AE36),
        ]);
        void write(FluidPalette a, FluidPalette b, double p, double time) =>
            u.write(
              shader,
              size: const Size(240, 400),
              time: time,
              motion: 1,
              dim: .3,
              source: a,
              target: b,
              paletteProgress: p,
            );
        try {
          write(two, two, 1, 9);
          for (var child = 0; child < 2; child++) {
            final base = 57 + child * 10;
            final slot = two.companionMix
                .sublist(child * 4, child * 4 + 4)
                .indexOf(1);
            final field = slot == 0 ? 3 : slot - 1;
            expect(u.values[base + 9], closeTo(1, 1e-6));
            for (var c = 0; c < 3; c++) {
              expect(
                u.values[base + 6 + c],
                closeTo(u.values[14 + field * 3 + c] * .64, 1e-6),
              );
            }
            expect(
              (u.values[base] - u.values[6 + field * 2]).abs(),
              lessThan(.22),
            );
          }
          var previous = 1.0;
          for (var step = 0; step <= 100; step++) {
            final p = step / 100;
            write(two, three, p, 9);
            final strength = u.values[66].toDouble();
            expect(strength, lessThanOrEqualTo(previous + 1e-6));
            expect(previous - strength, lessThan(.02));
            previous = strength;
          }
          expect(u.values[66], 0);
          expect(u.values[76], 0);
          final snapshot = FluidPalette.lerp(
            two,
            three,
            fluidPaletteBlend(.37),
            transitionProgress: .37,
          );
          write(two, three, .37, 9);
          final before = u.values.sublist(57);
          write(snapshot, two, 0, 9);
          for (var i = 0; i < 20; i++) {
            expect(u.values[57 + i], closeTo(before[i], 1e-6));
          }
          write(two, two, 1, 0);
          final cycleStart = u.values.sublist(57);
          write(two, two, 1, fluidPhaseCycle);
          for (var i = 0; i < 20; i++) {
            expect(u.values[57 + i], closeTo(cycleStart[i], 2e-5));
          }
        } finally {
          shader.dispose();
        }
      });
    },
  );

  testWidgets(
    'actual shader adds soft related depth without bright join bands',
    (tester) async {
      await tester.runAsync(() async {
        final shader = (await ui.FragmentProgram.fromAsset(
          'shaders/fluid_background.frag',
        )).fragmentShader();
        final uniforms = FluidFrameUniforms();
        final output = Platform.environment['COMPANION453_PREVIEW_DIR'];
        if (output != null) await Directory(output).create(recursive: true);
        Future<Uint8List> render(String label) async {
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawRect(
            const Rect.fromLTWH(0, 0, 240, 400),
            Paint()..shader = shader,
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(240, 400);
          try {
            if (output != null) {
              await File('$output/$label.png').writeAsBytes(
                (await image.toByteData(
                  format: ui.ImageByteFormat.png,
                ))!.buffer.asUint8List(),
              );
            }
            return (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
          } finally {
            image.dispose();
            picture.dispose();
          }
        }

        double luma(Uint8List rgba, int i) =>
            (.2126 * rgba[i] + .7152 * rgba[i + 1] + .0722 * rgba[i + 2]) / 255;
        try {
          for (final (name, colors) in [
            ('one', [const Color(0xFFC13951)]),
            ('two', [const Color(0xFFDF5145), const Color(0xFF009C91)]),
            (
              'three',
              [
                const Color(0xFFC13951),
                const Color(0xFF245AB0),
                const Color(0xFFE0AE36),
              ],
            ),
            ('grey', [const Color(0xFF989898), const Color(0xFF555555)]),
          ]) {
            final palette = cover(colors);
            for (final time in [0.0, 12.0, 48.0]) {
              uniforms.write(
                shader,
                size: const Size(240, 400),
                time: time,
                motion: 1,
                dim: .3,
                source: palette,
                target: palette,
              );
              final protected = await render('$name-$time');
              shader.setFloat(52, 0);
              final raw = await render('$name-$time-raw');
              shader.setFloat(52, uniforms.values[52]);
              shader.setFloat(66, 0);
              shader.setFloat(76, 0);
              final without = await render('$name-$time-without');
              shader.setFloat(66, uniforms.values[66]);
              shader.setFloat(76, uniforms.values[76]);
              var maxDepth = 0.0, maxRibbon = 0.0;
              for (var i = 0; i < protected.length; i += 4) {
                maxDepth = math.max(
                  maxDepth,
                  luma(without, i) - luma(protected, i),
                );
                maxRibbon = math.max(
                  maxRibbon,
                  (luma(raw, i) - luma(protected, i)).abs(),
                );
                expect(protected[i + 3], 255);
                if (name == 'grey') {
                  expect(
                    (protected[i] - protected[i + 1]).abs(),
                    lessThanOrEqualTo(1),
                  );
                  expect(
                    (protected[i + 1] - protected[i + 2]).abs(),
                    lessThanOrEqualTo(1),
                  );
                }
              }
              expect(maxRibbon, lessThanOrEqualTo(1.1 / 255));
              expect(maxDepth, name == 'three' ? 0 : greaterThan(2 / 255));
            }
          }
        } finally {
          shader.dispose();
        }
      });
    },
  );
}
