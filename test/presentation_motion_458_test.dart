import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/mobile/mobile_shell.dart';
import 'package:myune_music/widgets/playlist_entrance_motion.dart';
import 'package:myune_music/widgets/now_playing_immersive_layout.dart';
import 'package:myune_music/widgets/playback_orientation.dart';

void main() {
  testWidgets(
    'rotating and immersive transitions retain the single visual state',
    (tester) async {
      late StateSetter update;
      var split = false, immersive = false;
      final marker = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return NowPlayingImmersiveLayout(
                  immersive: immersive,
                  split: split,
                  header: const Text('header'),
                  visual: TextField(key: marker),
                  controls: const SizedBox(height: 80),
                );
              },
            ),
          ),
        ),
      );
      final state = marker.currentState;
      update(() => split = true);
      await tester.pumpAndSettle();
      expect(marker.currentState, same(state));
      update(() => immersive = true);
      await tester.pump(const Duration(milliseconds: 100));
      update(() => split = false);
      await tester.pumpAndSettle();
      expect(marker.currentState, same(state));
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final grid in [false, true]) {
    testWidgets(
      'all visible rows including partial bottom animate; cached rows settle ($grid)',
      (tester) async {
        tester.view.physicalSize = const Size(400, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final clock = AnimationController(
          vsync: const TestVSync(),
          duration: const Duration(milliseconds: 620),
        );
        addTearDown(clock.dispose);
        Widget item(int i) => buildLibrarySongEntranceTransition(
          animation: clock,
          order: i,
          style: grid
              ? LibraryEntranceStyle.indexed
              : LibraryEntranceStyle.list,
          child: SizedBox(height: 60, child: Text('song $i')),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 360,
                height: 700,
                child: LibraryEntranceMotion(
                  animation: clock,
                  child: grid
                      ? GridView.builder(
                          scrollCacheExtent: const ScrollCacheExtent.pixels(
                            800,
                          ),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisExtent: 100,
                              ),
                          itemCount: 40,
                          itemBuilder: (_, i) => item(i),
                        )
                      : ListView.builder(
                          scrollCacheExtent: const ScrollCacheExtent.pixels(
                            800,
                          ),
                          itemExtent: 60,
                          itemCount: 40,
                          itemBuilder: (_, i) => item(i),
                        ),
                ),
              ),
            ),
          ),
        );
        FadeTransition pose(int i) => tester.widget<FadeTransition>(
          find.byKey(ValueKey('library-entrance-$i'), skipOffstage: false),
        );
        final last = grid ? 13 : 11;
        final retained = tester.element(
          find.text('song 20', skipOffstage: false),
        );
        clock.forward();
        await tester.pump();
        await tester.pump();
        expect(pose(last).opacity.value, 0);
        expect(pose(20).opacity.value, 1);
        await tester.pump(const Duration(milliseconds: 310));
        await tester.pump();
        expect(pose(last).opacity.value, inExclusiveRange(0, 1));
        expect(
          tester.element(find.text('song 20', skipOffstage: false)),
          same(retained),
        );
        clock.value = 1;
        await tester.pump(const Duration(milliseconds: 700));
        expect(pose(last).opacity.value, 1);
        await tester.pumpWidget(const SizedBox());
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }
  testWidgets(
    'playback requests rotation, manual landscape and restores portrait after final route',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: PlaybackOrientationScope(
            child: PlaybackOrientationScope(child: PlaybackOrientationButton()),
          ),
        ),
      );
      var requests = calls
          .where((c) => c.method == 'SystemChrome.setPreferredOrientations')
          .toList();
      expect(
        requests.last.arguments,
        contains('DeviceOrientation.landscapeLeft'),
      );
      await tester.tap(find.byTooltip('横屏播放'));
      await tester.pump();
      requests = calls
          .where((c) => c.method == 'SystemChrome.setPreferredOrientations')
          .toList();
      expect(
        requests.last.arguments,
        equals([
          'DeviceOrientation.landscapeLeft',
          'DeviceOrientation.landscapeRight',
        ]),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      requests = calls
          .where((c) => c.method == 'SystemChrome.setPreferredOrientations')
          .toList();
      expect(requests.last.arguments, equals(['DeviceOrientation.portraitUp']));
    },
  );
  testWidgets('lower visible library rows participate in startup', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: buildLibrarySongEntranceTransition(
          animation: const AlwaysStoppedAnimation(0),
          order: 12,
          child: const Text('bottom song'),
        ),
      ),
    );
    final fades = tester.widgetList<FadeTransition>(
      find.ancestor(
        of: find.text('bottom song'),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fades.any((f) => f.opacity.value == 0), isTrue);
  });
  test('playlist growth starts fast and decelerates toward rest', () {
    expect(playlistGrowthProgress(.1), greaterThan(.3));
    expect(
      playlistGrowthProgress(.2) - playlistGrowthProgress(.1),
      greaterThan(playlistGrowthProgress(.9) - playlistGrowthProgress(.8)),
    );
  });
  testWidgets('landscape controls scroll within a short viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(740, 340);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NowPlayingImmersiveLayout(
            immersive: false,
            split: true,
            header: Text('header'),
            visual: ColoredBox(color: Colors.blue),
            controls: Column(
              children: [SizedBox(height: 430), Text('last control')],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('last control')).bottom,
      lessThanOrEqualTo(340),
    );
  });
}
