import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'colour restoration never adds a light or dark ribbon between fields',
    (tester) async {
      await tester.runAsync(() async {
        final shader = (await ui.FragmentProgram.fromAsset(
          'shaders/fluid_background.frag',
        )).fragmentShader();
        Future<Uint8List> render(
          Color warm,
          Color cool,
          double protection,
        ) async {
          final values = Float32List(77);
          values[0] = 320;
          values[1] = 160;
          for (var field = 0; field < 4; field++) {
            final c = field.isEven ? warm : cool;
            values[6 + field * 2] = field.isEven ? .22 : .78;
            values[7 + field * 2] = .5;
            values[14 + field * 3] = c.r;
            values[15 + field * 3] = c.g;
            values[16 + field * 3] = c.b;
            values[29 + field * 4] = values[32 + field * 4] = 1 / .42;
            values[53 + field] =
                math.max(c.r, math.max(c.g, c.b)) -
                math.min(c.r, math.min(c.g, c.b));
          }
          values[49] = warm.r;
          values[50] = warm.g;
          values[51] = warm.b;
          values[52] = protection;
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
            return (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
          } finally {
            image.dispose();
            picture.dispose();
          }
        }

        double level(Uint8List pixels, int i) =>
            (.2126 * pixels[i] +
                .7152 * pixels[i + 1] +
                .0722 * pixels[i + 2]) /
            255;
        try {
          for (final pair in [
            (const Color(0xFFDF5145), const Color(0xFF009C91)),
            (const Color(0xFFE39431), const Color(0xFF384DB8)),
            (const Color(0xFF551726), const Color(0xFF124C43)),
          ]) {
            final raw = await render(pair.$1, pair.$2, 0);
            for (final protection in [.04, .10, .16, .20]) {
              final corrected = await render(pair.$1, pair.$2, protection);
              var peak = 0.0;
              for (var i = 0; i < raw.length; i += 4) {
                peak = math.max(
                  peak,
                  (level(corrected, i) - level(raw, i)).abs(),
                );
                expect(corrected[i + 3], 255);
              }
              debugPrint(
                '452 luma ribbon control: protection=$protection, maximum difference=$peak',
              );
              expect(
                peak,
                lessThanOrEqualTo(1.1 / 255),
                reason:
                    'anti-grey correction must preserve the original continuous display-luma field',
              );
            }
          }
        } finally {
          shader.dispose();
        }
      });
    },
  );
}
