import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/interaction_motion.dart';
import 'package:myune_music/widgets/play_pause_button.dart';
import 'package:myune_music/widgets/navigation_motion_icon.dart';

void main() {
  testWidgets('rapid navigation retaps continue the accent without snapping', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: MyuneNavigationBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('音乐库'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final motion = find.byKey(const ValueKey('icon-motion-library'));
    final before = List<double>.of(
      tester.widget<Transform>(motion).transform.storage,
    );
    await tester.tap(find.text('音乐库'));
    await tester.pump();
    expect(tester.widget<Transform>(motion).transform.storage, before);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.tap(find.text('音乐库'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.widget<Transform>(motion).transform.isIdentity(), isFalse);
    await tester.pumpAndSettle();
  });

  test('accent has a smooth bounded settle without a hard stop', () {
    const epsilon = .000001;
    for (final delay in [0.0, .09, .16]) {
      double f(double t) => iconMotionAccent(t, delay: delay);
      for (var i = 0; i <= 1200; i++) {
        expect(f(i / 1200), inInclusiveRange(-.120001, 1.000001));
      }
      expect(f(0), 0);
      expect(f(1), 0);
      for (final t in [
        delay,
        delay + .28 * (1 - delay),
        delay + .64 * (1 - delay),
        1.0,
      ]) {
        final before = (f(t) - f(t - epsilon)) / epsilon;
        final after = (f(t + epsilon) - f(t)) / epsilon;
        expect((before - after).abs(), lessThan(.001));
      }
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'glyph detail frames settle identically and respect theme opacity: $brightness',
      (tester) async {
        const kinds = [
          IconMotion.library,
          IconMotion.playlist,
          IconMotion.artist,
          IconMotion.album,
          IconMotion.settings,
        ];
        final capture = GlobalKey();
        var phase = 0.0;
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Center(
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return RepaintBoundary(
                    key: capture,
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.surface,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final selected in [false, true])
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final kind in kinds)
                                  SizedBox(
                                    width: 72,
                                    height: 64,
                                    child: Center(
                                      child: IconTheme(
                                        data: IconThemeData(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                          size: 32,
                                          opacity: selected ? 1 : .65,
                                        ),
                                        child: NavigationGlyph(
                                          kind: kind,
                                          phase: phase,
                                          selected: selected,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
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
        final samples = <List<int>>[];
        const phases = [
          0.0,
          .07,
          .14,
          .21,
          .28,
          .36,
          .44,
          .54,
          .64,
          .74,
          .86,
          .94,
          1.0,
        ];
        for (var i = 0; i < phases.length; i++) {
          update(() => phase = phases[i]);
          await tester.pump();
          await tester.runAsync(() async {
            final image =
                await (capture.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final rgba = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            samples.add(List<int>.of(rgba));
            final dir = Platform.environment['MOTION445_PREVIEW_DIR'];
            if (dir != null) {
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '$dir/${brightness.name}-${i.toString().padLeft(2, '0')}.png',
              ).writeAsBytes(png!.buffer.asUint8List());
            }
            image.dispose();
          });
        }
        expect(samples.first, samples.last);
        expect(samples[4], isNot(samples.first));
        // Every glyph has 16px logical breathing room inside its cell. Motion
        // never leaks into that outer margin, including the settings teeth.
        const width = 720;
        final reference = samples.first;
        for (final pixels in samples) {
          for (var y = 0; y < 256; y++) {
            for (var x = 0; x < width; x++) {
              if (x % 144 < 22 ||
                  x % 144 >= 122 ||
                  y % 128 < 22 ||
                  y % 128 >= 106) {
                final offset = (y * width + x) * 4;
                expect(
                  pixels.sublist(offset, offset + 4),
                  reference.sublist(offset, offset + 4),
                );
              }
            }
          }
        }
        expect(tester.binding.transientCallbackCount, 0);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test('record motion leaves the outer silhouette upright', () {
    for (final phase in [.1, .25, .5, .75, .9]) {
      expect(iconMotionPose(IconMotion.album, phase).angle, 0);
    }
  });

  testWidgets('play morph uses a restrained turn and reverses continuously', (
    tester,
  ) async {
    var playing = false;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return PlayPauseButton(
              isPlaying: playing,
              onPressed: () {},
              color: Colors.black,
            );
          },
        ),
      ),
    );
    update(() => playing = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final turn = tester
        .widget<Transform>(find.byKey(const ValueKey('play_pause_rotation')))
        .transform;
    final angle = math.atan2(turn.storage[1], turn.storage[0]);
    expect(angle.abs(), lessThanOrEqualTo(math.pi / 12));
    final progress = tester
        .widget<AnimatedIcon>(find.byType(AnimatedIcon))
        .progress
        .value;
    update(() => playing = false);
    await tester.pump();
    expect(
      tester.widget<AnimatedIcon>(find.byType(AnimatedIcon)).progress.value,
      closeTo(progress, .000001),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedIcon>(find.byType(AnimatedIcon)).progress.value,
      0,
    );
    expect(tester.binding.transientCallbackCount, 0);
  });
}
