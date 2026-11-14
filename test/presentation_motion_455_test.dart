import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/home_tab_viewport.dart';
import 'package:myune_music/widgets/now_playing_immersive_layout.dart';
import 'package:myune_music/widgets/now_playing_route.dart';
import 'package:myune_music/widgets/optional_shader_mask.dart';
import 'package:myune_music/widgets/playback_bottom_sheet.dart';
import 'package:myune_music/widgets/playback_control_sheet_surface.dart';
import 'package:myune_music/widgets/playlist_entrance_motion.dart';

void main() {
  for (final horizontal in [true, false]) {
    testWidgets(
      'visible playlists stagger from current scroll offset (horizontal=$horizontal)',
      (tester) async {
        final navigation = HomeTabController();
        final scroll = ScrollController(initialScrollOffset: 600);
        var builds = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 350,
                height: 350,
                child: PlaylistEntranceMotion(
                  navigation: navigation,
                  child: ListView.builder(
                    controller: scroll,
                    scrollDirection: horizontal
                        ? Axis.horizontal
                        : Axis.vertical,
                    itemExtent: 120,
                    itemCount: 40,
                    itemBuilder: (_, i) {
                      builds++;
                      return PlaylistEntranceItem(
                        index: i,
                        child: Text('Playlist $i'),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        Transform pose(int i) => tester.widget<Transform>(
          find.byKey(ValueKey('playlist-entrance-$i'), skipOffstage: false),
        );
        navigation.jumpToPage(1);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final first = pose(5).transform;
        final next = pose(6).transform;
        expect(first.storage[0], greaterThan(next.storage[0]));
        expect(first.storage[1], lessThan(0), reason: 'small left rotation');
        expect(first.getMaxScaleOnAxis(), inExclusiveRange(.78, 1.03));
        final built = builds;
        await tester.pump(const Duration(milliseconds: 120));
        expect(
          builds,
          built,
          reason: 'no list/item rebuild on animation frames',
        );
        // Cached items outside the viewport were never put into the sequence.
        expect(pose(8).transform.getMaxScaleOnAxis(), 1);
        await tester.pumpAndSettle();
        expect(pose(5).transform.isIdentity(), isTrue);
        expect(scroll.offset, 600);
        navigation.jumpToPage(0);
        navigation.jumpToPage(1);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(pose(5).transform.isIdentity(), isFalse);
        navigation.jumpToPage(2);
        await tester.pump();
        expect(pose(5).transform.isIdentity(), isTrue);
        await tester.pumpWidget(const SizedBox());
        navigation.dispose();
        scroll.dispose();
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }

  testWidgets(
    'playlist entrance stays still with reduced motion and resumes only on new navigation',
    (tester) async {
      final navigation = HomeTabController();
      var hidden = false, reduced = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return MediaQuery(
                data: MediaQueryData(disableAnimations: reduced),
                child: TickerMode(
                  enabled: !hidden,
                  child: PlaylistEntranceMotion(
                    navigation: navigation,
                    child: ListView(
                      children: const [
                        PlaylistEntranceItem(
                          index: 0,
                          child: SizedBox(height: 80, child: Text('card')),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      Transform pose() => tester.widget<Transform>(
        find.byKey(const ValueKey('playlist-entrance-0')),
      );
      navigation.jumpToPage(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(pose().transform.isIdentity(), isFalse);
      update(() => hidden = true);
      await tester.pump();
      expect(pose().transform.isIdentity(), isTrue);
      update(() {
        hidden = false;
        reduced = true;
      });
      navigation.jumpToPage(0);
      navigation.jumpToPage(1);
      await tester.pumpAndSettle();
      expect(pose().transform.isIdentity(), isTrue);
      await tester.pumpWidget(const SizedBox());
      navigation.dispose();
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'edge dissolve reverses continuously and removes the mask at rest',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Text('home')),
        ),
      );
      nav.currentState!.push(
        NowPlayingRoute(builder: (_) => const Scaffold(body: Text('player'))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 210));
      final key = find.byKey(const ValueKey('player-left-edge-dissolve'));
      expect(
        tester
            .renderObject<RenderOptionalShaderMask>(key)
            .alwaysNeedsCompositing,
        isTrue,
      );
      final element = tester.element(find.text('player'));
      await tester.pumpAndSettle();
      expect(
        tester
            .renderObject<RenderOptionalShaderMask>(key)
            .alwaysNeedsCompositing,
        isFalse,
      );
      expect(tester.renderObject<RenderOptionalShaderMask>(key).layer, isNull);
      expect(tester.element(find.text('player')), same(element));
      nav.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester
            .renderObject<RenderOptionalShaderMask>(key)
            .alwaysNeedsCompositing,
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sheet foreground and glass use separate timing with continuous reversal',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showPlaybackBottomSheet<void>(
                  context: context,
                  backgroundColor: Colors.transparent,
                  sheetAnimationStyle: const AnimationStyle(
                    duration: Duration(milliseconds: 300),
                    reverseDuration: Duration(milliseconds: 300),
                  ),
                  surfaceBuilder: (_, child) =>
                      PlaybackControlSheetSurface(fluid: true, child: child),
                  builder: (_) => const SizedBox(
                    height: 300,
                    child: Center(child: Text('content')),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      FadeTransition fade(String key) =>
          tester.widget<FadeTransition>(find.byKey(ValueKey(key)));
      expect(
        fade('playback-sheet-foreground-fade').opacity.value,
        greaterThan(.5),
      );
      expect(
        fade('playback-sheet-background-fade').opacity.value,
        lessThan(.4),
      );
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('playback-feature-backdrop-filter')),
          matching: find.byKey(
            const ValueKey('playback-sheet-foreground-fade'),
          ),
        ),
        findsNothing,
      );
      await tester.pumpAndSettle();
      nav.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        fade('playback-sheet-background-fade').opacity.value,
        inExclusiveRange(0, 1),
      );
      expect(
        fade('playback-sheet-foreground-fade').opacity.value,
        inExclusiveRange(0, 1),
      );
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  for (final reduced in [false, true]) {
    testWidgets(
      'individual immersive controls retain state when reversing (reduced=$reduced)',
      (tester) async {
        var immersive = false;
        late StateSetter update;
        final visualKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: StatefulBuilder(
                builder: (_, setState) {
                  update = setState;
                  return NowPlayingImmersiveLayout(
                    immersive: immersive,
                    header: const NowPlayingChromeFade(
                      order: 0,
                      child: Text('header'),
                    ),
                    visual: SizedBox.expand(key: visualKey),
                    controls: const SizedBox(
                      height: 180,
                      child: Row(
                        children: [
                          NowPlayingChromeFade(
                            order: 2,
                            child: Text('timeline'),
                          ),
                          NowPlayingChromeFade(
                            order: 8,
                            child: Text('buttons'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        final element = visualKey.currentContext;
        double opacity(int i) => tester
            .widget<FadeTransition>(
              find.byKey(ValueKey('immersive-control-fade-$i')),
            )
            .opacity
            .value;
        update(() => immersive = true);
        await tester.pump();
        if (reduced) {
          expect(opacity(2), 0);
          expect(opacity(8), 0);
        } else {
          await tester.pump(const Duration(milliseconds: 140));
          expect(opacity(2), inExclusiveRange(0, 1));
          expect(opacity(8), lessThan(opacity(2)));
          final before = opacity(2);
          update(() => immersive = false);
          await tester.pump();
          expect(opacity(2), closeTo(before, .00001));
        }
        await tester.pumpAndSettle();
        expect(visualKey.currentContext, same(element));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }
}
