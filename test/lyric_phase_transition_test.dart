import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/lyric_normalized_motion.dart';
import 'package:myune_music/widgets/lyric_phase_transition.dart';

void main() {
  testWidgets('changed curve samples old values and restarts one shared phase', (
    tester,
  ) async {
    for (final hz in [60, 90, 120]) {
      var scale = 1.0;
      var opacity = .5;
      Color color = Colors.grey;
      Curve curve = lyricTransitionCurve;
      var duration = lyricTransitionDuration;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return LyricPhaseScale(
                scale: scale,
                curve: curve,
                duration: duration,
                child: LyricPhaseOpacity(
                  opacity: opacity,
                  curve: curve,
                  duration: duration,
                  child: LyricPhaseTextStyle(
                    style: TextStyle(color: color),
                    curve: curve,
                    duration: duration,
                    child: const Text('歌词', key: ValueKey('text')),
                  ),
                ),
              );
            },
          ),
        ),
      );
      update(() {
        scale = 1.1;
        opacity = 1;
        color = Colors.white;
      });
      await tester.pump();
      for (var i = 0; i < (hz * .08).round(); i++) {
        await tester.pump(Duration(microseconds: (1000000 / hz).round()));
      }
      double renderedScale() => tester
          .widget<ScaleTransition>(find.byType(ScaleTransition))
          .scale
          .value;
      double renderedOpacity() => tester
          .widget<FadeTransition>(
            find.descendant(
              of: find.byType(LyricPhaseOpacity),
              matching: find.byType(FadeTransition),
            ),
          )
          .opacity
          .value;
      Color renderedColor() => DefaultTextStyle.of(
        tester.element(find.byKey(const ValueKey('text'))),
      ).style.color!;
      final oldScale = renderedScale();
      final oldOpacity = renderedOpacity();
      final oldColor = renderedColor();
      update(() {
        // Unchanged in-flight scale must rephase too. Alpha/style change target.
        opacity = .68;
        color = Colors.blue;
        curve = const LyricTransitionCurve(initialSlope: 1.3);
        duration = const Duration(milliseconds: 480);
      });
      await tester.pump();
      expect(renderedScale(), closeTo(oldScale, 1e-10));
      expect(renderedOpacity(), closeTo(oldOpacity, 1e-10));
      expect(renderedColor(), oldColor);
      var elapsedUs = 0;
      for (var frame = 0; frame < (hz * .48).ceil(); frame++) {
        final us = (1000000 / hz).round();
        elapsedUs += us;
        await tester.pump(Duration(microseconds: us));
        final p = curve.transform((elapsedUs / 480000).clamp(0, 1));
        expect(renderedScale(), closeTo(oldScale + (1.1 - oldScale) * p, 1e-8));
        expect(
          renderedOpacity(),
          closeTo(oldOpacity + (.68 - oldOpacity) * p, 1e-8),
        );
        final actual = renderedColor();
        final expected = Color.lerp(oldColor, Colors.blue, p)!;
        expect(actual.a, closeTo(expected.a, 1e-10));
        expect(actual.r, closeTo(expected.r, 1e-10));
        expect(actual.g, closeTo(expected.g, 1e-10));
        expect(actual.b, closeTo(expected.b, 1e-10));
      }
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
    'seek snaps a still-running unchanged target without a ghost tail',
    (tester) async {
      var scale = 1.0;
      var duration = lyricTransitionDuration;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return LyricPhaseScale(
                scale: scale,
                duration: duration,
                curve: lyricTransitionCurve,
                child: const Text('歌词'),
              );
            },
          ),
        ),
      );
      update(() => scale = 1.1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      update(() => duration = Duration.zero);
      await tester.pump();
      expect(
        tester
            .widget<ScaleTransition>(find.byType(ScaleTransition))
            .scale
            .value,
        1.1,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester
            .widget<ScaleTransition>(find.byType(ScaleTransition))
            .scale
            .value,
        1.1,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
