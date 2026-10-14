import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/services/fluid_background_controller.dart';
import 'package:myune_music/widgets/playback_background/fluid_background_painter.dart';
import 'package:myune_music/widgets/playback_background/fluid_frame_uniforms.dart';

void main() {
  testWidgets('fourth cover pigment wanders inward and toward screen edges', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final shader = (await ui.FragmentProgram.fromAsset(
        'shaders/fluid_background.frag',
      )).fragmentShader();
      const palette = FluidPalette(
        Colors.white,
        Colors.black,
        Colors.black,
        Colors.black,
        baseColor: Colors.black,
      );
      try {
        for (final size in [const Size(96, 160), const Size(160, 96)]) {
          var near = double.infinity, far = 0.0;
          var largestStep = 0;
          for (var step = 0; step < 48; step++) {
            final pixels = await _render(
              shader,
              palette,
              size,
              fluidPhaseCycle * step / 48,
            );
            final width = size.width.toInt(), height = size.height.toInt();
            var peak = 0;
            var energy = 0.0, centreX = 0.0, centreY = 0.0;
            for (var y = 0; y < height; y++) {
              for (var x = 0; x < width; x++) {
                final i = (y * width + x) * 4;
                if (pixels[i] > peak) {
                  peak = pixels[i];
                }
                final weight = math.pow(pixels[i] / 255, 3).toDouble();
                energy += weight;
                centreX += weight * (x + .5) / width;
                centreY += weight * (y + .5) / height;
                if (x + 1 < width) {
                  largestStep = math.max(
                    largestStep,
                    (pixels[i] - pixels[i + 4]).abs(),
                  );
                }
                if (y + 1 < height) {
                  largestStep = math.max(
                    largestStep,
                    (pixels[i] - pixels[i + width * 4]).abs(),
                  );
                }
                expect(pixels[i + 3], 255);
              }
            }
            // A bounded field may leave the screen during its wider journey.
            if (peak < 8 || energy < .001) continue;
            final radius = math.sqrt(
              math.pow(centreX / energy - .5, 2) +
                  math.pow(centreY / energy - .5, 2),
            );
            near = math.min(near, radius);
            far = math.max(far, radius);
          }
          debugPrint(
            'Fourth pigment $size: radius=$near..$far, spatialStep=$largestStep',
          );
          expect(near, lessThan(.33));
          expect(far, greaterThan(.36));
          expect(far - near, greaterThan(.12));
          // Compact fields have a finite outer edge, unlike the old infinite tails.
          expect(largestStep, lessThanOrEqualTo(12));
        }
      } finally {
        shader.dispose();
      }
    });
  });
}

Future<Uint8List> _render(
  ui.FragmentShader shader,
  FluidPalette palette,
  Size size,
  double time,
) async {
  final controller = FluidBackgroundController(
    vsync: const TestVSync(),
    initialPalette: palette,
  );
  final setup = ui.PictureRecorder();
  FluidBackgroundPainter(
    shader: shader,
    controller: controller,
    dim: .3,
  ).paint(Canvas(setup), size);
  setup.endRecording().dispose();
  FluidFrameUniforms().write(
    shader,
    size: size,
    time: time,
    motion: 1,
    dim: .3,
    source: palette,
    target: palette,
  );
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(Offset.zero & size, Paint()..shader = shader);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
    controller.dispose();
  }
}
