import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/services/artwork_palette_cache.dart';
import 'package:myune_music/widgets/playback_background/fluid_background.dart';
import 'package:myune_music/widgets/playback_background/fluid_background_painter.dart';
import 'package:myune_music/widgets/playback_background/mesh_frame_uniforms.dart';

const _palette = FluidPalette(
  Color(0xFF18394C),
  Color(0xFFCB426B),
  Color(0xFF1AA292),
  Color(0xFFDFAA48),
  baseColor: Color(0xFF24182B),
);

void main() {
  testWidgets(
    'mesh colour fronts propagate outwards and dark nodes stay separated',
    (tester) async {
      await tester.runAsync(() async {
        final shader = (await ui.FragmentProgram.fromAsset(
          'shaders/fluid_mesh_background.frag',
        )).fragmentShader();
        Future<Uint8List> render(double phase, {bool dark = false}) async {
          final v = Float32List(34);
          v[0] = 200;
          v[1] = 320;
          v[4] = phase;
          for (var c = 0; c < 3; c++) {
            for (var colour = 0; colour < 3; colour++) {
              v[6 + colour * 3 + c] = dark ? 1 : (c == colour ? 1 : 0);
            }
            v[18 + c] = dark ? 1 : 0;
          }
          v[21] = dark ? 1 : 0;
          for (var i = 0; i < v.length; i++) {
            shader.setFloat(i, v[i]);
          }
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawRect(
            const Rect.fromLTWH(0, 0, 200, 320),
            Paint()..shader = shader,
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(200, 320);
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          image.dispose();
          picture.dispose();
          return data;
        }

        final earlier = await render(0), later = await render(.2 / .85);
        for (var c = 0; c < 3; c++) {
          expect(
            (earlier[(159 * 200 + 139) * 4 + c] -
                    later[(159 * 200 + 179) * 4 + c])
                .abs(),
            lessThanOrEqualTo(5),
          );
        }
        final dark = await render(.5, dark: true);
        final occupied = <Offset>[];
        for (var y = 1; y < 16; y++) {
          for (var x = 1; x < 10; x++) {
            if (dark[((y * 20) * 200 + x * 20) * 4] < 210) {
              occupied.add(Offset(x.toDouble(), y.toDouble()));
            }
          }
        }
        expect(occupied.length, greaterThan(1));
        for (var a = 0; a < occupied.length; a++) {
          for (var b = a + 1; b < occupied.length; b++) {
            final d = occupied[a] - occupied[b];
            expect(math.max(d.dx.abs(), d.dy.abs()), greaterThanOrEqualTo(3));
          }
        }
        shader.dispose();
      });
    },
  );

  testWidgets(
    'rendered cycle seams, event boundaries and shader replacement stay continuous',
    (tester) async {
      await tester.runAsync(() async {
        final program = await ui.FragmentProgram.fromAsset(
          'shaders/fluid_mesh_background.frag',
        );
        final a = program.fragmentShader(), b = program.fragmentShader();
        final frame = MeshFrameUniforms();
        Future<Uint8List> render(ui.FragmentShader shader, double time) async {
          frame.write(
            shader,
            size: const Size(72, 128),
            time: time,
            motion: 1,
            dim: .3,
            source: _palette,
            target: _palette,
          );
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawRect(
            const Rect.fromLTWH(0, 0, 72, 128),
            Paint()..shader = shader,
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(72, 128);
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          image.dispose();
          picture.dispose();
          return data;
        }

        for (final time in [
          fluidPhaseCycle,
          fluidPhaseCycle / 20,
          fluidPhaseCycle / 15,
          fluidPhaseCycle / 12,
        ]) {
          final before = await render(a, time - 1e-5),
              after = await render(a, time + 1e-5);
          var maximum = 0;
          for (var i = 0; i < before.length; i++) {
            maximum = math.max(maximum, (before[i] - after[i]).abs());
          }
          expect(maximum, lessThanOrEqualTo(1));
        }
        final first = await render(a, 17);
        final replacement = await render(b, 17);
        expect(replacement, first);
        a.dispose();
        b.dispose();
      });
    },
  );
  test(
    'saturation is relative +10 percent with unchanged hue and lightness',
    () {
      for (final color in [
        const Color(0xFF638AA4),
        const Color(0xFFB67B92),
        Colors.grey,
        Colors.black,
        Colors.white,
        Colors.red,
      ]) {
        final values = Float32List.fromList([color.r, color.g, color.b]);
        boostMeshSaturation(values, 0);
        final after = HSLColor.fromColor(
          Color.from(
            alpha: 1,
            red: values[0],
            green: values[1],
            blue: values[2],
          ),
        );
        final before = HSLColor.fromColor(color);
        final high = values.reduce(math.max), low = values.reduce(math.min);
        final light = (high + low) / 2;
        final saturation = high == low
            ? 0.0
            : (high - low) / (1 - (2 * light - 1).abs());
        expect(saturation, closeTo(math.min(1, before.saturation * 1.1), 1e-6));
        expect(light, closeTo(before.lightness, 1e-6));
        if (before.saturation > .01) {
          expect(after.hue, closeTo(before.hue, .6));
        }
      }
    },
  );

  test(
    'event support stays within 70 percent, buffers reuse, periodic seams stay continuous',
    () {
      for (final size in [
        const Size(360, 640),
        const Size(640, 360),
        const Size(600, 600),
      ]) {
        final frame = MeshFrameUniforms();
        final buffer = frame.values;
        void update(double time) => frame.update(
          size: size,
          time: time,
          motion: 1,
          dim: .3,
          source: _palette,
          target: _palette,
        );
        for (var i = 0; i < 1000; i++) {
          update(i * fluidPhaseCycle / 1000);
          expect(identical(buffer, frame.values), isTrue);
          expect(frame.values.every((x) => x.isFinite), isTrue);
          for (var event = 0; event < 3; event++) {
            final offset = 22 + event * 4;
            if (frame.values[offset + 3].abs() > 1e-6) {
              final diameter =
                  2 * (frame.values[offset + 2] + math.sqrt2 * meshGridStep);
              expect(
                diameter,
                lessThanOrEqualTo(frame.maximumLocalDiameter + 1e-6),
              );
            }
          }
        }
        update(fluidPhaseCycle - 1e-5);
        final previous = Float32List.fromList(frame.values);
        update(1e-5);
        for (var i = 6; i < 22; i++) {
          expect(
            frame.values[i],
            closeTo(previous[i], .0001),
            reason: 'seam $i',
          );
        }
        for (var event = 0; event < 3; event++) {
          final i = 22 + event * 4;
          if ((previous[i] - frame.values[i]).abs() > 1e-4 ||
              (previous[i + 1] - frame.values[i + 1]).abs() > 1e-4) {
            expect(
              previous[i + 3].abs() + frame.values[i + 3].abs(),
              lessThan(1e-6),
            );
          } else {
            expect(frame.values[i + 3], closeTo(previous[i + 3], .0001));
          }
        }
      }
    },
  );

  testWidgets('production widget loads mesh shader and releases its ticker', (
    tester,
  ) async {
    await tester.runAsync(
      () => FluidPlaybackBackground.prewarm(
        bytes: Uint8List(0),
        identity: 'mesh-423',
        cacheGeneration: 0,
        fallbackSeed: Colors.teal,
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: FluidPlaybackBackground(
          artworkBytes: null,
          artworkIdentity: 'mesh-423',
          artworkCacheGeneration: 0,
          fallbackSeed: Colors.teal,
          dim: .3,
          quality: FluidBackgroundQuality.smooth,
          routeTransitionActive: false,
          child: SizedBox.expand(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('fluid-background-shader')),
    );
    expect((paint.painter! as FluidBackgroundPainter).mesh, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'mesh renders portraits, changing covers, and continuous frames',
    (tester) async {
      await tester.runAsync(() async {
        final program = await ui.FragmentProgram.fromAsset(
          'shaders/fluid_mesh_background.frag',
        );
        final shader = program.fragmentShader();
        final frame = MeshFrameUniforms();
        final output = Platform.environment['MESH_PREVIEW_DIR'];
        final samples = <String, FluidPalette>{
          'colour': _palette,
          'black': buildFluidPalette([Colors.black], fallbackSeed: Colors.blue),
          'teal': buildFluidPalette([
            const Color(0xFF8BC5C8),
          ], fallbackSeed: Colors.blue),
          'vivid': buildFluidPalette([
            Colors.pink,
            Colors.teal,
            Colors.orange,
          ], fallbackSeed: Colors.blue),
        };
        final coverDir = Platform.environment['MESH_COVER_DIR'];
        if (coverDir != null) {
          for (final name in [
            '1496612195',
            '445117371',
            '638689121',
            '657211711',
          ]) {
            final file = File('$coverDir/$name.jpg');
            if (await file.exists()) {
              samples[name] = await fluidArtworkPaletteCache.resolve(
                key: 'mesh-$name',
                bytes: await file.readAsBytes(),
                fallbackSeed: Colors.blue,
              );
            }
          }
        }
        for (final entry in samples.entries) {
          for (final time in [0.0, 7.0, 14.0, 21.0]) {
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder);
            frame.write(
              shader,
              size: const Size(270, 480),
              time: time,
              motion: 1,
              dim: .3,
              source: entry.value,
              target: entry.value,
            );
            canvas.drawRect(
              const Rect.fromLTWH(0, 0, 270, 480),
              Paint()..shader = shader,
            );
            final picture = recorder.endRecording();
            final image = await picture.toImage(270, 480);
            final rgba = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            for (var i = 3; i < rgba.lengthInBytes; i += 4) {
              expect(rgba.getUint8(i), 255);
            }
            if (output != null) {
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '$output/${entry.key}-${time.toInt()}.png',
              ).writeAsBytes(png!.buffer.asUint8List());
            }
            image.dispose();
            picture.dispose();
          }
        }
        final animation = Platform.environment['MESH_ANIMATION_DIR'];
        if (animation != null) {
          final palette = samples['638689121'] ?? samples['vivid']!;
          for (var index = 0; index < 150; index++) {
            frame.write(
              shader,
              size: const Size(270, 480),
              time: 2 + index / 15,
              motion: 1,
              dim: .3,
              source: palette,
              target: palette,
            );
            final recorder = ui.PictureRecorder();
            Canvas(recorder).drawRect(
              const Rect.fromLTWH(0, 0, 270, 480),
              Paint()..shader = shader,
            );
            final picture = recorder.endRecording();
            final image = await picture.toImage(270, 480);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '$animation/${index.toString().padLeft(3, '0')}.png',
            ).writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
            picture.dispose();
          }
        }
        shader.dispose();
      });
    },
  );
}
