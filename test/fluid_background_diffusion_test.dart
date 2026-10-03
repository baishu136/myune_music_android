import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/services/artwork_palette_cache.dart';
import 'package:myune_music/services/fluid_background_controller.dart';
import 'package:myune_music/widgets/playback_background/fluid_background_painter.dart';

const _colourful = FluidPalette(
  Color(0xFFEE628B),
  Color(0xFF25BFA3),
  Color(0xFFFFBF54),
  Color(0xFF6B6F9B),
  baseColor: Color(0xFF200911),
  glowStrength: .92,
);

bool _warm(Color color) {
  final hsl = HSLColor.fromColor(color);
  return hsl.hue >= 20 && hsl.hue <= 55 && hsl.saturation >= .20;
}

void main() {
  test('real significant amber keeps slot two even after colour alignment', () {
    final palette = buildWeightedFluidPalette(const [
      FluidColorSample(Colors.black, .16),
      FluidColorSample(Color(0xFF0B9D93), .20),
      FluidColorSample(Color(0xFFEF2683), .20),
      FluidColorSample(Color(0xFFF09D2C), .15),
      FluidColorSample(Color(0xFFCC5845), .15),
      FluidColorSample(Color(0xFF58687B), .14),
    ], fallbackSeed: Colors.blue);
    expect(_warm(palette.third), isTrue);
    // Deliberately tempt the old nearest-colour permutation to move amber.
    final previous = FluidPalette(
      palette.third,
      palette.first,
      palette.second,
      palette.fourth,
    );
    expect(alignFluidPaletteSlots(previous, palette).third, palette.third);
  });

  test('cool artwork does not acquire a made-up warm accent', () {
    final palette = buildWeightedFluidPalette(const [
      FluidColorSample(Color(0xFF167EA4), .55),
      FluidColorSample(Color(0xFF202868), .30),
      FluidColorSample(Color(0xFF605798), .149),
      FluidColorSample(Color(0xFFF09D2C), .001),
    ], fallbackSeed: Colors.orange);
    // A noise pixel is not grounds for replacing a major real colour.
    expect(_warm(palette.third), isFalse);
    expect(palette.warmAccentLocked, isFalse);
  });

  testWidgets(
    'warm gradients survive top-bin pruning in actual image extraction',
    (tester) async {
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        for (var i = 0; i < 32; i++) {
          canvas.drawRect(
            Rect.fromLTWH(i * 2, 0, 2, 56),
            Paint()
              ..color = Color.fromARGB(
                255,
                16 + (i % 4) * 32,
                64 + (i ~/ 4) * 16,
                192,
              ),
          );
          canvas.drawRect(
            Rect.fromLTWH(i * 2, 56, 2, 8),
            Paint()
              ..color = HSLColor.fromAHSL(
                1,
                22 + i.toDouble(),
                .75,
                .35 + i * .008,
              ).toColor(),
          );
        }
        final picture = recorder.endRecording();
        final image = await picture.toImage(64, 64);
        try {
          final png = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
          final cache = ArtworkPaletteCache(maximumEntries: 1);
          final palette = await cache.resolve(
            key: 'warm-gradient',
            bytes: png,
            fallbackSeed: Colors.pink,
          );
          expect(palette.warmAccentLocked, isTrue);
          expect(_warm(palette.third), isTrue);
          expect(cache.length, 1);
        } finally {
          image.dispose();
          picture.dispose();
        }
      });
    },
  );

  testWidgets(
    'warm slot survives real controller retargets without colour jumps',
    (tester) async {
      final warm = buildFluidPalette(
        _colourful.colors,
        fallbackSeed: Colors.blue,
      );
      final controller = FluidBackgroundController(
        vsync: const TestVSync(),
        initialPalette: FluidPalette(
          warm.third,
          warm.first,
          warm.second,
          warm.fourth,
        ),
      );
      addTearDown(controller.dispose);
      controller.updateOperatingState(
        enabled: true,
        visible: true,
        foreground: true,
        reduceMotion: false,
        routeTransitionActive: false,
        quality: FluidBackgroundQuality.smooth,
      );
      final before = controller.currentPalette;
      controller.setPalette(warm);
      expect(controller.currentPalette, before);
      expect(controller.targetPalette.third, warm.third);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final intermediate = controller.currentPalette;
      controller.setPalette(FluidPalette.fallback(Colors.indigo));
      expect(controller.currentPalette, intermediate);
      expect(controller.targetPalette.warmAccentLocked, isFalse);
      controller.setPalette(warm);
      expect(controller.currentPalette, intermediate);
      expect(controller.targetPalette.third, warm.third);
      for (var i = 0; i < 43; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.currentPalette.third, warm.third);
      expect(controller.currentPalette.warmAccentLocked, isTrue);
      controller.updateOperatingState(
        enabled: true,
        visible: false,
        foreground: true,
        reduceMotion: false,
        routeTransitionActive: false,
        quality: FluidBackgroundQuality.smooth,
      );
      await tester.pump();
    },
  );

  test('vivid chromatic samples have light without lifting black shadows', () {
    final palette = buildWeightedFluidPalette(const [
      FluidColorSample(Color(0xFF00446B), .35),
      FluidColorSample(Color(0xFFFFC963), .35),
      FluidColorSample(Color(0xFFEF2683), .25),
      FluidColorSample(Colors.black, .05),
    ], fallbackSeed: Colors.blue);
    expect(palette.colors, contains(Colors.black));
    for (final color in palette.colors.where((c) => c != Colors.black)) {
      final hsl = HSLColor.fromColor(color);
      expect(hsl.lightness, inInclusiveRange(.375, .685));
      expect(hsl.saturation, lessThanOrEqualTo(.96));
    }
  });

  test('pale face bins cannot suppress real pink and gold printing', () {
    // Representative bins measured from the user-visible Light Mellow cover.
    final palette = buildWeightedFluidPalette(const [
      FluidColorSample(Color(0xFF008C87), .109),
      FluidColorSample(Color(0xFFF8DBDC), .084),
      FluidColorSample(Color(0xFFF3BF85), .045),
      FluidColorSample(Color(0xFFF2B13D), .035),
      FluidColorSample(Color(0xFFFEFDFD), .072),
      FluidColorSample(Color(0xFFF5B0CC), .052),
      FluidColorSample(Color(0xFFEC6945), .046),
      FluidColorSample(Color(0xFFE5314E), .034),
      FluidColorSample(Color(0xFFE32D81), .032),
    ], fallbackSeed: Colors.blue);
    expect(
      palette.colors.any((color) {
        final hsl = HSLColor.fromColor(color);
        return hsl.hue > 310 &&
            hsl.hue < 345 &&
            hsl.saturation > .55 &&
            hsl.lightness < .60;
      }),
      isTrue,
      reason: '${palette.colors.map(HSLColor.fromColor).toList()}',
    );
    expect(_warm(palette.third), isTrue);
    expect(HSLColor.fromColor(palette.third).lightness, lessThan(.66));
    expect(
      palette.colors.any((color) {
        final hsl = HSLColor.fromColor(color);
        return hsl.hue > 160 && hsl.hue < 200 && hsl.saturation > .5;
      }),
      isTrue,
    );
  });

  testWidgets('actual extraction keeps gold distinct from pale warm skin', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const samples = [
        FluidColorSample(Color(0xFF008C87), .109),
        FluidColorSample(Color(0xFFF8DBDC), .084),
        FluidColorSample(Color(0xFFF3BF85), .045),
        FluidColorSample(Color(0xFFF2B13D), .035),
        FluidColorSample(Color(0xFFF5B0CC), .052),
        FluidColorSample(Color(0xFFEC6945), .046),
        FluidColorSample(Color(0xFFE5314E), .034),
        FluidColorSample(Color(0xFFE32D81), .032),
      ];
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(Colors.white, BlendMode.src);
      var pixel = 0;
      for (final sample in samples) {
        final end = pixel + (sample.proportion * 4096).round();
        final paint = Paint()..color = sample.color;
        while (pixel < end) {
          final width = (end - pixel).clamp(1, 64 - pixel % 64);
          canvas.drawRect(
            Rect.fromLTWH(
              (pixel % 64).toDouble(),
              (pixel ~/ 64).toDouble(),
              width.toDouble(),
              1,
            ),
            paint,
          );
          pixel += width;
        }
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(64, 64);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
      image.dispose();
      picture.dispose();
      final palette = await ArtworkPaletteCache().resolve(
        key: 'skin-gold',
        bytes: bytes,
        fallbackSeed: Colors.blue,
      );
      final warm = HSLColor.fromColor(palette.third);
      expect(warm.hue, greaterThan(36));
      expect(warm.lightness, lessThan(.66));
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/fluid_background.frag',
      );
      final shader = program.fragmentShader();
      try {
        await _render(shader, palette, label: 'real-bins-colourful');
      } finally {
        shader.dispose();
      }
    });
  });

  testWidgets(
    'actual shader has broad light and a lit centre, not spotlights',
    (tester) async {
      await tester.runAsync(() async {
        final program = await ui.FragmentProgram.fromAsset(
          'shaders/fluid_background.frag',
        );
        final shader = program.fragmentShader();
        try {
          final centre = await _render(shader, _colourful, label: 'colourful');
          final centreLuma = _meanLuma(centre, 32, 56, 64, 104);
          expect(centreLuma, greaterThan(90), reason: '$centreLuma');
          // Test the complete extraction-to-shader path too. Broad diffusion
          // must not wash a vivid cover into a nearly white lyrics backdrop.
          final calibrated = await _render(
            shader,
            buildFluidPalette(_colourful.colors, fallbackSeed: Colors.blue),
            label: 'production-colourful',
          );
          final calibratedLuma = _meanLuma(calibrated, 32, 56, 64, 104);
          expect(calibratedLuma, inExclusiveRange(90, 175));
          const isolated = FluidPalette(
            Colors.white,
            Colors.black,
            Colors.black,
            Colors.black,
            baseColor: Colors.black,
            glowStrength: .70,
          );
          final broad = await _render(shader, isolated, motion: 0);
          final peak = _meanLuma(broad, 23, 30, 31, 46);
          final distant = _meanLuma(broad, 78, 128, 86, 144);
          expect(distant / peak, greaterThan(.20), reason: '$distant / $peak');
          final dim0 = await _render(shader, _colourful, dim: 0);
          final dim6 = await _render(shader, _colourful, dim: .6);
          final capped = await _render(shader, _colourful, dim: 1);
          expect(
            _meanLuma(dim6, 0, 0, 96, 160) / _meanLuma(dim0, 0, 0, 96, 160),
            closeTo(.85, .01),
          );
          expect(_meanDifference(dim6, capped), lessThan(.1));
          // Exercise the production painter, not just hand-written uniforms.
          final painted = await _render(
            shader,
            _colourful,
            dim: 0,
            motion: 0,
            productionPainter: true,
          );
          final equivalent = await _render(
            shader,
            _colourful,
            dim: 0,
            motion: 0,
          );
          expect(_meanDifference(painted, equivalent), lessThan(.1));

          // A near-full orbit still wraps all RGB channels, not just red.
          final wrapped = await _render(
            shader,
            _colourful,
            phase: fluidPhaseCycle,
          );
          expect(_meanDifference(centre, wrapped), lessThan(1));
          final preWrap = await _render(
            shader,
            _colourful,
            phase: fluidPhaseCycle - .016,
          );
          final postWrap = await _render(shader, _colourful, phase: .016);
          expect(_meanDifference(preWrap, postWrap), lessThan(.2));

          // Stable-motion frames sampled at real display intervals are gradual;
          // over twenty seconds colours still move rather than appearing stuck.
          final frame = await _render(shader, _colourful, phase: .019);
          expect(_meanDifference(centre, frame), lessThan(.2));
          final later = await _render(
            shader,
            _colourful,
            phase: 23,
            label: 'colourful-later',
          );
          expect(_meanDifference(centre, later), greaterThan(5));
        } finally {
          shader.dispose();
        }
      });
    },
  );
}

