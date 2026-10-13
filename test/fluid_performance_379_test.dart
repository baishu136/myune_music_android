import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/widgets/playback_background/fluid_background.dart';
import 'package:myune_music/widgets/playback_background/fluid_background_painter.dart';
import 'package:myune_music/widgets/playback_background/playback_background.dart';

void main() {
  testWidgets(
    'outgoing fluid retains its State but stops repainting during fade',
    (tester) async {
      await tester.runAsync(
        () => FluidPlaybackBackground.prewarm(
          bytes: Uint8List(0),
          identity: 'performance-probe',
          cacheGeneration: 0,
          fallbackSeed: Colors.teal,
        ),
      );
      Widget host(PlaybackArtworkBackgroundStyle style) => MaterialApp(
        home: PlaybackBackground(
          style: style,
          artworkIdentity: 'performance-probe',
          artworkCacheGeneration: 0,
          routeTransitionActive: false,
          fluidQuality: FluidBackgroundQuality.automatic,
          fallbackSeed: Colors.teal,
          path: null,
          customImageEnabled: false,
          customImageDim: 0,
          customImageBlur: 0,
          coverBytes: null,
          coverEnabled: true,
          coverDim: .3,
          coverBlur: 20,
          usePlaybackTheme: true,
          child: const SizedBox.expand(),
        ),
      );
      await tester.pumpWidget(host(PlaybackArtworkBackgroundStyle.fluid));
      await tester.pump(const Duration(milliseconds: 20));
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('fluid-background-shader')),
                  )
                  .painter!
              as FluidBackgroundPainter;
      final controller = painter.controller;
      var repaints = 0;
      controller.addListener(() => repaints++);
      final before = controller.isTicking;
      await tester.pumpWidget(host(PlaybackArtworkBackgroundStyle.blurred));
      final onExit = controller.isTicking;
      repaints =
          0; // The exit-start frame may have ticked before its widget build.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final duringExit = controller.isTicking;
      final visibleOutgoing = find
          .byType(FluidPlaybackBackground)
          .evaluate()
          .length;
      expect(before, isTrue);
      expect(onExit, isFalse);
      expect(duringExit, isFalse);
      expect(visibleOutgoing, 1);
      expect(repaints, 0);
      final outgoingPainter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('fluid-background-shader')),
                  )
                  .painter!
              as FluidBackgroundPainter;
      expect(
        outgoingPainter.controller,
        same(controller),
        reason: 'freeze without remounting',
      );
      await tester.pumpWidget(host(PlaybackArtworkBackgroundStyle.fluid));
      await tester.pump(const Duration(milliseconds: 16));
      final painters = tester.widgetList<CustomPaint>(
        find.byKey(const ValueKey('fluid-background-shader')),
      );
      expect(
        painters.any(
          (p) => (p.painter! as FluidBackgroundPainter).controller.isTicking,
        ),
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(FluidPlaybackBackground), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
}
