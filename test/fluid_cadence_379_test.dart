import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/services/fluid_background_controller.dart';

void main() {
  testWidgets(
    'a surface refresh increase respects the budget during relearning',
    (tester) async {
      final controller = FluidBackgroundController(
        vsync: const TestVSync(),
        initialPalette: FluidPalette.fallback(const Color(0xFF008080)),
      );
      controller.updateOperatingState(
        enabled: true,
        visible: true,
        foreground: true,
        reduceMotion: false,
        routeTransitionActive: false,
        quality: FluidBackgroundQuality.automatic,
        displayRefreshRate: 120,
      );
      var elapsed = 0, lastPaint = 0;
      final intervals = <int>[];
      controller.addListener(() {
        if (lastPaint != 0) intervals.add(elapsed - lastPaint);
        lastPaint = elapsed;
      });
      for (var i = 0; i < 24; i++) {
        elapsed += 16667;
        await tester.pump(const Duration(microseconds: 16667));
      }
      intervals.clear();
      for (var i = 0; i < 24; i++) {
        elapsed += 8333;
        await tester.pump(const Duration(microseconds: 8333));
      }
      controller.dispose();
      await tester.pump();
      expect(intervals, isNotEmpty);
      expect(intervals.every((micros) => micros >= 15833), isTrue);
    },
  );
  testWidgets(
    'measure production controller cadence at fixed simulated vsync',
    (tester) async {
      final records = <Map<String, Object>>[];
      for (final quality in FluidBackgroundQuality.values) {
        for (final hz in [60, 90, 120]) {
          final controller = FluidBackgroundController(
            vsync: const TestVSync(),
            initialPalette: FluidPalette.fallback(const Color(0xFF008080)),
          );
          var ticks = 0, previous = 0, paints = 0;
          final intervals = <int, int>{};
          controller.addListener(() {
            paints++;
            if (previous != 0 && ticks > 24) {
              final interval = ticks - previous;
              intervals[interval] = (intervals[interval] ?? 0) + 1;
            }
            previous = ticks;
          });
          controller.updateOperatingState(
            enabled: true,
            visible: true,
            foreground: true,
            reduceMotion: false,
            routeTransitionActive: false,
            quality: quality,
            displayRefreshRate: hz.toDouble(),
          );
          final period = Duration(microseconds: (1000000 / hz).round());
          for (var i = 0; i < hz * 10; i++) {
            ticks++;
            await tester.pump(period);
          }
          final expectedDivisor = quality == FluidBackgroundQuality.powerSaving
              ? {60: 3, 90: 4, 120: 5}[hz]!
              : quality == FluidBackgroundQuality.automatic && hz > 60
              ? 2
              : 1;
          expect(intervals.keys, [expectedDivisor], reason: '$quality / $hz');
          expect(controller.effectiveTime, closeTo(10, .06));
          records.add({
            'quality': quality.name,
            'simulatedDisplayHz': hz,
            'configuredFps': FluidBackgroundConfig.forQuality(
              quality,
            ).framesPerSecond,
            'paintsInTenSeconds': paints,
            'averagePaintFps': paints / 10,
            'vsyncTicksBetweenPaints': intervals.map(
              (k, v) => MapEntry('$k', v),
            ),
            'effectiveTimeSeconds': controller.effectiveTime,
          });
          controller.dispose();
          await tester.pump();
        }
      }
      expect(records, hasLength(9));
    },
  );
  testWidgets('actual 60Hz callbacks override a nominal 120Hz panel', (
    tester,
  ) async {
    final controller = FluidBackgroundController(
      vsync: const TestVSync(),
      initialPalette: FluidPalette.fallback(const Color(0xFF008080)),
    );
    controller.updateOperatingState(
      enabled: true,
      visible: true,
      foreground: true,
      reduceMotion: false,
      routeTransitionActive: false,
      quality: FluidBackgroundQuality.automatic,
      displayRefreshRate: 120,
    );
    var callbacks = 0;
    controller.addListener(() => callbacks++);
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(microseconds: 16667));
    }
    callbacks = 0;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(microseconds: 16667));
    }
    expect(callbacks, 60);
    controller.dispose();
    await tester.pump();
  });
}
