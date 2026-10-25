import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/services/artwork_palette_cache.dart';
import 'package:myune_music/widgets/playback_background/fluid_colour_motion.dart';
import 'package:myune_music/widgets/playback_background/fluid_frame_uniforms.dart';

FluidPalette _constantFields() => FluidPalette(
  const Color(0xff48778a),
  const Color(0xffc94765),
  const Color(0xff328d78),
  const Color(0xffac794a),
  motionColors: List.generate(
    32,
    (i) => const [
      Color(0xffc94765),
      Color(0xff328d78),
      Color(0xff48778a),
      Color(0xffac794a),
    ][i ~/ 8],
  ),
);

void main() {
  test('final artwork pigments gain ten percent saturation once', () {
    for (final colour in [
      const HSLColor.fromAHSL(1, 205, .36, .44).toColor(),
      const HSLColor.fromAHSL(1, 325, .68, .40).toColor(),
      const HSLColor.fromAHSL(1, 35, .95, .38).toColor(),
    ]) {
      final originals = selectDominantFluidColors([
        colour,
      ], fallbackSeed: Colors.blue).map(HSLColor.fromColor).toList();
      final palette = buildFluidPalette([colour], fallbackSeed: Colors.blue);
      for (final colour in palette.colors) {
        final actual = HSLColor.fromColor(colour);
        final original = originals.reduce(
          (a, b) =>
              (a.lightness - actual.lightness).abs() <
                  (b.lightness - actual.lightness).abs()
              ? a
              : b,
        );
        expect(
          actual.saturation,
          closeTo(math.min(1, original.saturation * 1.10), .006),
        );
        expect(actual.lightness, closeTo(original.lightness, .004));
        expect((actual.hue - original.hue).abs(), lessThan(1));
      }
    }
  });

  test('relay peaks are staggered, bounded and continuous at clock wrap', () {
    for (var field = 0; field < 4; field++) {
      final peak = ((field + 1) * math.pi / 2) / fluidShaderTimeScale;
      expect(fluidColourRelayWeight(peak, field, 1), closeTo(.24, 1e-12));
      expect(fluidColourRelayWeight(peak + fluidOrbitPeriod / 2, field, 1), 0);
      expect(fluidColourRelayWeight(peak, field, 0), 0);
      const h = .0001;
      const t = fluidPhaseCycle;
      final before = fluidColourRelayWeight(t - h, field, 1);
      final at = fluidColourRelayWeight(0, field, 1);
      final after = fluidColourRelayWeight(h, field, 1);
      expect((at - before) - (after - at), closeTo(0, 1e-9));
    }
    for (final hz in [60, 90, 120]) {
      for (var frame = 0; frame <= hz * 43; frame++) {
        final time = frame / hz;
        var total = 0.0;
        for (var field = 0; field < 4; field++) {
          final w = fluidColourRelayWeight(time, field, 1);
          expect(w, inInclusiveRange(0, .24));
          total += w;
        }
        expect(total, closeTo(.48, 1e-12));
      }
    }
  });

  test('relay preserves neutral artwork and does not mutate input buffers', () {
    final original = Float64List.fromList([
      .10,
      .10,
      .10,
      .32,
      .32,
      .32,
      .50,
      .50,
      .50,
      .21,
      .21,
      .21,
    ]);
    final snapshot = original.toList();
    final packed = Float32List(45)
      ..[0] = 180
      ..[1] = 320;
    for (var frame = 0; frame <= 600; frame++) {
      writeFluidColourRelay(original, packed, frame / 10, 1);
      for (var field = 0; field < 4; field++) {
        final c = 14 + field * 3;
        expect(packed[c], packed[c + 1]);
        expect(packed[c], packed[c + 2]);
      }
    }
    expect(original, snapshot);
    writeFluidColourRelay(original, packed, 12, 0);
    for (var i = 0; i < 12; i++) {
      expect(packed[14 + i], closeTo(original[i], 1e-7));
    }
    for (final neutral in [Colors.white, Colors.black, Colors.grey]) {
      expect(fluidSaturationBoost(neutral), neutral);
    }
  });

  testWidgets('constant-colour fields gradually receive their neighbours', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/fluid_background.frag',
      );
      final shader = program.fragmentShader();
      final packed = FluidFrameUniforms(), palette = _constantFields();
      try {
        final seen = List<bool>.filled(4, false);
        final first = Float32List(12), last = Float32List(12);
        for (var frame = 0; frame <= 60 * 42; frame++) {
          packed.write(
            shader,
            size: const Size(180, 320),
            time: frame / 60,
            motion: 1,
            dim: .3,
            source: palette,
            target: palette,
          );
          for (var f = 0; f < 4; f++) {
            final own = palette.motionColor(f, 0);
            final difference =
                (packed.values[14 + f * 3] - own.r).abs() +
                (packed.values[15 + f * 3] - own.g).abs() +
                (packed.values[16 + f * 3] - own.b).abs();
            if (difference > .025) seen[f] = true;
            for (var c = 0; c < 3; c++) {
              final v = packed.values[14 + f * 3 + c];
              expect(v, inInclusiveRange(0, 1));
              if (frame == 0) first[f * 3 + c] = v;
              if (frame > 0) {
                expect((v - last[f * 3 + c]).abs(), lessThan(.002));
              }
              last[f * 3 + c] = v;
            }
          }
        }
        expect(seen, everyElement(isTrue));
        packed.write(
          shader,
          size: const Size(180, 320),
          time: 0,
          motion: 1,
          dim: .3,
          source: palette,
          target: palette,
        );
        expect(packed.values.sublist(14, 26), first);
      } finally {
        shader.dispose();
      }
    });
  });
}
