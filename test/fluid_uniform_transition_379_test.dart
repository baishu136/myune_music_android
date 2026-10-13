import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/widgets/playback_background/fluid_frame_uniforms.dart';

void main() {
  testWidgets(
    'packed uniforms preserve premultiplied transitions, resize and shader replacement',
    (tester) async {
      await tester.runAsync(() async {
        final program = await ui.FragmentProgram.fromAsset(
          'shaders/fluid_background.frag',
        );
        final shader = program.fragmentShader();
        final replacement = program.fragmentShader();
        final uniforms = FluidFrameUniforms();
        const source = FluidPalette(
          Color(0x80FF2200),
          Color(0x4000FF88),
          Color(0xAA2200FF),
          Color(0x00FFFFFF),
          baseColor: Color(0xA0331122),
        );
        const target = FluidPalette(
          Color(0xFF0055AA),
          Color(0xFF881100),
          Color(0x80FFCC00),
          Color(0xFF22AA44),
          baseColor: Color(0xFF081020),
        );
        try {
          for (final size in [const Size(48, 80), const Size(80, 48)]) {
            for (final progress in [0.0, .17, .5, .83, 1.0, .31]) {
              final blend = fluidPaletteBlend(progress);
              Color mixed(Color a, Color b) => Color.from(
                alpha: 1,
                red: a.r * a.a * (1 - blend) + b.r * b.a * blend,
                green: a.g * a.a * (1 - blend) + b.g * b.a * blend,
                blue: a.b * a.a * (1 - blend) + b.b * b.a * blend,
              );
              final expectedPalette = FluidPalette(
                mixed(source.first, target.first),
                mixed(source.second, target.second),
                mixed(source.third, target.third),
                mixed(source.fourth, target.fourth),
                baseColor: mixed(source.baseColor, target.baseColor),
              );
              final actual = await render(
                shader,
                uniforms,
                size,
                source,
                target,
                progress,
              );
              final expected = await render(
                replacement,
                FluidFrameUniforms(),
                size,
                expectedPalette,
                expectedPalette,
                1,
              );
              var largest = 0;
              for (var i = 0; i < actual.length; i++) {
                final difference = (actual[i] - expected[i]).abs();
                if (difference > largest) largest = difference;
              }
              expect(largest, lessThanOrEqualTo(1));
              final swapped = await render(
                replacement,
                uniforms,
                size,
                source,
                target,
                progress,
              );
              expect(
                swapped,
                actual,
                reason: 'shader replacement needs all uniforms',
              );
            }
          }
        } finally {
          shader.dispose();
          replacement.dispose();
        }
      });
    },
  );
}

Future<Uint8List> render(
  ui.FragmentShader shader,
  FluidFrameUniforms uniforms,
  Size size,
  FluidPalette source,
  FluidPalette target,
  double progress,
) async {
  uniforms.write(
    shader,
    size: size,
    time: 17,
    motion: 1.72,
    dim: .3,
    source: source,
    target: target,
    paletteProgress: progress,
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
  }
}
