import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/interaction_motion.dart';
import 'package:myune_music/widgets/navigation_motion_icon.dart';

Future<double> _ink(WidgetTester tester, GlobalKey capture) async {
  var alpha = 0.0;
  await tester.runAsync(() async {
    final image =
        await (capture.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
    final pixels = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    for (var i = 3; i < pixels.length; i += 4) {
      alpha += pixels[i] / 255;
    }
    image.dispose();
  });
  return alpha;
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'misans',
    )..addFont(rootBundle.load('assets/fonts/MiSansVF.ttf'))).load();
  });
  for (final cancellation in ['hidden', 'background', 'reduced', 'dispose']) {
    testWidgets('pending navigation fill settles on $cancellation', (
      tester,
    ) async {
      var selected = false, visible = true, reduced = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reduced),
                child: TickerMode(
                  enabled: visible,
                  child: NavigationMotionIcon(
                    kind: IconMotion.album,
                    selected: selected,
                  ),
                ),
              );
            },
          ),
        ),
      );
      update(() => selected = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(
        tester
            .widget<NavigationGlyph>(find.byType(NavigationGlyph))
            .fillProgress,
        inExclusiveRange(0, 1),
      );
      if (cancellation == 'dispose') {
        await tester.pumpWidget(const SizedBox());
      } else if (cancellation == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
      } else {
        update(() {
          visible = cancellation != 'hidden';
          reduced = cancellation == 'reduced';
        });
        await tester.pump();
      }
      if (cancellation != 'dispose') {
        expect(
          tester
              .widget<NavigationGlyph>(find.byType(NavigationGlyph))
              .fillProgress,
          1,
        );
        update(() {
          visible = true;
          reduced = false;
        });
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
      }
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('production fill and indicator remain coherent: $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 220);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final capture = GlobalKey();
      var selected = 4;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness, fontFamily: 'misans'),
          home: RepaintBoundary(
            key: capture,
            child: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: const SizedBox.expand(),
                bottomNavigationBar: MyuneNavigationBar(
                  selectedIndex: selected,
                  onDestinationSelected: (i) => setState(() => selected = i),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      const labels = ['音乐库', '歌单', '歌手', '专辑', '设置'];
      for (var i = 0; i < labels.length; i++) {
        await tester.tap(find.text(labels[i]));
        await tester.pump();
        var previous = 0;
        for (final milliseconds in [0, 60, 120, 200, 300, 620]) {
          await tester.pump(Duration(milliseconds: milliseconds - previous));
          previous = milliseconds;
          final dir = Platform.environment['FILL446_PREVIEW_DIR'];
          if (dir != null) {
            await tester.runAsync(() async {
              final image =
                  await (capture.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 2);
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '$dir/${brightness.name}-$i-$milliseconds.png',
              ).writeAsBytes(png!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          i,
        );
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .animationDuration,
          const Duration(milliseconds: 300),
        );
        final glyphs = tester
            .widgetList<NavigationGlyph>(find.byType(NavigationGlyph))
            .toList();
        for (var j = 0; j < glyphs.length; j++) {
          expect(glyphs[j].fillProgress, j == i ? 1 : 0);
        }
        await tester.tap(find.text(labels[i]));
        await tester.pump();
        expect(
          tester
              .widgetList<NavigationGlyph>(find.byType(NavigationGlyph))
              .elementAt(i)
              .fillProgress,
          1,
        );
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final kind in [
    IconMotion.library,
    IconMotion.playlist,
    IconMotion.artist,
    IconMotion.album,
    IconMotion.settings,
  ]) {
    testWidgets('selected ${kind.name} has a readable solid treatment', (
      tester,
    ) async {
      var selected = false;
      late StateSetter update;
      final capture = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return RepaintBoundary(
                  key: capture,
                  child: IconTheme(
                    data: const IconThemeData(size: 96, color: Colors.white),
                    child: NavigationGlyph(
                      kind: kind,
                      phase: 1,
                      selected: selected,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      final outline = await _ink(tester, capture);
      update(() => selected = true);
      await tester.pump();
      final solid = await _ink(tester, capture);
      expect(
        solid / outline,
        greaterThan(kind == IconMotion.playlist ? 1.2 : 1.5),
      );
    });
  }
  testWidgets('fill begins without a jump and reverses from visible coverage', (
    tester,
  ) async {
    var selected = false;
    late StateSetter update;
    final capture = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return RepaintBoundary(
                key: capture,
                child: IconTheme(
                  data: const IconThemeData(size: 96, color: Colors.white),
                  child: NavigationMotionIcon(
                    kind: IconMotion.artist,
                    selected: selected,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    final outline = await _ink(tester, capture);
    update(() => selected = true);
    await tester.pump();
    expect(await _ink(tester, capture), closeTo(outline, outline * .03));
    await tester.pump(const Duration(milliseconds: 130));
    final middle = await _ink(tester, capture);
    expect(middle, greaterThan(outline * 1.2));
    update(() => selected = false);
    await tester.pump();
    expect(await _ink(tester, capture), closeTo(middle, middle * .03));
    await tester.pump(const Duration(milliseconds: 60));
    final withdrawing = await _ink(tester, capture);
    expect(withdrawing, lessThan(middle));
    update(() => selected = true);
    await tester.pump();
    expect(
      await _ink(tester, capture),
      closeTo(withdrawing, withdrawing * .03),
    );
    await tester.pumpAndSettle();
    expect(await _ink(tester, capture), greaterThan(outline * 1.5));
    expect(tester.binding.transientCallbackCount, 0);
  });
}
