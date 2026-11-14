import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/home_tab_viewport.dart';
import 'package:myune_music/widgets/playlist_entrance_motion.dart';
import 'package:myune_music/widgets/now_playing_route.dart';

void main() {
  testWidgets(
    'playlist finishes at 272ms with cached items idle and cached items do not tick',
    (tester) async {
      final nav = HomeTabController();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              height: 200,
              child: PlaylistEntranceMotion(
                navigation: nav,
                child: ListView(
                  scrollCacheExtent: const ScrollCacheExtent.pixels(1000),
                  children: [
                    for (var i = 0; i < 10; i++)
                      PlaylistEntranceItem(
                        index: i,
                        child: SizedBox(height: 100, child: Text('list $i')),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      nav.jumpToPage(1);
      await tester.pump();
      await tester.pump();
      Transform transform(int i) => tester.widget<Transform>(
        find.byKey(ValueKey('playlist-entrance-$i'), skipOffstage: false),
      );
      expect(transform(0).transform.storage[0], .4);
      final cached = transform(4);
      final visible = transform(0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(transform(0), isNot(same(visible)));
      expect(
        transform(4),
        same(cached),
        reason: 'offscreen cached items must not rebuild on each frame',
      );
      await tester.pump(const Duration(microseconds: 172000));
      expect(transform(0).transform.storage[0], 1);
      expect(transform(1).transform.storage[0], 1);
      // Flutter completes its ticker on the first sample after the endpoint.
      await tester.pump(const Duration(microseconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
      nav.dispose();
    },
  );

  testWidgets(
    'player feather reuses identical paint inputs and invalidates geometry and direction',
    (tester) async {
      final clock = AnimationController(vsync: const TestVSync(), value: .3);
      var right = false;
      await tester.pumpWidget(
        MaterialApp(
          home: PageEdgeDissolve(
            progress: clock,
            edgeResolver: () => right,
            child: const ColoredBox(color: Colors.red),
          ),
        ),
      );
      final render = tester.renderObject<RenderPageEdgeDissolve>(
        find.byType(PageEdgeDissolve),
      );
      const bounds = Rect.fromLTWH(0, 0, 400, 600);
      final first = render.shaderCallback(bounds);
      expect(render.shaderCallback(bounds), same(first));
      clock.value = .4;
      final next = render.shaderCallback(bounds);
      expect(next, isNot(same(first)));
      expect(render.shaderCallback(bounds), same(next));
      right = true;
      final flipped = render.shaderCallback(bounds);
      expect(flipped, isNot(same(next)));
      expect(
        render.shaderCallback(bounds.shift(const Offset(10, 0))),
        isNot(same(flipped)),
      );
      clock.value = 1;
      await tester.pump();
      expect(render.alwaysNeedsCompositing, isFalse);
      expect(render.layer, isNull);
      await tester.pumpWidget(const SizedBox());
      clock.dispose();
    },
  );
}
