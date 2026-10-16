import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';

Future<void> _fonts(WidgetTester tester) => tester.runAsync(() async {
  await (FontLoader(
    'Glow398',
  )..addFont(rootBundle.load('assets/fonts/MiSansVF.ttf'))).load();
});

Finder _glow([int row = 0]) => find.descendant(
  of: find.byKey(ValueKey('mobile_lyric_$row')),
  matching: find.byKey(const ValueKey('mobile_lyric_glow_layer')),
);

MobileLyricGlowPainter _painter(WidgetTester tester, [int row = 0]) =>
    tester.widget<CustomPaint>(_glow(row)).painter! as MobileLyricGlowPainter;

Future<void> _warm(WidgetTester tester, [int row = 0]) async {
  for (var i = 0; i < 80 && _painter(tester, row).preparedRaster == null; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(_painter(tester, row).preparedRaster, isNotNull);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await tester.pump();
  expect(debugMobileLyricGlowRasterPixels, 0);
}

Widget _host(Widget child, {double dpr = 3}) => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(devicePixelRatio: dpr),
      child: Center(child: SizedBox(width: 260, height: 600, child: child)),
    ),
  ),
);

void main() {
  testWidgets('normal glow keeps native density, pixels and original strength', (
    tester,
  ) async {
    await _fonts(tester);
    for (final radius in [8.0, 20.0]) {
      for (final font in [20.0, 40.0]) {
        await tester.pumpWidget(
          _host(
            MobileLyricsList(
              lines: [
                LyricLine(
                  timestamp: Duration.zero,
                  texts: const ['中文 office ygp 切换', 'Translation 多行翻译文字'],
                ),
              ],
              active: 0,
              fontFamily: 'Glow398',
              fontSize: font,
              fontWeight: FontWeight.w800,
              highlightActiveLine: true,
              glowEnabled: true,
              glowRadius: radius,
            ),
          ),
        );
        await _warm(tester);
        final cached = _painter(tester),
            image = _painter(tester).preparedRaster!;
        expect(image.width * image.height, lessThanOrEqualTo(2097152));
        expect(
          image.width / cached.preparedRasterBounds!.width,
          closeTo(3, 1e-8),
        );
        expect(cached.color, Colors.white.withValues(alpha: .3));
        expect(cached.blurRadius, radius);
        final vector = MobileLyricGlowPainter(
          text: cached.text,
          style: cached.style,
          color: cached.color,
          blurRadius: cached.blurRadius,
          textAlign: cached.textAlign,
          textDirection: cached.textDirection,
          textScaler: cached.textScaler,
          locale: cached.locale,
          primaryRowOnly: cached.primaryRowOnly,
          preparedLayout: cached.preparedLayout,
        );
        final size = Size(
          cached.preparedLayout!.width,
          cached.preparedLayout!.height,
        );
        Future<List<int>> render(
          MobileLyricGlowPainter painter,
          double scale,
        ) async {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder)
            ..scale(3 * scale)
            ..drawColor(const Color(0xff183244), BlendMode.src)
            ..translate(64, 64);
          painter.paint(canvas, size);
          final picture = recorder.endRecording();
          final frame = await picture.toImage(
            ((size.width + 128) * 3 * scale).ceil(),
            ((size.height + 128) * 3 * scale).ceil(),
          );
          final bytes = await frame.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final result = bytes!.buffer.asUint8List().toList();
          frame.dispose();
          picture.dispose();
          return result;
        }

        for (final scale in [1.0, 1.05, 1.1]) {
          late List<int> expected, actual;
          await tester.runAsync(() async {
            expected = await render(vector, scale);
            actual = await render(cached, scale);
          });
          var sum = 0, maximum = 0;
          for (var i = 0; i < actual.length; i++) {
            final error = (actual[i] - expected[i]).abs();
            sum += error;
            if (error > maximum) maximum = error;
          }
          // Stationary native pixels retain the stricter reference. A scaled
          // cached glow is sampled as an image; native vector text is rehinted.
          expect(sum / actual.length, lessThan(scale == 1 ? .25 : .30));
          expect(maximum, lessThanOrEqualTo(scale == 1 ? 3 : 8));
        }
        await _unmount(tester);
        expect(image.debugDisposed, isTrue);
      }
    }
  });

  testWidgets(
    'focus alpha reuses glow image; typography and unmount release it',
    (tester) async {
      await _fonts(tester);
      var active = 2, font = 20.0;
      late StateSetter update;
      final lines = List.generate(
        20,
        (i) => LyricLine(
          timestamp: Duration(seconds: i * 3),
          texts: ['连续滚动歌词 $i', 'Translation $i'],
        ),
      );
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return MobileLyricsList(
                lines: lines,
                active: active,
                fontSize: font,
                fontFamily: 'Glow398',
                highlightActiveLine: true,
                glowEnabled: true,
                lineBlurEnabled: true,
              );
            },
          ),
        ),
      );
      await _warm(tester, 3);
      final before = _painter(tester, 3),
          image = _painter(tester, 3).preparedRaster!;
      update(() => active = 3);
      await tester.pump();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(_painter(tester, 3).preparedRaster, same(image));
        expect(_painter(tester, 3).preparedLayout, same(before.preparedLayout));
        expect(
          debugMobileLyricGlowRasterPixels,
          lessThanOrEqualTo(8 * 1024 * 1024),
        );
      }
      update(() => font = 32);
      await tester.pump();
      expect(image.debugDisposed, isTrue);
      await _warm(tester, 3);
      expect(_painter(tester, 3).preparedRaster, isNot(same(image)));
      await _unmount(tester);
    },
  );

  testWidgets(
    'small shadows and oversized lines retain complete vector output',
    (tester) async {
      for (final sample in [
        (2.0, 'office 中文'),
        (8.0, List.filled(300, 'oversized 中文').join(' ')),
      ]) {
        await tester.pumpWidget(
          _host(
            MobileLyricsList(
              lines: [
                LyricLine(timestamp: Duration.zero, texts: [sample.$2]),
              ],
              active: 0,
              fontSize: 40,
              highlightActiveLine: true,
              glowEnabled: true,
              glowRadius: sample.$1,
            ),
          ),
        );
        await tester.pump();
        final painter = _painter(tester);
        expect(painter.preparedLayout, isNotNull);
        expect(painter.preparedRaster, isNull);
        expect(debugMobileLyricGlowRasterPixels, 0);
        await _unmount(tester);
      }
    },
  );

  testWidgets('mounted and pending glows share one bounded pixel reservation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(devicePixelRatio: 3),
            child: MobileLyricsList(
              lines: List.generate(
                100,
                (i) => LyricLine(
                  timestamp: Duration(seconds: i * 3),
                  texts: ['glow budget 中文 $i'],
                ),
              ),
              active: 10,
              fontSize: 30,
              highlightActiveLine: true,
              glowEnabled: true,
            ),
          ),
        ),
      ),
    );
    expect(debugMobileLyricGlowRasterPixels, greaterThan(0));
    expect(
      debugMobileLyricGlowRasterPixels,
      lessThanOrEqualTo(8 * 1024 * 1024),
    );
    await _unmount(tester);
  });
}
