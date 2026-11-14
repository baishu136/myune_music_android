import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/home_tab_viewport.dart';
import 'package:myune_music/widgets/playlist_entrance_motion.dart';
import 'package:myune_music/widgets/playback_bottom_sheet.dart';
import 'package:myune_music/widgets/interaction_motion.dart';
import 'package:myune_music/widgets/now_playing_route.dart';
import 'package:myune_music/widgets/transport_skip_button.dart';

class _ObservedClock extends AnimationController {
  _ObservedClock()
    : super(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 620),
      );
  int observers = 0;
  @override
  void addListener(VoidCallback listener) {
    observers++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    observers--;
    super.removeListener(listener);
  }
}

void main() {
  test(
    'feather and growth curves stay continuous at 60/90/120Hz and settle softly',
    () {
      for (final hz in [60, 90, 120]) {
        var previous = 0.0;
        for (var i = 0; i <= hz; i++) {
          final p = Curves.easeInOutCubic.transform(i / hz);
          final value = pageEdgeOpacity(p, 0);
          expect(value, inInclusiveRange(0, 1));
          expect(value, greaterThanOrEqualTo(previous - 1e-12));
          expect(value - previous, lessThan(.12));
          previous = value;
          expect(playlistGrowthProgress(i / hz), inInclusiveRange(0, 1));
        }
        expect(previous, 1);
      }
      expect(pageEdgeOpacity(0, 1), 1);
      expect(pageEdgeOpacity(1, 0), 1);
      expect(
        pageEdgeOpacity(.999, 0) - pageEdgeOpacity(.998, 0),
        lessThan(.000001),
      );
    },
  );

  testWidgets(
    'feather ticks paint without rebuilding the mask or its child and detaches listeners',
    (tester) async {
      final clock = _ObservedClock();
      var maskBuilds = 0, childBuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (_) {
              maskBuilds++;
              return PageEdgeDissolve(
                progress: clock,
                child: Builder(
                  builder: (_) {
                    childBuilds++;
                    return const ColoredBox(color: Colors.red);
                  },
                ),
              );
            },
          ),
        ),
      );
      final render = tester.renderObject<RenderPageEdgeDissolve>(
        find.byType(PageEdgeDissolve),
      );
      for (var i = 0; i <= 120; i++) {
        clock.value = i / 120;
        await tester.pump();
      }
      expect(maskBuilds, 1);
      expect(childBuilds, 1);
      expect(render.layer, isNull);
      await tester.pumpWidget(const SizedBox());
      expect(clock.observers, 0);
      clock.dispose();
    },
  );

  testWidgets(
    'rapid skip taps keep the compression continuous and preserve callbacks',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: TransportSkipButton(
              tooltip: '下一首',
              icon: Icons.skip_next,
              onSkip: () async {
                calls++;
              },
            ),
          ),
        ),
      );
      double scale() => tester
          .widget<Transform>(find.byKey(const ValueKey('icon-motion-next')))
          .transform
          .storage[0];
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final before = scale();
      expect(before, inInclusiveRange(.6, .68));
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(scale(), closeTo(before, .00001));
      expect(calls, 2);
      await tester.pumpAndSettle();
      expect(scale(), 1);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'skip pulse contracts fast-to-slow and returns slow-to-fast without exceeding rest',
    () {
      double scale(double t) => iconMotionPose(IconMotion.next, t).scaleX;
      expect(scale(.10) - scale(0), lessThan(scale(.30) - scale(.20)));
      expect(scale(.95) - scale(.85), greaterThan(scale(.50) - scale(.40)));
      for (var i = 0; i <= 1000; i++) {
        expect(scale(i / 1000), inInclusiveRange(.6, 1));
      }
    },
  );
  test(
    'skip buttons compress forty percent and pull toward the play button',
    () {
      final previous = iconMotionPose(IconMotion.previous, .34);
      final next = iconMotionPose(IconMotion.next, .34);
      expect(next.scaleX, closeTo(.6, 1e-9));
      expect(next.scaleY, closeTo(.6, 1e-9));
      expect(previous.x, 4);
      expect(next.x, -4);
      expect(
        iconMotionPose(IconMotion.next, 0),
        iconMotionPose(IconMotion.next, 1),
      );
    },
  );
  testWidgets(
    'playlist starts at forty percent and grows along a speed curve',
    (tester) async {
      final nav = HomeTabController();
      await tester.pumpWidget(
        MaterialApp(
          home: PlaylistEntranceMotion(
            navigation: nav,
            child: ListView(
              children: const [
                PlaylistEntranceItem(
                  index: 0,
                  child: SizedBox(height: 100, child: Text('playlist')),
                ),
              ],
            ),
          ),
        ),
      );
      nav.jumpToPage(1);
      await tester.pump();
      await tester.pump();
      double scale() {
        final m = tester
            .widget<Transform>(
              find.byKey(const ValueKey('playlist-entrance-0')),
            )
            .transform;
        return math.sqrt(
          m.storage[0] * m.storage[0] + m.storage[1] * m.storage[1],
        );
      }

      expect(scale(), closeTo(.4, .00001));
      await tester.pump(const Duration(milliseconds: 170));
      final first = scale();
      await tester.pump(const Duration(milliseconds: 170));
      expect(
        scale() - first,
        isNot(closeTo(first - .4, .01)),
        reason: 'a shaped speed curve, not constant-speed growth',
      );
      await tester.pumpAndSettle();
      expect(scale(), 1);
      await tester.pumpWidget(const SizedBox());
      nav.dispose();
    },
  );

  testWidgets(
    'bottom sheet no longer alternates foreground and whole-panel fades',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showPlaybackBottomSheet<void>(
                  context: context,
                  backgroundColor: Colors.blue,
                  sheetAnimationStyle: const AnimationStyle(
                    duration: Duration(milliseconds: 300),
                  ),
                  builder: (_) =>
                      const SizedBox(height: 240, child: Text('menu text')),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(
        find.byKey(const ValueKey('playback-sheet-content-fade')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('playback-bottom-sheet-fade')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('playback-sheet-background-fade')),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
    },
  );
}
