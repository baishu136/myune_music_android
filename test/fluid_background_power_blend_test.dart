import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/services/artwork_palette_cache.dart';
import 'package:myune_music/services/fluid_background_controller.dart';
import 'package:myune_music/widgets/playback_background/fluid_background_painter.dart';
import 'package:myune_music/widgets/playback_background/fluid_frame_uniforms.dart';
import 'support/fluid_field_reference.dart';

const _pigments = [
  FluidColorSample(Color(0xFFEF2683), .40),
  FluidColorSample(Color(0xFF25BFA3), .30),
  FluidColorSample(Color(0xFFF09D2C), .20),
  FluidColorSample(Color(0xFF58687B), .10),
];

void main() {
  testWidgets('orbital pigments avoid opaque colour plateaus', (tester) async {
    await tester.runAsync(() async {
      final shader = (await ui.FragmentProgram.fromAsset(
        'shaders/fluid_background.frag',
      )).fragmentShader();
      const palette = FluidPalette(
        Colors.black,
        Colors.green,
        Colors.black,
        Colors.red,
        baseColor: Colors.black,
      );
      try {
        for (var step = 0; step < 24; step++) {
          final pixels = await _render(
            shader,
            palette,
            time: fluidPhaseCycle * step / 24,
            motion: 1,
          );
          var peakRed = 0, peakGreen = 0;
          for (var y = 0; y < 160; y++) {
            for (var x = 0; x < 96; x++) {
              final i = (y * 96 + x) * 4;
              peakRed = math.max(peakRed, pixels[i]);
              peakGreen = math.max(peakGreen, pixels[i + 1]);
            }
          }
          // Three orbiting fields use convex mixing and subdued coverage.
          expect(peakRed, lessThan(220), reason: 'red orbit $step');
          expect(peakGreen, lessThan(165), reason: 'green orbit $step');
        }
      } finally {
        shader.dispose();
      }
    });
  });
  testWidgets('exposed centre retains cover colour throughout an orbit', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final shader = (await ui.FragmentProgram.fromAsset(
        'shaders/fluid_background.frag',
      )).fragmentShader();
      try {
        final palette = buildWeightedFluidPalette(const [
          FluidColorSample(Colors.white, .55),
          FluidColorSample(Color(0xFFEE2288), .15),
          FluidColorSample(Color(0xFFFFB820), .15),
          FluidColorSample(Color(0xFF22BF9C), .15),
        ], fallbackSeed: Colors.blue);
        for (var step = 0; step < 24; step++) {
          final bytes = await _render(
            shader,
            palette,
            time: fluidPhaseCycle * step / 24,
            motion: 1,
          );
          for (var y = 64; y <= 96; y += 16) {
            for (var x = 36; x <= 60; x += 12) {
              final i = (y * 96 + x) * 4;
              final c = Color.fromARGB(
                255,
                bytes[i],
                bytes[i + 1],
                bytes[i + 2],
              );
              expect(
                HSLColor.fromColor(c).lightness,
                greaterThan(.085),
                reason: 'orbit $step at $x,$y',
              );
              expect(bytes[i + 3], 255);
            }
          }
        }
        const black = FluidPalette(
          Colors.black,
          Colors.black,
          Colors.black,
          Colors.black,
          baseColor: Colors.black,
        );
        final bytes = await _render(shader, black, motion: 1);
        for (var i = 0; i < bytes.length; i += 4) {
          expect(bytes[i], lessThanOrEqualTo(1));
          expect(bytes[i + 1], lessThanOrEqualTo(1));
          expect(bytes[i + 2], lessThanOrEqualTo(1));
        }
      } finally {
        shader.dispose();
      }
    });
  });
  testWidgets(
    'export actual fluid samples without substituting a scalar renderer',
    (tester) async {
      const directory = String.fromEnvironment('FLUID_ARTIFACT_DIRECTORY');
      if (directory.isEmpty) return;
      await tester.runAsync(() async {
        await Directory(directory).create(recursive: true);
        final shader = (await ui.FragmentProgram.fromAsset(
          'shaders/fluid_background.frag',
        )).fragmentShader();
        final palette = buildWeightedFluidPalette(
          _pigments,
          fallbackSeed: Colors.blue,
        );
        final controller = FluidBackgroundController(
          vsync: const TestVSync(),
          initialPalette: palette,
        );
        try {
          for (final seconds in [0.0, 24.0, 48.0, 72.0]) {
            // The painter writes all palette uniforms; then set the explicit
            // phase/motion for reproducible snapshots, not a simulated clock.
            final uniformRecorder = ui.PictureRecorder();
            FluidBackgroundPainter(
              shader: shader,
              controller: controller,
              dim: .3,
            ).paint(Canvas(uniformRecorder), const Size(384, 640));
            uniformRecorder.endRecording().dispose();
            FluidFrameUniforms().write(
              shader,
              size: const Size(384, 640),
              time: seconds,
              motion: 1,
              dim: .3,
              source: palette,
              target: palette,
            );
            // DisplayList snapshots shader uniforms at draw time, not at the
            // eventual toImage call. Set explicit phase BEFORE recording.
            final recorder = ui.PictureRecorder();
            Canvas(recorder).drawRect(
              const Rect.fromLTWH(0, 0, 384, 640),
              Paint()..shader = shader,
            );
            final picture = recorder.endRecording();
            final image = await picture.toImage(384, 640);
            try {
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '$directory/phase-${seconds.toInt()}.png',
              ).writeAsBytes(data!.buffer.asUint8List());
            } finally {
              image.dispose();
              picture.dispose();
            }
          }
        } finally {
          shader.dispose();
          controller.dispose();
        }
      });
    },
  );
  test(
    'highlight rejection uses both thresholds, not brightness or low chroma alone',
    () {
      final palette = buildFluidPalette([
        const HSLColor.fromAHSL(1, 280, .50, .90).toColor(),
        const HSLColor.fromAHSL(1, 210, .10, .50).toColor(),
        const Color(0xFF25BFA3),
        Colors.black,
      ], fallbackSeed: Colors.orange);
      final colours = palette.colors.map(HSLColor.fromColor);
      expect(colours.any((c) => c.hue > 270 && c.hue < 290), isTrue);
      expect(
        colours.any((c) => c.saturation < .20 && c.lightness > .10),
        isTrue,
      );
      expect(palette.colors, contains(Colors.black));
    },
  );

  test(
    'bright white artwork preserves pigment hues while lifting the canvas',
    () {
      final clean = buildWeightedFluidPalette(
        _pigments,
        fallbackSeed: Colors.blue,
      );
      final padded = buildWeightedFluidPalette([
        const FluidColorSample(Color(0xFFEFEDEB), .80),
        ..._pigments.map((s) => FluidColorSample(s.color, s.proportion * .20)),
      ], fallbackSeed: Colors.blue);
      expect(padded.colors, isNot(contains(Colors.black)));
      expect(
        HSLColor.fromColor(padded.baseColor).lightness,
        greaterThan(HSLColor.fromColor(clean.baseColor).lightness),
      );
      final lead = HSLColor.fromColor(padded.second);
      expect(lead.saturation, greaterThan(.6));
      expect(lead.hue, closeTo(HSLColor.fromColor(clean.second).hue, 3));
      expect(lead.lightness, inInclusiveRange(.345, .555));
      final aligned = alignFluidPaletteSlots(
        FluidPalette(padded.second, padded.fourth, padded.first, padded.third),
        padded,
      );
      expect(aligned.second, padded.second);
      expect(aligned.third, padded.third);
    },
  );

  testWidgets('worker filters white pixels before histogram selection', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawColor(const Color(0xFFEFEDEB), BlendMode.src);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 16, 64),
        Paint()..color = const Color(0xFFEF2683),
      );
      canvas.drawRect(
        const Rect.fromLTWH(16, 0, 8, 64),
        Paint()..color = const Color(0xFF25BFA3),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(64, 64);
      final png = (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
      image.dispose();
      picture.dispose();
      final palette = await ArtworkPaletteCache().resolve(
        key: 'white-padding',
        bytes: png,
        fallbackSeed: Colors.blue,
      );
      expect(
        palette.colors.every((c) => HSLColor.fromColor(c).saturation > .6),
        isTrue,
      );
      expect(
        HSLColor.fromColor(palette.second).lightness,
        lessThanOrEqualTo(.555),
      );
    });
  });

  test('all-white and all-black covers stay achromatic, not seed-coloured', () {
    for (final color in [Colors.white, const Color(0xFFEFEDEB), Colors.black]) {
      final palette = buildFluidPalette([color], fallbackSeed: Colors.pink);
      expect(
        palette.colors.every((c) => HSLColor.fromColor(c).saturation < .01),
        isTrue,
      );
    }
  });

  testWidgets(
    'production shader follows four-field convex mixing and retains pigments',
    (tester) async {
      await tester.runAsync(() async {
        final shader = (await ui.FragmentProgram.fromAsset(
          'shaders/fluid_background.frag',
        )).fragmentShader();
        try {
          const palette = FluidPalette(
            Color(0xFFEE2288),
            Color(0xFFEE2288),
            Color(0xFFFFB820),
            Color(0xFF22BF9C),
            baseColor: Color(0xFF721943),
          );
          final bytes = await _render(shader, palette);
          final packed = FluidFrameUniforms();
          packed.write(
            shader,
            size: const Size(96, 160),
            time: 0,
            motion: 0,
            dim: .3,
            source: palette,
            target: palette,
          );
          var saturation = 0.0;
          var oldSaturation = 0.0;
          for (var y = 0; y < 160; y++) {
            for (var x = 0; x < 96; x++) {
              final i = (y * 96 + x) * 4;
              final actual = Color.fromARGB(
                255,
                bytes[i],
                bytes[i + 1],
                bytes[i + 2],
              );
              saturation += HSLColor.fromColor(actual).saturation;
              final old = _screenOracle(palette, (x + .5) / 96, (y + .5) / 160);
              oldSaturation += HSLColor.fromColor(
                Color.from(alpha: 1, red: old[0], green: old[1], blue: old[2]),
              ).saturation;
              if (x % 12 == 0 && y % 20 == 0) {
                final expected = _layerOracle(
                  palette,
                  (x + .5) / 96,
                  (y + .5) / 160,
                  packed.values,
                );
                for (var channel = 0; channel < 3; channel++) {
                  expect(
                    bytes[i + channel],
                    closeTo(expected[channel] * 255, 2),
                    reason: '$x,$y channel $channel',
                  );
                }
                expect(bytes[i + 3], 255);
              }
            }
          }
          // Same synthetic pigments/grid as the old Screen diagnostic. This is
          // not an album measurement or a global saturation guarantee.
          // Wider four-field joins reduce this sample's chroma; reject washout
          // without restoring the previous, narrower pigment boundaries.
          expect(saturation / (96 * 160), greaterThan(.35));
          debugPrint(
            'Synthetic grid HSL saturation: orbital=${saturation / (96 * 160)}, old Screen=${oldSaturation / (96 * 160)}',
          );
          // Slot zero now owns a real fourth field; it changes pigment, not
          // additive light. Simple covers may still repeat an extracted colour.
          final metadata = await _render(
            shader,
            FluidPalette(
              Colors.white,
              palette.second,
              palette.third,
              palette.fourth,
              baseColor: palette.baseColor,
            ),
          );
          expect(metadata, isNot(bytes));
          // The base supports every field's veil rather than making black holes.
          final differentBase = await _render(
            shader,
            FluidPalette(
              palette.first,
              palette.second,
              palette.third,
              palette.fourth,
              baseColor: Colors.black,
            ),
          );
          expect(differentBase, isNot(bytes));
          // Equal pigments must stay that hue where both masks overlap.
          final same = await _render(
            shader,
            FluidPalette(
              palette.first,
              palette.first,
              baseColor: palette.first,
              palette.first,
              palette.first,
            ),
          );
          const centre = (80 * 96 + 48) * 4;
          expect(
            HSLColor.fromColor(
              Color.fromARGB(
                255,
                same[centre],
                same[centre + 1],
                same[centre + 2],
              ),
            ).saturation,
            greaterThan(.70),
          );
        } finally {
          shader.dispose();
        }
      });
    },
  );
}

