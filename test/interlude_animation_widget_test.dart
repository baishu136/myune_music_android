import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/widgets/interlude_animation_widget.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';

void main() {
  for (final rate in [1.0, 2.0]) {
    testWidgets('dots exit 500 media ms early at ${rate}x without restarting',
      (tester) async {
        final seek = ValueNotifier<Duration?>(null);
        addTearDown(seek.dispose);
        var current = true;
        late StateSetter update;
        await tester.pumpWidget(MaterialApp(home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return InterludeAnimationWidget(
              isCurrent: current, baseColor: Colors.grey,
              highlightColor: Colors.white, startTime: Duration.zero,
              interludeDuration: const Duration(seconds: 8),
              currentTime: const Duration(seconds: 7), isPlaying: true,
              playbackRate: rate, seekPositionListenable: seek,
            );
          },
        )));
        double opacity() => tester.widget<FadeTransition>(
          find.byKey(const ValueKey('interlude_exit_visibility'))).opacity.value;
        await tester.pump();
        await tester.pump(Duration(microseconds: (499000 / rate).round()));
        expect(opacity(), 1);
        await tester.pump(Duration(microseconds: (1000 / rate).round()));
        await tester.pump(const Duration(milliseconds: 60));
        expect(opacity(), inExclusiveRange(0, 1));
        final during = opacity();
        update(() => current = false);
        await tester.pump();
        expect(opacity(), during, reason: 'boundary must not restart exit');
        seek.value = const Duration(seconds: 7);
        update(() => current = true);
        await tester.pump();
        expect(opacity(), 1, reason: 'seek cancels frozen exit');
        await tester.pump(const Duration(milliseconds: 250));
        if (rate == 1) expect(opacity(), 1);
        await tester.pumpWidget(const SizedBox());
      });
  }
  testWidgets('paused dots inside early-exit window do not disappear', (tester) async {
    var playing = false;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(home: StatefulBuilder(
      builder: (context, setState) {
        update = setState;
        return InterludeAnimationWidget(
          isCurrent: true, baseColor: Colors.grey,
          highlightColor: Colors.white, startTime: Duration.zero,
          interludeDuration: const Duration(seconds: 8),
          currentTime: const Duration(milliseconds: 7600), isPlaying: playing,
        );
      },
    )));
    double opacity() => tester.widget<FadeTransition>(
      find.byKey(const ValueKey('interlude_exit_visibility'))).opacity.value;
    await tester.pump(const Duration(seconds: 1));
    expect(opacity(), 1);
    update(() => playing = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(opacity(), 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('paint overflow preserves upward dots beyond their old box', (
    tester,
  ) async {
    var current = true;
    late StateSetter update;
    const capture = ValueKey('interlude_capture');
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: capture,
          child: ColoredBox(
            color: Colors.black,
            child: Center(
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return InterludeAnimationWidget(
                    isCurrent: current,
                    baseColor: Colors.white,
                    highlightColor: Colors.white,
                    startTime: Duration.zero,
                    interludeDuration: const Duration(seconds: 8),
                    currentTime: const Duration(seconds: 8),
                    isPlaying: false,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    Future<({double y, int width, int minY})> ink() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(capture),
      );
      final image = await boundary.toImage();
      try {
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        var minX = image.width, maxX = 0, minY = image.height;
        var weightedY = 0.0, weight = 0.0;
        for (var y = 0; y < image.height; y++) {
          for (var x = 0; x < image.width; x++) {
            final value = bytes[(y * image.width + x) * 4];
            if (value == 0) continue;
            weight += value;
            weightedY += y * value;
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
          }
        }
        expect(weight, greaterThan(0));
        return (y: weightedY / weight, width: maxX - minX + 1, minY: minY);
      } finally {
        image.dispose();
      }
    }

    final before = (await tester.runAsync(ink))!;
    update(() => current = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final after = (await tester.runAsync(ink))!;
    final upward = -8 * Curves.easeOutCubic.transform(.25);
    expect(after.y - before.y, closeTo(upward, 1));
    expect(after.width, lessThan(before.width));
    expect(after.minY, lessThan(before.minY));
    await tester.pumpWidget(const SizedBox());
  });
  for (final hz in [60, 90, 120]) {
    testWidgets('$hz Hz exit gathers upward without rebuild or relayout', (
      tester,
    ) async {
      var current = true;
      var builds = 0;
      final layouts = _LayoutCounts();
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: _LayoutProbe(
              counts: layouts,
              child: StatefulBuilder(
                builder: (context, setState) {
                  builds++;
                  update = setState;
                  return InterludeAnimationWidget(
                    isCurrent: current,
                    baseColor: Colors.grey,
                    highlightColor: Colors.white,
                    startTime: Duration.zero,
                    interludeDuration: const Duration(seconds: 8),
                    currentTime: current
                        ? const Duration(milliseconds: 7800)
                        : Duration.zero,
                    isPlaying: false,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      InterludeDotsPainter painter() =>
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('interlude_dots')),
                  )
                  .painter!
              as InterludeDotsPainter;
      final original = painter();
      final color = original.dotColor(2);
      final progress = original.progress;
      final size = tester.getSize(find.byKey(const ValueKey('interlude_dots')));
      update(() => current = false);
      await tester.pump();
      final startingBuilds = builds;
      final startingLayouts = layouts.count;
      expect(original.progress, progress);
      var elapsed = 0;
      var opacity = 1.0;
      var scale = 1.0;
      var dy = 0.0;
      var spacing = 6.0;
      while (elapsed < 240000) {
        final step = ((1000000 / hz).round()).clamp(1, 240000 - elapsed);
        elapsed += step;
        await tester.pump(Duration(microseconds: step));
        final p = Curves.easeOutCubic.transform(elapsed / 240000);
        expect(painter(), same(original));
        expect(original.scale, closeTo(1 - .85 * p, 1e-6));
        expect(original.dy, closeTo(-8 * p, 1e-6));
        expect(original.spacing, closeTo(6 - 5 * p, 1e-6));
        expect(original.scale, lessThanOrEqualTo(scale));
        expect(original.dy, lessThanOrEqualTo(dy));
        expect(original.spacing, lessThanOrEqualTo(spacing));
        final alpha = tester
            .widget<FadeTransition>(
              find.byKey(const ValueKey('interlude_exit_visibility')),
            )
            .opacity
            .value;
        expect(alpha, lessThanOrEqualTo(opacity));
        expect(alpha, closeTo(1 - p, 1e-6));
        if (elapsed < 240000) {
          expect(original.progress, progress);
          expect(original.dotColor(2), color);
        }
        expect(
          tester.getSize(find.byKey(const ValueKey('interlude_dots'))),
          size,
        );
        expect(builds, startingBuilds);
        expect(layouts.count, startingLayouts);
        opacity = alpha;
        scale = original.scale;
        dy = original.dy;
        spacing = original.spacing;
      }
      expect(original.scale, closeTo(.15, 1e-9));
      expect(original.dy, -8);
      // Flutter marks interpolation complete on time > duration, while its
      // visible value is already exactly the endpoint at time == duration.
      await tester.pump(const Duration(microseconds: 1));
      expect(original.progress, 0);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'seek interrupts exit and returning dots cannot be hidden by stale completion',
    (tester) async {
      var current = true;
      late StateSetter update;
      final seek = ValueNotifier<Duration?>(null);
      final intent = ValueNotifier(0);
      addTearDown(seek.dispose);
      addTearDown(intent.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return InterludeAnimationWidget(
                  isCurrent: current,
                  baseColor: Colors.grey,
                  highlightColor: Colors.white,
                  startTime: Duration.zero,
                  interludeDuration: const Duration(seconds: 8),
                  currentTime: const Duration(seconds: 7),
                  isPlaying: false,
                  seekIntentListenable: intent,
                  seekPositionListenable: seek,
                );
              },
            ),
          ),
        ),
      );
      double opacity() => tester
          .widgetList<FadeTransition>(find.byType(FadeTransition))
          .fold<double>(1, (v, a) => v * a.opacity.value);
      await tester.pump(const Duration(milliseconds: 400));
      update(() => current = false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(opacity(), inExclusiveRange(0, 1));
      intent.value++;
      await tester.pump();
      expect(opacity(), 0);
      seek.value = const Duration(seconds: 2);
      update(() => current = true);
      await tester.pump();
      expect(opacity(), 1);
      await tester.pump(const Duration(milliseconds: 400));
      expect(opacity(), 1);
      for (final target in [20, 3, 19, 4]) {
        intent.value++;
        seek.value = Duration(seconds: target);
        update(() => current = target < 8);
        await tester.pump();
        expect(opacity(), target < 8 ? 1 : 0);
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pause buffering and rate changes preserve local dot progress', (
    tester,
  ) async {
    final position = ValueNotifier(const Duration(seconds: 2));
    final rate = ValueNotifier(1.0);
    final output = ValueNotifier(true);
    addTearDown(position.dispose);
    addTearDown(rate.dispose);
    addTearDown(output.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: InterludeAnimationWidget(
            isCurrent: true,
            baseColor: Colors.grey,
            highlightColor: Colors.white,
            startTime: Duration.zero,
            interludeDuration: const Duration(seconds: 8),
            currentTime: Duration.zero,
            isPlaying: true,
            positionListenable: position,
            playbackRateListenable: rate,
            actualPlaybackListenable: output,
          ),
        ),
      ),
    );
    InterludeDotsPainter painter() =>
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey('interlude_dots')),
                )
                .painter!
            as InterludeDotsPainter;
    await tester.pump(const Duration(milliseconds: 400));
    final beforePause = painter().progress;
    output.value = false;
    await tester.pump(const Duration(milliseconds: 500));
    expect(painter().progress, beforePause);
    position.value = const Duration(
      milliseconds: 2350,
    ); // stale final decoder sample
    await tester.pump();
    expect(painter().progress, beforePause);
    output.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    final beforeRate = painter().progress;
    expect(beforeRate, closeTo(beforePause + .160 / 8, 1e-5));
    rate.value = 2;
    expect(painter().progress, beforeRate);
    await tester.pump(const Duration(milliseconds: 100));
    expect(painter().progress, closeTo(beforeRate + .2 / 8, 1e-5));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  testWidgets('normal interlude exit completes independently in 240ms', (
    tester,
  ) async {
    var current = true;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return InterludeAnimationWidget(
              isCurrent: current,
              baseColor: Colors.grey,
              highlightColor: Colors.white,
              startTime: Duration.zero,
              interludeDuration: const Duration(seconds: 8),
              currentTime: const Duration(seconds: 7),
              isPlaying: false,
            );
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    final initialSize = tester.getSize(find.byType(InterludeAnimationWidget));
    update(() => current = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    final fades = tester.widgetList<FadeTransition>(
      find.byType(FadeTransition),
    );
    final opacity = fades.fold<double>(
      1,
      (value, fade) => value * fade.opacity.value,
    );
    expect(opacity, closeTo(0, 1e-9));
    expect(tester.getSize(find.byType(InterludeAnimationWidget)), initialSize);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'interlude state survives playback-source removal at normal line change',
    (tester) async {
      final position = ValueNotifier(const Duration(milliseconds: 7000));
      addTearDown(position.dispose);
      var active = 0;
      late StateSetter update;
      final lines = [
        LyricLine(
          timestamp: Duration.zero,
          texts: const [],
          isInterlude: true,
          interludeDuration: const Duration(seconds: 8),
        ),
        LyricLine(timestamp: const Duration(seconds: 8), texts: const ['正文']),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return MobileLyricsList(
                  lines: lines,
                  active: active,
                  positionListenable: position,
                  isPlaying: true,
                );
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      final state = tester.state(find.byType(InterludeAnimationWidget));
      update(() => active = 1);
      await tester.pump();
      expect(tester.state(find.byType(InterludeAnimationWidget)), same(state));
      final fades = tester.widgetList<FadeTransition>(
        find.descendant(
          of: find.byType(InterludeAnimationWidget),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(
        fades.fold<double>(1, (v, f) => v * f.opacity.value),
        closeTo(1, .001),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.state(find.byType(InterludeAnimationWidget)), same(state));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'fast second boundary preserves exit styling and inferred seek cancels it',
    (tester) async {
      final position = ValueNotifier(const Duration(milliseconds: 7000));
      addTearDown(position.dispose);
      var active = 0;
      late StateSetter update;
      final lines = [
        LyricLine(
          timestamp: Duration.zero,
          texts: const [],
          isInterlude: true,
          interludeDuration: const Duration(seconds: 8),
        ),
        LyricLine(timestamp: const Duration(seconds: 8), texts: const ['起唱']),
        LyricLine(
          timestamp: const Duration(milliseconds: 8080),
          texts: const ['快句'],
        ),
        LyricLine(
          timestamp: const Duration(seconds: 20),
          texts: const ['跳转目标'],
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return MobileLyricsList(
                  lines: lines,
                  active: active,
                  positionListenable: position,
                  isPlaying: true,
                );
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      update(() => active = 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      update(() => active = 2);
      await tester.pump();
      final row = find.byKey(const ValueKey('mobile_lyric_0'));
      final opacity = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: row,
          matching: find.byKey(const ValueKey('mobile_lyric_distance_opacity')),
        ),
      );
      expect(opacity.opacity, 1);
      final exit = tester.widget<FadeTransition>(
        find.byKey(const ValueKey('interlude_exit_visibility')),
      );
      expect(exit.opacity.value, inExclusiveRange(0, 1));
      position.value = const Duration(seconds: 20);
      update(() => active = 3);
      await tester.pump();
      final dots = find.byType(InterludeAnimationWidget);
      if (dots.evaluate().isNotEmpty) {
        final fades = tester.widgetList<FadeTransition>(
          find.descendant(of: dots, matching: find.byType(FadeTransition)),
        );
        expect(fades.fold<double>(1, (v, a) => v * a.opacity.value), 0);
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}

class _LayoutCounts {
  int count = 0;
}

class _LayoutProbe extends SingleChildRenderObjectWidget {
  const _LayoutProbe({required this.counts, required super.child});
  final _LayoutCounts counts;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _LayoutProbeRender(counts);
}

class _LayoutProbeRender extends RenderProxyBox {
  _LayoutProbeRender(this.counts);
  final _LayoutCounts counts;
  @override
  void performLayout() {
    counts.count++;
    super.performLayout();
  }
}
