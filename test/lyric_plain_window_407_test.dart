import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/services/interaction_performance_controller.dart';
import 'package:myune_music/widgets/lyric_plain_foreground.dart';
import 'package:myune_music/widgets/lyric_plain_prewarm.dart';
import 'package:myune_music/widgets/lyric_plain_raster.dart';
import 'package:myune_music/widgets/lyric_raster_pool.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';

Future<void> frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
  }
}

void main() {
  testWidgets(
    'production prepared rows preserve native paragraph pixels at both font sizes',
    (tester) async {
      await tester.runAsync(() async {
        await (FontLoader(
          'List407',
        )..addFont(rootBundle.load('assets/fonts/MiSansVF.ttf'))).load();
      });
      final lines = List.generate(
        12,
        (i) => LyricLine(
          timestamp: Duration(seconds: i * 3),
          texts: ['中文 office $i', 'ygp $i'],
        ),
      );
      for (final font in [32.0, 40.0]) {
        final protection = InteractionPerformanceController.instance
            .beginTransition();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.light(),
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(devicePixelRatio: 3),
                child: SizedBox(
                  width: 360,
                  height: 800,
                  child: MobileLyricsList(
                    lines: lines,
                    active: 3,
                    fontFamily: 'List407',
                    fontSize: font,
                    fontWeight: FontWeight.w800,
                    karaokeLyricsEnabled: false,
                    highlightActiveLine: true,
                    lineBlurEnabled: true,
                  ),
                ),
              ),
            ),
          ),
        );
        Future<List<int>> pixels(int row, String label) async {
          final alpha = find.descendant(
            of: find.byKey(ValueKey('mobile_lyric_$row')),
            matching: find.byKey(
              const ValueKey('mobile_lyric_foreground_opacity'),
            ),
          );
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find
                .descendant(of: alpha, matching: find.byType(RepaintBoundary))
                .first,
          );
          late List<int> bytes;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 3);
            const output = String.fromEnvironment('PLAIN407_EXPORT');
            if (output.isNotEmpty) {
              final dir = Directory(output)..createSync(recursive: true);
              File('${dir.path}/$label-$font-$row.png').writeAsBytesSync(
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

        final native = [await pixels(3, 'native'), await pixels(4, 'native')];
        protection.release();
        await frames(tester, 120);
        for (var i = 0; i < 2; i++) {
          final row = i + 3;
          final render = tester.renderObject<RenderLyricPlainRaster>(
            find.descendant(
              of: find.byKey(ValueKey('mobile_lyric_$row')),
              matching: find.byType(LyricPlainRaster),
            ),
          );
          expect(render.debugImage, isNotNull);
          final cached = await pixels(row, 'cached');
          var sum = 0, max = 0;
          for (var p = 0; p < cached.length; p++) {
            final error = (cached[p] - native[i][p]).abs();
            sum += error;
            if (error > max) max = error;
          }
          expect(sum / cached.length, lessThan(.25));
          expect(max, lessThanOrEqualTo(3));
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await frames(tester, 30);
        expect(LyricRasterPool.pixels, 0);
      }
    },
  );
  testWidgets(
    'dense ordinary lines enter with prepared native ink and release the shared budget',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var active = 3;
      late StateSetter update;
      final lines = List.generate(
        40,
        (i) => LyricLine(
          timestamp: Duration(milliseconds: i * 400),
          texts: ['连续短句 office $i', 'Translation $i'],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return MobileLyricsList(
                  lines: lines,
                  active: active,
                  fontSize: 40,
                  karaokeLyricsEnabled: false,
                  highlightActiveLine: true,
                  lineBlurEnabled: true,
                );
              },
            ),
          ),
        ),
      );
      await frames(tester, 150);
      for (var i = 4; i < 13; i++) {
        update(() => active = i);
        await tester.pump();
        final render = tester.renderObject<RenderLyricPlainRaster>(
          find.descendant(
            of: find.byKey(ValueKey('mobile_lyric_$i')),
            matching: find.byType(LyricPlainRaster),
          ),
        );
        expect(
          render.debugImage,
          isNotNull,
          reason: 'short row $i was not prepared before entry',
        );
        final image = render.debugImage;
        await frames(tester, 25);
        expect(render.debugImage, same(image));
        expect(
          LyricRasterPool.pixels,
          lessThanOrEqualTo(LyricRasterPool.limit),
        );
      }
      update(() => active = 30);
      await tester.pump();
      await frames(tester, 80);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await frames(tester, 60);
      expect(LyricRasterPool.pixels, 0);
    },
  );

  testWidgets(
    'time-window entries prepare beyond mounted rows and obey real gesture protection',
    (tester) async {
      final owner = LyricPlainPrewarm();
      final lines = List.generate(
        30,
        (i) => LyricLine(
          timestamp: Duration(milliseconds: i * 300),
          texts: ['未来 $i'],
        ),
      );
      final protect = InteractionPerformanceController.instance
          .beginTransition();
      owner.update(
        lines: lines,
        active: 0,
        rate: 1,
        visible: true,
        eligible: (_) => true,
        width: 300,
        dpr: 3,
        style: const TextStyle(fontSize: 32, height: 1.2),
        align: TextAlign.left,
        direction: TextDirection.ltr,
        scaler: TextScaler.noScaling,
        locale: null,
        inactive: Colors.white,
        activeColor: Colors.white,
      );
      for (final i in owner.indices) {
        owner.at(i)!.measureHeight(38.4);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await frames(tester, 4);
      expect(owner.indices.length, 7);
      expect(owner.at(6)!.image, isNull);
      protect.release();
      final motion = InteractionPerformanceController.instance
          .beginVisualAnimation(allowResourcePreparation: true);
      await frames(tester, 110);
      expect(owner.at(6)!.image, isNotNull);
      expect(LyricRasterPool.pixels, lessThanOrEqualTo(LyricRasterPool.limit));
      owner.clear();
      motion.release();
      await frames(tester, 30);
      expect(LyricRasterPool.pixels, 0);
      final held = List.generate(
        20,
        (i) => LyricLine(
          timestamp: i == 0
              ? Duration.zero
              : Duration(milliseconds: 20000 + (i - 1) * 300),
          texts: ['长音之后的短句 $i'],
        ),
      );
      owner.update(
        lines: held,
        active: 0,
        rate: 1,
        visible: true,
        eligible: (_) => true,
        width: 300,
        dpr: 3,
        style: const TextStyle(fontSize: 32, height: 1.2),
        align: TextAlign.left,
        direction: TextDirection.ltr,
        scaler: TextScaler.noScaling,
        locale: null,
        inactive: Colors.white,
        activeColor: Colors.white,
      );
      expect(
        owner.indices.length,
        7,
        reason: 'held note must not hide the upcoming dense verse',
      );
      owner.clear();
      await frames(tester, 10);
      expect(LyricRasterPool.pixels, 0);
    },
  );

  testWidgets(
    'RGB transitions retain endpoint images and never substitute an approximate tint',
    (tester) async {
      await tester.runAsync(() async {
        await (FontLoader(
          'Native407',
        )..addFont(rootBundle.load('assets/fonts/MiSansVF.ttf'))).load();
      });
      const text = 'office ygp 中文\nسلام हिन्दी';
      const style = TextStyle(
        fontFamily: 'Native407',
        fontSize: 27,
        height: 1.2,
        fontWeight: FontWeight.w800,
      );
      const from = Color(0xff757575), to = Color(0xffeb6fa9);
      final owner = LyricPlainPrewarm();
      final line = LyricLine(timestamp: Duration.zero, texts: [text]);
      owner.update(
        lines: [line],
        active: 0,
        rate: 1,
        visible: true,
        eligible: (_) => true,
        width: 254,
        dpr: 2,
        style: style,
        align: TextAlign.left,
        direction: TextDirection.ltr,
        scaler: TextScaler.noScaling,
        locale: null,
        inactive: from,
        activeColor: to,
      );
      final measure = TextPainter(
        text: const TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout(minWidth: 254, maxWidth: 254);
      owner.at(0)!.measureHeight(measure.height);
      measure.dispose();
      var color = from.withValues(alpha: .4), managed = true;
      late StateSetter update;
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                Widget ink = const LyricPlainForeground(
                  text: text,
                  textAlign: TextAlign.left,
                );
                if (managed) {
                  ink = LyricPlainPrewarmScope(
                    entry: owner.at(0),
                    child: LyricRasterScope(rank: 0, child: ink),
                  );
                }
                return RepaintBoundary(
                  key: key,
                  child: SizedBox(
                    width: 290,
                    height: 180,
                    child: ColoredBox(
                      color: const Color(0xff163044),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: MediaQuery(
                          data: const MediaQueryData(devicePixelRatio: 2),
                          child: DefaultTextStyle(
                            style: style.copyWith(color: color),
                            child: ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await frames(tester, 100);
      final entry = owner.at(0)!;
      final image = entry.image;
      expect(image, isNotNull);
      Future<List<int>> pixels() async {
        late List<int> bytes;
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List().toList();
          image.dispose();
        });
        return bytes;
      }

      for (final t in [0.0, .15, .5, .85, 1.0, 0.0]) {
        final beforeLayout = tester
            .renderObject<RenderLyricPlainRaster>(find.byType(LyricPlainRaster))
            .debugLayoutCount;
        update(() {
          color = Color.lerp(from, to, t)!.withValues(alpha: .73);
          managed = true;
        });
        await tester.pump();
        final render = tester.renderObject<RenderLyricPlainRaster>(
          find.byType(LyricPlainRaster),
        );
        expect(
          render.debugLayoutCount,
          beforeLayout,
          reason: 'paint-only RGB change forced row layout',
        );
        expect(entry.image, same(image));
        expect(render.debugRetainedImage, same(image));
        if (t == 0 || t == 1) {
          expect(render.debugImage, same(entry.imageFor(color)));
          expect(render.debugImage, isNotNull);
        } else {
          expect(
            render.debugImage,
            isNull,
            reason: 'RGB intermediate must retain native edge coverage',
          );
        }
        final cached = await pixels();
        update(() => managed = false);
        await tester.pump();
        final native = await pixels();
        var sum = 0, max = 0;
        for (var i = 0; i < native.length; i++) {
          final e = (native[i] - cached[i]).abs();
          sum += e;
          if (e > max) max = e;
        }
        expect(sum / native.length, lessThan(.25));
        expect(max, lessThanOrEqualTo(3));
        // managed toggles replace the RenderObject; reacquire after the next frame.
        update(() => managed = true);
        await tester.pump();
      }
      owner.clear();
      await tester.pumpWidget(const SizedBox.shrink());
      await frames(tester, 30);
      expect(LyricRasterPool.pixels, 0);
    },
  );

  testWidgets('long RGB rows retain the per-image limit and shared budget', (
    tester,
  ) async {
    final owner = LyricPlainPrewarm();
    const text = 'one\ntwo\nthree\nfour\nfive\nsix\nseven\neight';
    const style = TextStyle(fontSize: 40, height: 1.2);
    const from = Colors.grey, to = Colors.pink;
    owner.update(
      lines: [
        LyricLine(timestamp: Duration.zero, texts: [text]),
      ],
      active: 0,
      rate: 1,
      visible: true,
      eligible: (_) => true,
      width: 350,
      dpr: 3,
      style: style,
      align: TextAlign.left,
      direction: TextDirection.ltr,
      scaler: TextScaler.noScaling,
      locale: null,
      inactive: from,
      activeColor: to,
    );
    final measure = TextPainter(
      text: const TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 350, maxWidth: 350);
    final entry = owner.at(0)!;
    entry.measureHeight(measure.height);
    measure.dispose();
    expect(entry.rasterDemand, greaterThan(2097152));
    expect(entry.rasterDemand, lessThanOrEqualTo(LyricRasterPool.limit));
    await tester.pumpWidget(const SizedBox.shrink());
    await frames(tester, 100);
    for (final color in [from, to]) {
      final image = entry.imageFor(color);
      expect(image, isNotNull);
      expect(image!.width * image.height, lessThanOrEqualTo(2097152));
    }
    expect(LyricRasterPool.pixels, lessThanOrEqualTo(LyricRasterPool.limit));
    owner.clear();
    await frames(tester, 30);
    expect(LyricRasterPool.pixels, 0);
  });
}
