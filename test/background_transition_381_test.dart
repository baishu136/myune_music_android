import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/services/fluid_background_controller.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/widgets/fullscreen_swipe_song_hint.dart';

FluidPalette solid(Color color) =>
    FluidPalette(color, color, color, color, baseColor: color);

void main() {
  test('wide palette spans get more time with bounded smooth endpoints', () {
    final black = solid(Colors.black);
    final near = solid(const Color(0xff050505));
    final white = solid(Colors.white);
    expect(fluidPaletteTransitionDuration(black, black).inMilliseconds, 650);
    expect(fluidPaletteTransitionDuration(black, white).inMilliseconds, 1400);
    expect(
      fluidPaletteTransitionDuration(black, near).inMilliseconds,
      lessThan(700),
    );
    const curve = BackgroundColorBlendCurve();
    expect(curve.transform(0), 0);
    expect(curve.transform(1), 1);
    expect(curve.transform(.001), lessThan(.000001));
    expect(1 - curve.transform(.999), lessThan(.000001));
  });

  testWidgets(
    'a large span bounds frame colour change and rapid retarget is continuous',
    (tester) async {
      final controller = FluidBackgroundController(
        vsync: const TestVSync(),
        initialPalette: solid(Colors.black),
      );
      controller.updateOperatingState(
        enabled: true,
        visible: true,
        foreground: true,
        reduceMotion: false,
        routeTransitionActive: false,
        quality: FluidBackgroundQuality.smooth,
      );
      controller.setPalette(solid(Colors.white));
      var previous = 0.0, maximum = 0.0;
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final current = controller.currentPalette.first.r;
        final step = (current - previous).abs();
        if (step > maximum) maximum = step;
        previous = current;
      }
      expect(maximum, lessThan(.023));
      expect(controller.paletteProgress, 1);
      controller.setPalette(solid(Colors.black));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final shown = controller.currentPalette;
      final phase = controller.effectiveTime;
      controller.setPalette(solid(Colors.red));
      expect(controller.currentPalette, shown);
      expect(controller.effectiveTime, phase);
      controller.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'text-only hint has fixed 24 font and follows song handoff direction',
    (tester) async {
      final signal = FullscreenSwipeSongHintController();
      final a = Song(title: 'Title A', artist: 'Artist A', filePath: '/a');
      final b = Song(title: 'Title B', artist: 'Artist B', filePath: '/b');
      Future<void> host(Song song) => tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Align(
              alignment: Alignment.topLeft,
              child: FullscreenSwipeSongHint(
                enabled: true,
                currentSongIdentity: song.normalizedPath,
                songChanges: signal,
              ),
            ),
          ),
        ),
      );
      double x() => tester
          .widget<Transform>(
            find.byKey(const ValueKey('fullscreen-swipe-song-hint-slide')),
          )
          .transform
          .storage[12];
      await host(a);
      signal.show(a);
      await tester.pump();
      expect(x(), 20);
      await tester.pump(const Duration(milliseconds: 240));
      expect(x(), 0);
      for (final label in [a.title, a.artist]) {
        final text = tester.widget<Text>(find.text(label));
        expect(text.style!.fontSize, 24);
        expect(text.textScaler, TextScaler.noScaling);
      }
      expect(find.byType(Image), findsNothing);
      signal.beginSwitch(next: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(x(), lessThan(0));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text(a.title), findsNothing);
      signal.show(b);
      await host(b);
      expect(x(), 20);
      await tester.pump(const Duration(milliseconds: 240));
      signal.beginSwitch(next: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      signal.show(a);
      await host(a);
      expect(x(), -20);
      await tester.pump(const Duration(milliseconds: 240));
      await tester.pump(const Duration(milliseconds: 1960));
      await tester.pump(const Duration(milliseconds: 70));
      expect(
        x(),
        greaterThan(0),
        reason: 'expiry always exits quickly to the right',
      );
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text(a.title), findsNothing);
      await tester.pumpWidget(const SizedBox());
      signal.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