// Optional PNGs are generated test evidence, never production I/O.
Future<Uint8List> _render(
  ui.FragmentShader shader,
  FluidPalette palette, {
  double phase = 0,
  double motion = 1,
  double dim = .3,
  bool productionPainter = false,
  String? label,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (productionPainter) {
    final controller = FluidBackgroundController(
      vsync: const TestVSync(),
      initialPalette: palette,
      initialEffectiveTime: phase,
    );
    FluidBackgroundPainter(
      shader: shader,
      controller: controller,
      dim: dim,
    ).paint(canvas, const Size(96, 160));
    controller.dispose();
  } else {
    shader.setFloat(0, 96);
    shader.setFloat(1, 160);
    shader.setFloat(2, phase);
    shader.setFloat(3, motion);
    shader.setFloat(4, dim);
    shader.setFloat(5, 1);
    for (var i = 0; i < 4; i++) {
      for (final start in [6, 22]) {
        shader.setFloat(start + i * 4, palette[i].r);
        shader.setFloat(start + i * 4 + 1, palette[i].g);
        shader.setFloat(start + i * 4 + 2, palette[i].b);
        shader.setFloat(start + i * 4 + 3, 1);
      }
    }
    for (final start in [38, 42]) {
      shader.setFloat(start, palette.baseColor.r);
      shader.setFloat(start + 1, palette.baseColor.g);
      shader.setFloat(start + 2, palette.baseColor.b);
      shader.setFloat(start + 3, 1);
    }
    shader.setFloat(46, palette.glowStrength);
    shader.setFloat(47, palette.glowStrength);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 96, 160),
      Paint()..shader = shader,
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(96, 160);
  try {
    final output = Platform.environment['MYUNE_FLUID_SNAPSHOTS'];
    if (output != null && label != null) {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output/$label.png').writeAsBytes(png!.buffer.asUint8List());
    }
    return (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

double _meanLuma(Uint8List pixels, int left, int top, int right, int bottom) {
  var sum = 0.0;
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final i = (y * 96 + x) * 4;
      sum += .2126 * pixels[i] + .7152 * pixels[i + 1] + .0722 * pixels[i + 2];
    }
  }
  return sum / ((right - left) * (bottom - top));
}

double _meanDifference(Uint8List a, Uint8List b) {
  var sum = 0;
  for (var i = 0; i < a.length; i += 4) {
    for (var c = 0; c < 3; c++) {
      sum += (a[i + c] - b[i + c]).abs();
    }
  }
  return sum / (a.length / 4 * 3);
}
