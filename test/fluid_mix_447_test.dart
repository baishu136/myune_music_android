import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/services/artwork_palette_cache.dart';
import 'package:myune_music/widgets/playback_background/fluid_frame_uniforms.dart';

Future<ui.Image> _image(ui.FragmentShader shader, Size size) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(Offset.zero & size, Paint()..shader = shader);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(size.width.toInt(), size.height.toInt());
  } finally {
    picture.dispose();
  }
}

void main() {
  testWidgets(
    'wider overlap blends across the boundary and retains colour cores',
    (tester) async {
      await tester.runAsync(() async {
        final shader = (await ui.FragmentProgram.fromAsset(
          'shaders/fluid_background.frag',
        )).fragmentShader();
        try {
          final values = Float32List(45);
          values[0] = 320;
          values[1] = 160;
          for (var field = 0; field < 4; field++) {
            values[6 + field * 2] = field.isEven ? .22 : .78;
            values[7 + field * 2] = .5;
            values[14 + field * 3 + (field.isEven ? 0 : 2)] = 1;
            values[29 + field * 4] = 1 / .42;
            values[32 + field * 4] = 1 / .42;
          }
          for (var i = 0; i < 45; i++) {
            shader.setFloat(i, values[i]);
          }
          final image = await _image(shader, const Size(320, 160));
          try {
            final rgba = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            double redFraction(int x) {
              final index = (80 * 320 + x) * 4;
              expect(rgba[index + 3], 255);
              return rgba[index] / (rgba[index] + rgba[index + 2]);
            }

            final mixed = List.generate(
              320,
              redFraction,
            ).where((v) => v >= .1 && v <= .9).length;
            expect(mixed, greaterThanOrEqualTo(84));
            expect(redFraction(70), greaterThan(.94));
            expect(redFraction(249), lessThan(.06));
          } finally {
            image.dispose();
          }
        } finally {
          shader.dispose();
        }
      });
    },
  );

  testWidgets('export matched cover shader frames for visual comparison', (
    tester,
  ) async {
    final output = Platform.environment['MIX447_PREVIEW_DIR'];
    final covers = Platform.environment['MIX447_COVERS_DIR'];
    if (output == null || covers == null) return;
    await tester.runAsync(() async {
      await Directory(output).create(recursive: true);
      final cache = ArtworkPaletteCache();
      final shader = (await ui.FragmentProgram.fromAsset(
        'shaders/fluid_background.frag',
      )).fragmentShader();
      final manifest = <String, dynamic>{};
      try {
        for (final entry in Directory(
          covers,
        ).listSync().whereType<File>().where((f) => f.path.endsWith('.png'))) {
          final name = entry.uri.pathSegments.last.replaceAll('.png', '');
          final palette = await cache.resolve(
            key: name,
            bytes: await entry.readAsBytes(),
            fallbackSeed: Colors.blue,
          );
          for (final size in [const Size(240, 400), const Size(640, 360)]) {
            for (final time in [0.0, 37.0, 83.0]) {
              final frame = FluidFrameUniforms();
              frame.write(
                shader,
                size: size,
                time: time,
                motion: 1,
                dim: .3,
                source: palette,
                target: palette,
              );
              final stem = '$name-${size.width.toInt()}-${time.toInt()}';
              manifest[stem] = frame.values.toList();
              final image = await _image(shader, size);
              try {
                final png = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  '$output/$stem.png',
                ).writeAsBytes(png!.buffer.asUint8List());
              } finally {
                image.dispose();
              }
            }
          }
        }
        await File('$output/uniforms.json').writeAsString(jsonEncode(manifest));
      } finally {
        shader.dispose();
      }
    });
  });
}
