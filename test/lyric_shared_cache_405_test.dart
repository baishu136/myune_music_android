import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/services/interaction_performance_controller.dart';
import 'package:myune_music/widgets/lyric_plain_foreground.dart';
import 'package:myune_music/widgets/lyric_plain_raster.dart';
import 'package:myune_music/widgets/lyric_raster_pool.dart';
import 'package:myune_music/widgets/lyric_shared_focus.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';

Future<void> idle(WidgetTester tester) async {
  for (var i = 0; i < 35; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
}

void main() {
  testWidgets(
    'queued foreground and glow reservations cancel together on unmount',
    (tester) async {
      final protection = InteractionPerformanceController.instance
          .beginTransition();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(devicePixelRatio: 3),
              child: MobileLyricsList(
                lines: List.generate(
                  12,
                  (i) => LyricLine(
                    timestamp: Duration(seconds: i * 3),
                    texts: ['等待正文及光晕 $i'],
                  ),
                ),
                active: 3,
                fontSize: 32,
                highlightActiveLine: true,
                glowEnabled: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(LyricRasterPool.pixels, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(LyricRasterPool.pixels, 0);
      protection.release();
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'default motion and focus share progress without reversal or a landing tail',
    (tester) async {
      var active = 3;
      var karaoke = false;
      late StateSetter update;
      final lines = List.generate(
        30,
        (i) => LyricLine(
          timestamp: Duration(seconds: i * 3),
          texts: ['连续滚动长句 office ygp $i', 'Translation $i'],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return MobileLyricsList(
                  lines: lines,
                  active: active,
                  fontSize: 40,
                  karaokeLyricsEnabled: karaoke,
                  highlightActiveLine: true,
                  lineBlurEnabled: true,
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final list = tester.widget<ListView>(find.byType(ListView));
      final scroll = list.controller!;
      update(() => active = 4);
      await tester.pump();
      final row = find.byKey(const ValueKey('mobile_lyric_4'));
      final scaleFinder = find.descendant(
        of: row,
        matching: find.byType(ScaleTransition),
      );
      final scope = tester.widget<LyricSharedFocusScope>(
        find
            .ancestor(of: row, matching: find.byType(LyricSharedFocusScope))
            .first,
      );
      var previous = scroll.offset;
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(scroll.offset, greaterThanOrEqualTo(previous - 1e-8));
        previous = scroll.offset;
        final scale = tester.widget<ScaleTransition>(scaleFinder).scale.value;
        expect(scale, closeTo(1 + .1 * scope.phase!.value, 1e-8));
      }
      final landed = scroll.offset;
      await tester.pump(const Duration(milliseconds: 300));
      expect(scroll.offset, landed);
      update(() => active = 5);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      final pose = tester
          .widget<ScaleTransition>(
            find.descendant(of: row, matching: find.byType(ScaleTransition)),
          )
          .scale
          .value;
      update(() => active = 6);
      await tester.pump();
      expect(
        tester
            .widget<ScaleTransition>(
              find.descendant(of: row, matching: find.byType(ScaleTransition)),
            )
            .scale
            .value,
        closeTo(pose, 1e-8),
      );
      final offset = scroll.offset;
      update(() => karaoke = true);
      await tester.pump();
      expect(scroll.offset, closeTo(offset, 1e-8));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await idle(tester);
      expect(LyricRasterPool.pixels, 0);
    },
  );

  testWidgets(
    'native RGB raster waits for idle, retains alpha-only ink and releases on invalidation',
    (tester) async {
      final protection = InteractionPerformanceController.instance
          .beginTransition();
      var color = const Color(0xff757575).withValues(alpha: .4);
      var font = 32.0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(devicePixelRatio: 3),
            child: Center(
              child: SizedBox(
                width: 260,
                child: StatefulBuilder(
                  builder: (_, setState) {
                    update = setState;
                    return LyricRasterScope(
                      rank: 0,
                      child: DefaultTextStyle(
                        style: TextStyle(fontSize: font, color: color),
                        child: const LyricPlainForeground(
                          text: '原生RGB office 中文',
                          textAlign: TextAlign.left,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final render = tester.renderObject<RenderLyricPlainRaster>(
        find.byType(LyricPlainRaster),
      );
      expect(render.debugImage, isNull);
      protection.release();
      await idle(tester);
      final image = render.debugImage;
      expect(image, isNotNull);
      expect(LyricRasterPool.pixels, lessThanOrEqualTo(LyricRasterPool.limit));
      update(() => color = color.withValues(alpha: .8));
      await tester.pump();
      expect(render.debugImage, same(image));
      update(() => font = 40);
      await tester.pump();
      expect(image!.debugDisposed, isTrue);
      await idle(tester);
      expect(render.debugImage, isNotNull);
      await tester.pumpWidget(const SizedBox());
      await idle(tester);
      expect(LyricRasterPool.pixels, 0);
    },
  );

  testWidgets(
    'ready foreground raster preserves native colors and stationary pixels',
    (tester) async {
      await tester.runAsync(() async {
        await (FontLoader(
          'Ink405',
        )..addFont(rootBundle.load('assets/fonts/MiSansVF.ttf'))).load();
      });
      Future<List<int>> pixels(Color color, bool cached) async {
        final key = GlobalKey();
        Widget ink = const LyricPlainForeground(
          text: 'office ygp 中文\nسلام हिन्दी',
          textAlign: TextAlign.left,
        );
        if (cached) ink = LyricRasterScope(rank: 0, child: ink);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(devicePixelRatio: 2),
              child: Center(
                child: RepaintBoundary(
                  key: key,
                  child: SizedBox(
                    width: 290,
                    height: 180,
                    child: ColoredBox(
                      color: const Color(0xff163044),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: DefaultTextStyle(
                          style: TextStyle(
                            fontFamily: 'Ink405',
                            fontSize: 27,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                          child: ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await idle(tester);
        if (cached) {
          expect(
            tester
                .renderObject<RenderLyricPlainRaster>(
                  find.byType(LyricPlainRaster),
                )
                .debugImage,
            isNotNull,
          );
        }
        late List<int> bytes;
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          const output = String.fromEnvironment('LYRIC405_REVIEW_DIR');
          if (output.isNotEmpty) {
            final dir = Directory(output)..createSync(recursive: true);
            File(
              '${dir.path}/${color.toARGB32()}-${cached ? 'cached' : 'native'}.png',
            ).writeAsBytesSync(
              (await image.toByteData(
                format: ui.ImageByteFormat.png,
              ))!.buffer.asUint8List(),
            );
          }
          bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List().toList();
          image.dispose();
        });
        return bytes;
      }

      for (final color in [
        Colors.white.withValues(alpha: .4),
        const Color(0xffeb6fa9).withValues(alpha: .73),
        const Color(0xff757575),
      ]) {
        final native = await pixels(color, false),
            cached = await pixels(color, true);
        var sum = 0, max = 0;
        for (var i = 0; i < native.length; i++) {
          final e = (native[i] - cached[i]).abs();
          sum += e;
          if (e > max) max = e;
        }
        expect(sum / native.length, lessThan(.25));
        expect(max, lessThanOrEqualTo(3));
      }
      await tester.pumpWidget(const SizedBox());
      await idle(tester);
      expect(LyricRasterPool.pixels, 0);
    },
  );
}
