import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/services/interaction_performance_controller.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';
import 'package:myune_music/widgets/lyric_raster_pool.dart';

MobileLyricGlowPainter glow(WidgetTester tester, int row) =>
    tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byKey(ValueKey('mobile_lyric_$row')),
                matching: find.byKey(const ValueKey('mobile_lyric_glow_layer')),
              ),
            )
            .painter!
        as MobileLyricGlowPainter;

Future<void> waitForGlows(WidgetTester tester, List<int> rows) async {
  for (var i = 0; i < 120; i++) {
    if (rows.every((row) => glow(tester, row).preparedRaster != null)) return;
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    expect(
      debugMobileLyricGlowRasterPixels,
      lessThanOrEqualTo(8 * 1024 * 1024),
    );
  }
  for (final row in rows) {
    expect(glow(tester, row).preparedRaster, isNotNull, reason: 'row $row');
  }
}

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
  expect(debugMobileLyricGlowRasterPixels, 0);
}

void main() {
  testWidgets(
    'colored glow cache retains native shadow colors and pixel precision',
    (tester) async {
      await tester.runAsync(() async {
        await (FontLoader(
          'Glow401',
        )..addFont(rootBundle.load('assets/fonts/MiSansVF.ttf'))).load();
      });
      for (final color in [Colors.pink, const Color(0xff757575)]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.light(),
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(devicePixelRatio: 3),
                child: SizedBox(
                  width: 260,
                  height: 600,
                  child: MobileLyricsList(
                    lines: [
                      LyricLine(
                        timestamp: Duration.zero,
                        texts: const ['中文 office ygp 切换', 'Translation 多行翻译文字'],
                      ),
                    ],
                    active: 0,
                    activeColor: color,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Glow401',
                    glowEnabled: true,
                  ),
                ),
              ),
            ),
          ),
        );
        await waitForGlows(tester, [0]);
        final cached = glow(tester, 0);
        final native = MobileLyricGlowPainter(
          text: cached.text,
          style: cached.style,
          color: cached.color,
          blurRadius: cached.blurRadius,
          textAlign: cached.textAlign,
          textDirection: cached.textDirection,
          textScaler: cached.textScaler,
          locale: cached.locale,
          primaryRowOnly: cached.primaryRowOnly,
        );
        Future<List<int>> pixels(
          MobileLyricGlowPainter painter,
          double scale,
        ) async {
          final size = Size(
            cached.preparedLayout!.width,
            cached.preparedLayout!.height,
          );
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder)
            ..scale(3 * scale)
            ..drawColor(const Color(0xff183244), BlendMode.src)
            ..translate(64, 64);
          painter.paint(canvas, size);
          final picture = recorder.endRecording();
          final image = await picture.toImage(
            ((size.width + 128) * 3 * scale).ceil(),
            ((size.height + 128) * 3 * scale).ceil(),
          );
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final result = bytes!.buffer.asUint8List().toList();
          image.dispose();
          picture.dispose();
          return result;
        }

        for (final scale in [1.0, 1.1]) {
          late List<int> actual, expected;
          await tester.runAsync(() async {
            actual = await pixels(cached, scale);
            expected = await pixels(native, scale);
          });
          var sum = 0, maximum = 0;
          for (var i = 0; i < actual.length; i++) {
            final error = (actual[i] - expected[i]).abs();
            sum += error;
            if (error > maximum) maximum = error;
          }
          expect(sum / actual.length, lessThan(scale == 1 ? .25 : .30));
          expect(maximum, lessThanOrEqualTo(scale == 1 ? 3 : 8));
        }
        await unmount(tester);
      }
    },
  );

  testWidgets(
    'budget pressure prepares focus and adjacent glows first and preserves them across a handoff',
    (tester) async {
      tester.view.physicalSize = const Size(900, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await (FontLoader(
          'Glow401',
        )..addFont(rootBundle.load('assets/fonts/MiSansVF.ttf'))).load();
      });
      var active = 15;
      late StateSetter update;
      final lines = List.generate(
        60,
        (i) => LyricLine(
          timestamp: Duration(seconds: i * 3),
          texts: ['中文多行歌词 office $i', 'Translation 多行翻译文字 $i'],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(devicePixelRatio: 4),
              child: SizedBox(
                width: 300,
                height: 1800,
                child: StatefulBuilder(
                  builder: (_, setState) {
                    update = setState;
                    return MobileLyricsList(
                      lines: lines,
                      active: active,
                      fontSize: 40,
                      fontFamily: 'Glow401',
                      fontWeight: FontWeight.w800,
                      highlightActiveLine: true,
                      glowEnabled: true,
                      lineBlurEnabled: true,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      // Native foreground ink now shares the budget. Under this pressure the
      // focus/next glows win; other glows retain their exact native painter.
      await waitForGlows(tester, [15, 16]);
      final retained = {
        for (final row in [15, 16]) row: glow(tester, row).preparedRaster!,
      };
      expect(LyricRasterPool.pixels, lessThanOrEqualTo(8 * 1024 * 1024));
      final mounted = tester
          .widgetList<CustomPaint>(
            find.byKey(const ValueKey('mobile_lyric_glow_layer')),
          )
          .map((paint) => paint.painter)
          .whereType<MobileLyricGlowPainter>()
          .toList();
      expect(
        mounted.where((painter) => painter.preparedRaster == null),
        isNotEmpty,
      );
      update(() => active = 16);
      await tester.pump();
      await waitForGlows(tester, [16, 17]);
      for (final entry in retained.entries) {
        if (entry.key == 16) {
          expect(glow(tester, entry.key).preparedRaster, same(entry.value));
        }
      }
      await unmount(tester);
      for (final image in retained.values) {
        expect(image.debugDisposed, isTrue);
      }
    },
  );

  testWidgets(
    'queued normal glow work cancels without retaining its budget after unmount',
    (tester) async {
      final protection = InteractionPerformanceController.instance
          .beginTransition();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileLyricsList(
              lines: List.generate(
                20,
                (i) => LyricLine(
                  timestamp: Duration(seconds: i * 3),
                  texts: ['等待资源 $i'],
                ),
              ),
              active: 4,
              fontSize: 32,
              highlightActiveLine: true,
              glowEnabled: true,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(debugMobileLyricGlowRasterPixels, greaterThan(0));
      expect(glow(tester, 4).preparedRaster, isNull);
      await tester.pumpWidget(const SizedBox());
      protection.release();
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(debugMobileLyricGlowRasterPixels, 0);
    },
  );

  testWidgets(
    'colored focus reuses ready glow images without rebuilding native glow layout',
    (tester) async {
      var active = 2;
      late StateSetter update;
      final lines = List.generate(
        6,
        (i) => LyricLine(
          timestamp: Duration(seconds: i * 3),
          texts: ['office $i', '中文 $i'],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(devicePixelRatio: 2),
              child: SizedBox(
                width: 300,
                height: 600,
                child: StatefulBuilder(
                  builder: (_, setState) {
                    update = setState;
                    return MobileLyricsList(
                      lines: lines,
                      active: active,
                      activeColor: Colors.pink,
                      fontSize: 20,
                      glowEnabled: true,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await waitForGlows(tester, [0, 1, 2, 3, 4, 5]);
      final image = glow(tester, 3).preparedRaster;
      final layouts = debugMobileLyricGlowLayoutCount;
      update(() => active = 3);
      await tester.pump();
      for (var i = 0; i < 45; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(glow(tester, 3).preparedRaster, same(image));
        expect(debugMobileLyricGlowLayoutCount, layouts);
      }
      expect(glow(tester, 3).color, Colors.pink.withValues(alpha: .3));
      await unmount(tester);
    },
  );

  test('resource priority follows the latest focus while queued', () async {
    final controller = InteractionPerformanceController.instance;
    final lease = await controller.acquireIdleWork();
    var priority = InteractionWorkPriority.background;
    final starts = <String>[];
    final first = controller.runIdleResource(() async {
      starts.add('focus');
      return 1;
    }, priorityForWork: () => priority);
    final second = controller.runIdleResource(() async {
      starts.add('other');
      return 2;
    }, priority: InteractionWorkPriority.userVisible);
    priority = InteractionWorkPriority.currentVisual;
    lease.release();
    await Future.wait([first, second]);
    expect(starts, ['focus', 'other']);
  });
}
