import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/services/artwork_palette_cache.dart';
import 'package:myune_music/services/fluid_background_controller.dart';

void main() {
  test(
    'dark chromatic artwork has an OLED-depth base without invented light',
    () {
      final palette = buildWeightedFluidPalette(const [
        FluidColorSample(Color(0xFF102A3D), .75),
        FluidColorSample(Color(0xFF183344), .20),
        FluidColorSample(Color(0xFF715248), .05),
      ], fallbackSeed: Colors.pink);
      expect(HSLColor.fromColor(palette.baseColor).lightness, lessThan(.015));
      expect(
        palette.colors.every((c) => HSLColor.fromColor(c).lightness <= .38),
        isTrue,
      );
    },
  );

  test('vivid artwork supplies two actual contrasting pigments', () {
    final palette = buildWeightedFluidPalette(const [
      FluidColorSample(Color(0xFFEF2683), .40),
      FluidColorSample(Color(0xFF25BFA3), .30),
      FluidColorSample(Color(0xFFF09D2C), .20),
      FluidColorSample(Color(0xFF58687B), .10),
    ], fallbackSeed: Colors.blue);
    for (final color in [palette.second, palette.fourth]) {
      final hsl = HSLColor.fromColor(color);
      expect(hsl.saturation, inInclusiveRange(.65, .95));
      expect(hsl.lightness, inInclusiveRange(.345, .555));
    }
    final a = HSLColor.fromColor(palette.second),
        b = HSLColor.fromColor(palette.fourth);
    final delta = (a.hue - b.hue).abs();
    expect(delta > 180 ? 360 - delta : delta, greaterThan(90));
    final aligned = alignFluidPaletteSlots(
      FluidPalette(
        palette.fourth,
        palette.third,
        palette.first,
        palette.second,
      ),
      palette,
    );
    expect(aligned.second, palette.second);
    expect(aligned.fourth, palette.fourth);
    expect(aligned.third, palette.third);
  });

  testWidgets(
    'ambient clock stays real-time across quality and rhythm changes',
    (tester) async {
      final controller = FluidBackgroundController(
        vsync: const TestVSync(),
        initialPalette: FluidPalette.fallback(Colors.blue),
      );
      addTearDown(controller.dispose);
      for (final quality in FluidBackgroundQuality.values) {
        controller.updateOperatingState(
          enabled: true,
          visible: true,
          foreground: true,
          reduceMotion: false,
          routeTransitionActive: false,
          quality: quality,
        );
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));
        final start = controller.effectiveTime;
        for (var frame = 0; frame < 60; frame++) {
          controller.setRhythmMotion(frame.isEven ? .68 : 1.72);
          await tester.pump(const Duration(microseconds: 16667));
        }
        expect(controller.effectiveTime - start, closeTo(1.00002, .0001));
      }
      final before = controller.effectiveTime;
      controller.updateOperatingState(
        enabled: true,
        visible: true,
        foreground: false,
        reduceMotion: false,
        routeTransitionActive: false,
        quality: FluidBackgroundQuality.smooth,
      );
      await tester.pump(const Duration(seconds: 10));
      expect(controller.effectiveTime, before);
      expect(fluidPhaseCycle, inInclusiveRange(64, 65));
    },
  );
}
