import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/interaction_motion.dart';
import 'package:myune_music/widgets/navigation_motion_icon.dart';
import 'package:myune_music/widgets/transport_skip_button.dart';

const _kinds = [
  IconMotion.library,
  IconMotion.playlist,
  IconMotion.artist,
  IconMotion.album,
  IconMotion.settings,
];
const _labels = ['音乐库', '歌单', '歌手', '专辑', '设置'];

class _CountBuild extends StatelessWidget {
  const _CountBuild(this.onBuild);
  final VoidCallback onBuild;
  @override
  Widget build(BuildContext context) {
    onBuild();
    return const Icon(Icons.favorite);
  }
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
      'misans',
    )..addFont(rootBundle.load('assets/fonts/MiSansVF.ttf'))).load();
  });

  test(
    'all motion profiles stay bounded at 60/90/120 Hz and settle exactly',
    () {
      for (final kind in IconMotion.values) {
        for (final hz in [60, 90, 120]) {
          final seconds = iconMotionDuration(kind).inMicroseconds / 1e6;
          for (var i = 0; i <= (seconds * hz).ceil(); i++) {
            final pose = iconMotionPose(kind, i / (seconds * hz));
            expect(pose.x.abs(), lessThanOrEqualTo(4));
            expect(pose.y.abs(), lessThanOrEqualTo(2.5));
            expect(pose.scaleX, inInclusiveRange(.9, 1.181));
            expect(pose.scaleY, inInclusiveRange(.9, 1.181));
            expect(pose.angle.isFinite, isTrue);
          }
          expect(iconMotionPose(kind, 0), iconMotionPose(kind, 1));
        }
      }
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'navigation keeps native selection through rapid taps: $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(390, 280);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var selected = 0, reduced = false, visible = true;
        late StateSetter update;
        final capture = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness, fontFamily: 'misans'),
            home: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: reduced),
                  child: TickerMode(
                    enabled: visible,
                    child: RepaintBoundary(
                      key: capture,
                      child: Scaffold(
                        body: Center(
                          child: Text('交互动效预览 · ${_labels[selected]}'),
                        ),
                        bottomNavigationBar: NavigationBar(
                          selectedIndex: selected,
                          onDestinationSelected: (index) =>
                              setState(() => selected = index),
                          destinations: [
                            for (var i = 0; i < 5; i++)
                              NavigationDestination(
                                icon: NavigationMotionIcon(
                                  kind: _kinds[i],
                                  selected: selected == i,
                                ),
                                label: _labels[i],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final kind in _kinds) {
          expect(
            tester
                .widget<Transform>(
                  find.byKey(ValueKey('icon-motion-${kind.name}')),
                )
                .transform
                .isIdentity(),
            isTrue,
          );
        }
        await tester.tap(find.text('歌单'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        expect(
          tester
              .widget<Transform>(
                find.byKey(const ValueKey('icon-motion-playlist')),
              )
              .transform
              .isIdentity(),
          isFalse,
        );
        for (var i = 2; i < 12; i++) {
          await tester.tap(find.text(_labels[i % 5]));
          await tester.pump(const Duration(milliseconds: 25));
        }
        expect(selected, 1);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          selected,
        );
        expect(tester.binding.transientCallbackCount, 0);
        update(() {
          selected = 3;
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        update(() {
          reduced = true;
        });
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Transform>(
                find.byKey(const ValueKey('icon-motion-album')),
              )
              .transform
              .isIdentity(),
          isTrue,
        );
        update(() {
          reduced = false;
          selected = 4;
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        update(() {
          visible = false;
        });
        await tester.pump();
        expect(tester.binding.transientCallbackCount, 0);
        update(() {
          visible = true;
        });
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);

        final dir = Platform.environment['MOTION443_PREVIEW_DIR'];
        if (dir != null) {
          for (var i = 0; i < 5; i++) {
            update(() => selected = i);
            await tester.pump();
            for (var frame = 0; frame < 5; frame++) {
              await tester.pump(const Duration(milliseconds: 100));
              await tester.runAsync(() async {
                final image =
                    await (capture.currentContext!.findRenderObject()
                            as RenderRepaintBoundary)
                        .toImage(pixelRatio: 2);
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  '$dir/${brightness.name}-$i-$frame.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            await tester.pumpAndSettle();
          }
        }
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'state motion never rebuilds its static child and cancels in background',
    (tester) async {
      var trigger = 0, builds = 0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return ActionMotionIcon(
                trigger: trigger,
                kind: IconMotion.heart,
                child: _CountBuild(() => builds++),
              );
            },
          ),
        ),
      );
      update(() => trigger++);
      await tester.pump();
      final baseline = builds;
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(builds, baseline);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(
        tester
            .widget<Transform>(find.byKey(const ValueKey('icon-motion-heart')))
            .transform
            .isIdentity(),
        isTrue,
      );
      expect(tester.binding.transientCallbackCount, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'hold-to-skip has no ongoing visual ticker and keeps 600ms timing',
    (tester) async {
      var skips = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransportSkipButton(
              tooltip: '下一首',
              icon: Icons.skip_next,
              onSkip: () async {
                skips++;
              },
            ),
          ),
        ),
      );
      final pointer = await tester.startGesture(
        tester.getCenter(find.byType(IconButton)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(skips, 1);
      await tester.pump(const Duration(milliseconds: 1800));
      await tester.pump();
      expect(skips, 4);
      expect(tester.binding.transientCallbackCount, 0);
      expect(
        tester
            .widget<Transform>(find.byKey(const ValueKey('icon-motion-next')))
            .transform
            .isIdentity(),
        isTrue,
      );
      await pointer.up();
      await tester.pumpAndSettle();
      expect(skips, 4);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'cancelled press settles without triggering the underlying button',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ButtonPressMotion(
              child: IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => taps++,
              ),
            ),
          ),
        ),
      );
      final pointer = await tester.startGesture(
        tester.getCenter(find.byType(IconButton)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await pointer.cancel();
      await tester.pumpAndSettle();
      expect(taps, 0);
      expect(
        tester
            .widget<Transform>(
              find.byKey(const ValueKey('button-press-transform')),
            )
            .transform
            .storage[0],
        closeTo(1, .001),
      );
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
