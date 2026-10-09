import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/widgets/custom_theme_background.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';
import 'package:myune_music/widgets/karaoke_sweep_path.dart';
import 'package:myune_music/services/interaction_performance_controller.dart';
import 'package:myune_music/page/setting/settings_provider.dart';

void main() {
  final pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  Widget background(Uint8List bytes, double blur, String label) => MaterialApp(
    home: CustomThemeBackground(
      path: null,
      enabled: false,
      dim: .6,
      coverEnabled: true,
      coverBytes: bytes,
      coverBlurSigma: blur,
      child: Text(label),
    ),
  );
  test('no playback focus leaves every ordinary row at its base color', () {
    for (var distance = 0; distance < 8; distance++) {
      expect(mobileLyricWholeLineHighlight(distance, hasFocus: false), 0);
    }
  });
  test(
    'slow feather is bounded and continuous; fast sweeps retain the baseline',
    () {
      expect(
        karaokeSweepFeather(width: 24, durationUs: 8000000, baseline: 14),
        closeTo(5.28, .00001),
      );
      expect(
        karaokeSweepFeather(width: 24, durationUs: 400000, baseline: 14),
        14,
      );
      var previous = 14.0;
      for (var duration = 500000; duration <= 8000000; duration += 10000) {
        final value = karaokeSweepFeather(
          width: 24,
          durationUs: duration,
          baseline: 14,
        );
        expect(value, inInclusiveRange(4.0, 14.0));
        expect(value, lessThanOrEqualTo(previous));
        expect((value - previous).abs(), lessThan(.5));
        previous = value;
      }
      for (final rtl in [false, true]) {
        final path = KaraokeSweepPath([(start: 0.0, end: 24.0)]);
        for (final feather in [5.28, 14.0]) {
          final start = path.frontAt(0, feather, rtl: rtl);
          final end = path.frontAt(1, feather, rtl: rtl);
          expect(start, rtl ? 24 + feather / 2 : -feather / 2);
          expect(end, rtl ? -feather / 2 : 24 + feather / 2);
        }
      }
    },
  );
  for (final effect in [
    LyricScrollEffect.standard,
    LyricScrollEffect.elastic,
  ]) {
    testWidgets(
      'completed scroll releases its own protection and retains another owner ($effect)',
      (tester) async {
        final active = ValueNotifier(2);
        final lines = List.generate(
          12,
          (i) => LyricLine(
            timestamp: Duration(seconds: i),
            texts: ['line $i'],
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<int>(
              valueListenable: active,
              builder: (_, index, _) => SizedBox(
                height: 600,
                child: MobileLyricsList(
                  lines: lines,
                  active: index,
                  scrollEffect: effect,
                  karaokeLyricsEnabled: false,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final controller = InteractionPerformanceController.instance;
        final other = controller.beginVisualAnimation();
        addTearDown(other.release);
        active.value = 3;
        await tester.pumpAndSettle();
        expect(controller.isCritical, isTrue);
        other.release();
        expect(controller.isCritical, isFalse);
        await tester.pumpWidget(const SizedBox());
        active.dispose();
      },
    );
    testWidgets(
      'scroll owns only its protection and releases it when hidden ($effect)',
      (tester) async {
        final active = ValueNotifier(2), visible = ValueNotifier(true);
        final lines = List.generate(
          12,
          (i) => LyricLine(
            timestamp: Duration(seconds: i),
            texts: ['line $i', 'translation'],
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (_, show, _) => TickerMode(
                enabled: show,
                child: ValueListenableBuilder<int>(
                  valueListenable: active,
                  builder: (_, index, _) => SizedBox(
                    height: 600,
                    child: MobileLyricsList(
                      lines: lines,
                      active: index,
                      scrollEffect: effect,
                      karaokeLyricsEnabled: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final controller = InteractionPerformanceController.instance;
        final other = controller.beginVisualAnimation();
        active.value = 3;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        other.release();
        expect(controller.isCritical, isTrue);
        visible.value = false;
        await tester.pump();
        expect(controller.isCritical, isFalse);
        await tester.pumpWidget(const SizedBox());
        active.dispose();
        visible.dispose();
      },
    );
  }
  testWidgets(
    'ordinary glow layout is reused for repeated paints and scroll frames',
    (tester) async {
      final lines = List.generate(
        12,
        (i) => LyricLine(
          timestamp: Duration(seconds: i),
          texts: ['glowing lyrics $i', 'translation'],
        ),
      );
      var active = 2;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, set) {
              update = set;
              return SizedBox(
                height: 600,
                child: MobileLyricsList(
                  lines: lines,
                  active: active,
                  glowEnabled: true,
                  karaokeLyricsEnabled: false,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = debugMobileLyricGlowLayoutCount;
      final paints = tester
          .widgetList<CustomPaint>(
            find.byKey(const ValueKey('mobile_lyric_glow_layer')),
          )
          .toList();
      for (var frame = 0; frame < 30; frame++) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        for (final paint in paints) {
          paint.painter!.paint(canvas, const Size(600, 100));
        }
        recorder.endRecording().dispose();
      }
      expect(debugMobileLyricGlowLayoutCount, before);
      update(() => active = 3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final moving = debugMobileLyricGlowLayoutCount;
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(debugMobileLyricGlowLayoutCount - moving, lessThanOrEqualTo(2));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('cover image State survives live blur structure changes', (
    tester,
  ) async {
    await tester.pumpWidget(background(pixel, 0, 'cover'));
    final state = tester.state(find.byType(Image));
    await tester.pumpWidget(background(pixel, 28, 'lyrics'));
    expect(tester.state(find.byType(Image)), same(state));
    await tester.pumpWidget(background(pixel, 0, 'cover again'));
    expect(tester.state(find.byType(Image)), same(state));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'same artwork bytes reuse the image provider across foreground changes',
    (tester) async {
      await tester.pumpWidget(background(pixel, 28, 'cover'));
      final first = tester.widget<Image>(find.byType(Image)).image;
      await tester.pumpWidget(
        background(Uint8List.fromList(pixel), 28, 'lyrics'),
      );
      final next = tester.widget<Image>(find.byType(Image)).image;
      expect(next, first);
      expect((next as MemoryImage).bytes, same(pixel));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'ordinary lyric neighbors use base color outside the playback focus',
    (tester) async {
      final lines = List.generate(
        9,
        (i) => LyricLine(
          timestamp: Duration(seconds: i),
          texts: ['line $i'],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: SizedBox(
            height: 650,
            child: MobileLyricsList(
              lines: lines,
              active: 4,
              karaokeLyricsEnabled: false,
              highlightActiveLine: true,
              fontSize: 20,
            ),
          ),
        ),
      );
      for (final index in [2, 3, 4, 5, 6]) {
        final row = find.byKey(ValueKey('mobile_lyric_$index'));
        final style = tester
            .widget<AnimatedDefaultTextStyle>(
              find.descendant(
                of: row,
                matching: find.byWidgetPredicate(
                  (w) => w is AnimatedDefaultTextStyle,
                ),
              ),
            )
            .style;
        final distance = (index - 4).abs();
        final strength = distance == 0 ? 1.0 : 0.0;
        expect(
          style.color,
          Color.lerp(
            const Color(0xFF757575).withValues(
              alpha: distance == 0
                  ? 1
                  : distance == 1
                  ? .68
                  : .52,
            ),
            Colors.white,
            strength,
          ),
        );
        final fade = tester.widget<AnimatedOpacity>(
          find.descendant(
            of: row,
            matching: find.byKey(
              const ValueKey('mobile_lyric_distance_opacity'),
            ),
          ),
        );
        expect(
          fade.opacity,
          1,
          reason: 'distance alpha is included in the color mix once',
        );
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('white-on-white ordinary highlight mixes alpha in dark mode', (
    tester,
  ) async {
    final lines = List.generate(
      9,
      (i) => LyricLine(
        timestamp: Duration(seconds: i),
        texts: ['dark line $i'],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: SizedBox(
          height: 650,
          child: MobileLyricsList(
            lines: lines,
            active: 4,
            karaokeLyricsEnabled: false,
            highlightActiveLine: true,
            entryPreparing: true,
            fontSize: 20,
          ),
        ),
      ),
    );
    for (final index in [2, 3, 4, 5, 6]) {
      final row = find.byKey(ValueKey('mobile_lyric_$index'));
      final distance = (index - 4).abs();
      final text = find.descendant(
        of: row,
        matching: find.text('dark line $index'),
      );
      final color = DefaultTextStyle.of(tester.element(text)).style.color!;
      final base = Colors.white.withValues(
        alpha: distance == 0
            ? 1
            : distance == 1
            ? .68
            : .52,
      );
      expect(color, Color.lerp(base, Colors.white, distance == 0 ? 1 : 0));
      final fade = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: row,
          matching: find.byKey(const ValueKey('mobile_lyric_distance_opacity')),
        ),
      );
      expect(fade.opacity, 1);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
