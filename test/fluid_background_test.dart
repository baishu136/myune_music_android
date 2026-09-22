import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/services/artwork_palette_cache.dart';
import 'package:myune_music/services/fluid_background_controller.dart';
import 'package:myune_music/widgets/playback_background/playback_background.dart';

void main() {
  test('fluid phase only wraps at the shader harmonic cycle', () {
    expect(wrapFluidPhase(math.pi * 2 + .1), greaterThan(math.pi * 2));
    expect(wrapFluidPhase(fluidPhaseCycle + .1), closeTo(.1, .000001));
  });

  test('fluid motion is doubled again without increasing frame cadence', () {
    final powerSaving = FluidBackgroundConfig.forQuality(
      FluidBackgroundQuality.powerSaving,
    );
    final automatic = FluidBackgroundConfig.forQuality(
      FluidBackgroundQuality.automatic,
    );
    final smooth = FluidBackgroundConfig.forQuality(
      FluidBackgroundQuality.smooth,
    );

    expect(
      (powerSaving.framesPerSecond, powerSaving.motionPeriodSeconds),
      (24, 6.5),
    );
    expect(
      (automatic.framesPerSecond, automatic.motionPeriodSeconds),
      (30, 5.5),
    );
    expect((smooth.framesPerSecond, smooth.motionPeriodSeconds), (60, 4.625));
  });

  test('unknown background preferences safely keep the legacy defaults', () {
    expect(
      decodePlaybackArtworkBackgroundStyle('future-value'),
      PlaybackArtworkBackgroundStyle.blurred,
    );
    expect(
      decodeFluidBackgroundQuality('future-value'),
      FluidBackgroundQuality.automatic,
    );
  });

  test(
    'palette selection keeps meaningful black but ignores white padding',
    () {
      final palette = buildFluidPalette(const [
        Colors.black,
        Colors.white,
        Color(0xFF1565C0),
        Color(0xFFE65100),
        Color(0xFF2E7D32),
        Color(0xFF6A1B9A),
      ], fallbackSeed: Colors.teal);
      expect(palette.colors, hasLength(4));
      expect(palette.colors, contains(Colors.black));
      expect(palette.colors, isNot(contains(Colors.white)));
      expect(palette.colors.toSet().length, greaterThanOrEqualTo(3));
    },
  );

  test('dominant colour selection stays between three and six colours', () {
    final selected = selectDominantFluidColors(const [
      Color(0xFFB71C1C),
      Color(0xFF0D47A1),
      Color(0xFF1B5E20),
      Color(0xFFF57F17),
      Color(0xFF4A148C),
      Color(0xFF006064),
      Color(0xFF3E2723),
      Color(0xFF263238),
    ], fallbackSeed: Colors.teal);

    expect(selected.length, 6);
    expect(selected.toSet(), hasLength(6));
    expect(
      selectDominantFluidColors(const [
        Color(0xFF102344),
      ], fallbackSeed: Colors.teal).length,
      3,
    );
  });

  test(
    'dark artwork keeps its hue and is not forced into a bright palette',
    () {
      final palette = buildFluidPalette(const [
        Colors.black,
        Color(0xFF071126),
        Color(0xFF102344),
        Color(0xFF1B0D2E),
      ], fallbackSeed: Colors.teal);
      final colors = palette.colors.map(HSLColor.fromColor).toList();

      expect(colors.any((color) => color.hue > 190 && color.hue < 260), isTrue);
      expect(palette.colors, contains(Colors.black));
      expect(colors.every((color) => color.lightness <= .50), isTrue);
    },
  );

  test('fluid palette keeps four colours independent of artwork occupancy', () {
    final palette = buildWeightedFluidPalette(const [
      FluidColorSample(Color(0xFF1565C0), .94),
      FluidColorSample(Color(0xFFE65100), .03),
      FluidColorSample(Color(0xFF2E7D32), .02),
      FluidColorSample(Color(0xFF6A1B9A), .01),
    ], fallbackSeed: Colors.teal);

    expect(palette.colors, hasLength(4));
    expect(palette.colors.toSet(), hasLength(4));
    final hues = palette.colors.map((color) => HSLColor.fromColor(color).hue);
    expect(hues.any((hue) => hue > 260 && hue < 320), isTrue);
    expect(hues.any((hue) => hue > 80 && hue < 160), isTrue);
  });

  test('incoming palette slots align to the nearest current colours', () {
    const current = FluidPalette(
      Colors.red,
      Colors.green,
      Colors.blue,
      Colors.orange,
    );
    const reordered = FluidPalette(
      Colors.blue,
      Colors.orange,
      Colors.red,
      Colors.green,
    );

    expect(alignFluidPaletteSlots(current, reordered), current);
  });

  test('equal palette values do not restart a colour transition', () {
    final first = FluidPalette.fallback(Colors.indigo);
    final sameValues = FluidPalette(
      first.first,
      first.second,
      first.third,
      first.fourth,
    );
    expect(sameValues, first);
    expect(sameValues.hashCode, first.hashCode);
  });

  test(
    'palette cache identity changes with artwork content and generation',
    () {
      final first = Uint8List.fromList(List<int>.generate(128, (i) => i));
      final changed = Uint8List.fromList(first)..[64] = 7;
      final key = fluidArtworkPaletteKey('song', 1, first);
      expect(fluidArtworkPaletteKey('song', 1, changed), isNot(key));
      expect(fluidArtworkPaletteKey('song', 2, first), isNot(key));
    },
  );

  test('cached artwork palette is available before route entry', () {
    final cache = ArtworkPaletteCache();
    final palette = FluidPalette.fallback(Colors.deepOrange);
    cache.remember('song-palette', palette);

    expect(cache.peek('song-palette'), same(palette));
    expect(cache.peek('missing'), isNull);
  });

  testWidgets('route and reduced-motion state stop fluid scheduling', (
    tester,
  ) async {
    final controller = FluidBackgroundController(
      vsync: const TestVSync(),
      initialPalette: FluidPalette.fallback(Colors.blue),
    );
    addTearDown(controller.dispose);

    controller.updateOperatingState(
      enabled: true,
      visible: true,
      foreground: true,
      reduceMotion: false,
      routeTransitionActive: false,
      quality: FluidBackgroundQuality.automatic,
    );
    expect(controller.isTicking, isTrue);

    controller.updateOperatingState(
      enabled: true,
      visible: true,
      foreground: true,
      reduceMotion: false,
      routeTransitionActive: true,
      quality: FluidBackgroundQuality.automatic,
    );
    expect(controller.isTicking, isFalse);

    controller.updateOperatingState(
      enabled: true,
      visible: true,
      foreground: true,
      reduceMotion: true,
      routeTransitionActive: false,
      quality: FluidBackgroundQuality.automatic,
    );
    expect(controller.isTicking, isFalse);
  });

  testWidgets('fluid motion keeps advancing without playback state', (
    tester,
  ) async {
    final controller = FluidBackgroundController(
      vsync: const TestVSync(),
      initialPalette: FluidPalette.fallback(Colors.blue),
    );
    try {
      controller.updateOperatingState(
        enabled: true,
        visible: true,
        foreground: true,
        reduceMotion: false,
        routeTransitionActive: false,
        quality: FluidBackgroundQuality.automatic,
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 16));

      expect(controller.isTicking, isTrue);
      expect(controller.effectiveTime, greaterThan(0));
    } finally {
      controller.dispose();
      await tester.pump();
    }
  });

  testWidgets('rhythm energy changes motion speed with a smooth envelope', (
    tester,
  ) async {
    final controller = FluidBackgroundController(
      vsync: const TestVSync(),
      initialPalette: FluidPalette.fallback(Colors.blue),
    );
    try {
      controller.updateOperatingState(
        enabled: true,
        visible: true,
        foreground: true,
        reduceMotion: false,
        routeTransitionActive: false,
        quality: FluidBackgroundQuality.automatic,
      );
      controller.setRhythmMotion(1.7);
      expect(controller.rhythmMotionTarget, 1.7);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.motionScale, greaterThan(0));

      await tester.pump(const Duration(milliseconds: 600));
      expect(controller.motionScale, lessThan(controller.rhythmMotionTarget));
    } finally {
      controller.dispose();
      await tester.pump();
    }
  });

  testWidgets('fluid mode paints an immediate static fallback during entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PlaybackBackground(
          style: PlaybackArtworkBackgroundStyle.fluid,
          artworkIdentity: 'song',
          artworkCacheGeneration: 1,
          routeTransitionActive: true,
          fluidQuality: FluidBackgroundQuality.automatic,
          fallbackSeed: Colors.blue,
          path: null,
          customImageEnabled: false,
          customImageDim: .6,
          customImageBlur: 20,
          coverBytes: Uint8List.fromList([1, 2, 3]),
          coverEnabled: true,
          coverDim: .5,
          coverBlur: 40,
          usePlaybackTheme: true,
          child: const SizedBox.expand(child: Text('foreground')),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('fluid-background-static-fallback')),
      findsOneWidget,
    );
    expect(find.text('foreground'), findsOneWidget);
  });

  testWidgets('switching to cover keeps one foreground and crossfades', (
    tester,
  ) async {
    final artwork = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    var style = PlaybackArtworkBackgroundStyle.fluid;
    late StateSetter updateHost;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return PlaybackBackground(
              style: style,
              artworkIdentity: 'switch-song',
              artworkCacheGeneration: 1,
              routeTransitionActive: true,
              fluidQuality: FluidBackgroundQuality.automatic,
              fallbackSeed: Colors.blue,
              path: null,
              customImageEnabled: false,
              customImageDim: .6,
              customImageBlur: 20,
              coverBytes: artwork,
              coverEnabled: true,
              coverDim: .5,
              coverBlur: 40,
              usePlaybackTheme: true,
              child: const SizedBox.expand(child: Text('single foreground')),
            );
          },
        ),
      ),
    );
    updateHost(() => style = PlaybackArtworkBackgroundStyle.blurred);
    await tester.pump();
    expect(find.text('single foreground'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('fluid-background-static-fallback')),
      findsOneWidget,
    );

    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(find.text('single foreground'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cover-follow-background')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('fluid-background-static-fallback')),
      findsNothing,
    );
  });
}
