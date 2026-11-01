import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'mixing protects moderate chroma loss without lifting lightness or tinting grey',
    (tester) async {
      await tester.runAsync(() async {
        final shader = (await ui.FragmentProgram.fromAsset(
          'shaders/fluid_background.frag',
        )).fragmentShader();
        Future<List<double>> sample(
          Color a,
          Color b,
          double share, {
          bool protect = true,
        }) async {
          final values = Float32List(57);
          values[0] = values[1] = 32;
          for (var field = 0; field < 4; field++) {
            final c = field.isEven ? a : b;
            values[6 + field * 2] = values[7 + field * 2] = .5;
            values[14 + field * 3] = c.r;
            values[15 + field * 3] = c.g;
            values[16 + field * 3] = c.b;
            values[29 + field * 4] = values[32 + field * 4] = 2;
            values[45 + field] = (field.isEven ? share : 1 - share) * 2 - 1;
            values[53 + field] =
                math.max(c.r, math.max(c.g, c.b)) -
                math.min(c.r, math.min(c.g, c.b));
          }
          values[49] = a.r;
          values[50] = a.g;
          values[51] = a.b;
          values[52] = protect ? .2 : 0;
          for (var i = 0; i < values.length; i++) {
            shader.setFloat(i, values[i]);
          }
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawRect(
            const Rect.fromLTWH(0, 0, 32, 32),
            Paint()..shader = shader,
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(32, 32);
          try {
            final rgba = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            const i = (16 * 32 + 16) * 4;
            expect(rgba[i + 3], 255);
            return List.generate(3, (c) => rgba[i + c] / 255);
          } finally {
            image.dispose();
            picture.dispose();
          }
        }

        double chroma(List<double> c) =>
            c.reduce(math.max) - c.reduce(math.min);
        double lightness(List<double> c) =>
            (c.reduce(math.max) + c.reduce(math.min)) / 2;
        try {
          const blue = Color(0xFF3366B3), warm = Color(0xFFB3661A);
          final raw = await sample(blue, warm, .7, protect: false);
          final vivid = await sample(blue, warm, .7);
          debugPrint('451 moderate mix: raw=$raw protected=$vivid');
          expect(chroma(vivid), greaterThan(chroma(raw) * 1.35));
          expect(lightness(vivid), closeTo(lightness(raw), 2 / 255));
          for (final c in [const Color(0xFF111315), const Color(0xFFCED0D1)]) {
            final a = await sample(c, Colors.grey, .5, protect: false);
            final b = await sample(c, Colors.grey, .5);
            expect(
              b,
              orderedEquals(a),
              reason: 'near-neutral input should retain its original style',
            );
          }
          var previous = await sample(blue, warm, .275);
          for (var step = 1; step <= 90; step++) {
            final current = await sample(blue, warm, .275 + step * .005);
            expect(
              lightness(current),
              closeTo(
                lightness(
                  await sample(blue, warm, .275 + step * .005, protect: false),
                ),
                2 / 255,
              ),
            );
            for (var c = 0; c < 3; c++) {
              expect((current[c] - previous[c]).abs(), lessThan(.025));
            }
            previous = current;
          }
        } finally {
          shader.dispose();
        }
      });
    },
  );
}