Future<Uint8List> _render(
  ui.FragmentShader shader,
  FluidPalette palette, {
  double time = 0,
  double motion = 0,
}) async {
  final controller = FluidBackgroundController(
    vsync: const TestVSync(),
    initialPalette: palette,
  );
  final setup = ui.PictureRecorder();
  FluidBackgroundPainter(
    shader: shader,
    controller: controller,
    dim: .3,
  ).paint(Canvas(setup), const Size(96, 160));
  setup.endRecording().dispose();
  FluidFrameUniforms().write(
    shader,
    size: const Size(96, 160),
    time: time,
    motion: motion,
    dim: .3,
    source: palette,
    target: palette,
  );
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(0, 0, 96, 160), Paint()..shader = shader);
  final picture = recorder.endRecording();
  final image = await picture.toImage(96, 160);
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

// Independent scalar oracle, with motion=0/time=0 from the production painter.
List<double> _layerOracle(
  FluidPalette palette,
  double x,
  double y,
  Float32List packed,
) {
  final weights = fluidReferenceWeights(packed, x, y);
  final sum = weights.reduce((a, b) => a + b);
  final distance = math.sqrt(math.pow(x - .5, 2) + math.pow(y - .48, 2));
  final edge = ((distance - .35) / (1.10 - .35)).clamp(0.0, 1.0);
  final vignette = 1 - edge * edge * (3 - 2 * edge);
  return List<double>.generate(3, (channel) {
    double component(Color c) => [c.r, c.g, c.b][channel];
    double lerp(double a, double b, double mask) => a + (b - a) * mask;
    final colours = [
      for (var field = 0; field < 4; field++) packed[14 + field * 3 + channel],
    ];
    var pigment = 0.0;
    for (var i = 0; i < 4; i++) {
      pigment += colours[i] * weights[i] / math.max(sum, .00001);
    }
    final mixed = lerp(component(palette.baseColor), pigment, .84);
    return mixed * (.98 + .02 * vignette) * (1 - .3 * .25);
  });
}

List<double> _screenOracle(FluidPalette palette, double x, double y) {
  const centres = [(.28, .24), (.72, .32), (.30, .76), (.74, .74)];
  const radii = [(.85, 1.05), (.80, .95), (.75, .95), (.80, 1.00)];
  const gains = [1.0, 1.0, 1.35, 1.15];
  final distance = math.sqrt(math.pow(x - .5, 2) + math.pow(y - .48, 2));
  final edge = ((distance - .35) / .75).clamp(0.0, 1.0);
  final vignette = 1 - edge * edge * (3 - 2 * edge);
  return List<double>.generate(3, (channel) {
    double component(Color c) => [c.r, c.g, c.b][channel];
    var transmission = 1.0;
    for (var i = 0; i < 4; i++) {
      final dx = (x - centres[i].$1) / radii[i].$1;
      final dy = (y - centres[i].$2) / radii[i].$2;
      final field = math.exp(
        -math.pow(math.max(dx * dx + dy * dy, .00001), .65) * 1.25,
      );
      transmission *=
          1 -
          math.min(
            component(palette[i]) * field * palette.glowStrength * gains[i],
            .98,
          );
    }
    return ((1 - (1 - component(palette.baseColor)) * transmission) *
            (.90 + .15 * vignette) *
            .925)
        .clamp(0.0, 1.0);
  });
}
