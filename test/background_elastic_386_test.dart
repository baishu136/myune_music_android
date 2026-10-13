import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/services/artwork_palette_cache.dart';
import 'package:myune_music/widgets/playback_background/fluid_frame_uniforms.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';

void main() {
  test(
    '383 extraction keeps real black pigment and does not mute coloured accents',
    () {
      final bright = buildWeightedFluidPalette(const [
        FluidColorSample(Colors.white, .60),
        FluidColorSample(Color(0xff55bbe5), .25),
        FluidColorSample(Colors.black, .10),
        FluidColorSample(Colors.grey, .05),
      ], fallbackSeed: Colors.purple);
      expect(bright.colors.contains(Colors.black), isTrue);
      final muted = buildWeightedFluidPalette(const [
        FluidColorSample(Color(0xff929496), .88),
        FluidColorSample(Color(0xfff02947), .12),
      ], fallbackSeed: Colors.orange);
      expect(
        muted.colors
            .map((c) => HSLColor.fromColor(c).saturation)
            .reduce(math.max),
        greaterThan(.5),
      );
    },
  );
  testWidgets(
    'field shapes breathe smoothly and repeat without a period seam',
    (tester) async {
      await tester.runAsync(() async {
        final shader = (await ui.FragmentProgram.fromAsset(
          'shaders/fluid_background.frag',
        )).fragmentShader();
        final frame = FluidFrameUniforms();
        const palette = FluidPalette(
          Colors.red,
          Colors.green,
          Colors.blue,
          Colors.yellow,
        );
        void sample(double time) => frame.write(
          shader,
          size: const Size(180, 320),
          time: time,
          motion: 1,
          dim: .3,
          source: palette,
          target: palette,
        );
        try {
          sample(0);
          final first = frame.values.toList();
          expect(first, hasLength(45));
          sample(5);
          final later = frame.values.toList();
          expect(later.sublist(29), isNot(first.sublist(29)));
          sample(fluidPhaseCycle);
          for (var i = 6; i < 45; i++) {
            expect(frame.values[i], closeTo(first[i], 2e-6));
          }
          sample(fluidPhaseCycle - .00001);
          final before = frame.values.toList();
          sample(.00001);
          for (var i = 29; i < 45; i++) {
            expect((frame.values[i] - before[i]).abs(), lessThan(.0001));
          }
        } finally {
          shader.dispose();
        }
      });
    },
  );
  testWidgets(
    'equal pigments do not acquire capsule outlines from field coverage',
    (tester) async {
      await tester.runAsync(() async {
        final shader = (await ui.FragmentProgram.fromAsset(
          'shaders/fluid_background.frag',
        )).fragmentShader();
        const palette = FluidPalette(
          Colors.red,
          Colors.red,
          Colors.red,
          Colors.red,
          baseColor: Colors.black,
        );
        final recorder = ui.PictureRecorder();
        try {
          FluidFrameUniforms().write(
            shader,
            size: const Size(100, 200),
            time: 4,
            motion: 1,
            dim: 0,
            source: palette,
            target: palette,
          );
          for (var f = 0; f < 4; f++) {
            shader.setFloat(6 + f * 2, .5);
            shader.setFloat(7 + f * 2, .5);
            for (var c = 0; c < 3; c++) {
              shader.setFloat(14 + f * 3 + c, c == 0 ? 1 : 0);
            }
          }
          Canvas(recorder).drawRect(
            const Rect.fromLTWH(0, 0, 100, 200),
            Paint()..shader = shader,
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(100, 200);
          try {
            final rgba = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            final samples = [
              for (final y in [5, 50, 100, 150, 195]) rgba[(y * 100 + 50) * 4],
            ];
            expect(
              samples.reduce(math.max) - samples.reduce(math.min),
              lessThanOrEqualTo(4),
            );
          } finally {
            image.dispose();
            picture.dispose();
          }
        } finally {
          shader.dispose();
        }
      });
    },
  );
  testWidgets(
    'large elastic row travel stays continuous on redirect and settles without layout frames',
    (tester) async {
      final key = GlobalKey<_HostState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(height: 600, width: 240, child: _Host(key: key)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      key.currentState!.active(1);
      await tester.pump();
      dynamic painter(int index) {
        final dynamic painter = tester
            .widgetList<CustomPaint>(
              find.descendant(
                of: find.byKey(ValueKey('mobile_lyric_$index')),
                matching: find.byType(CustomPaint),
              ),
            )
            .map((w) => w.painter)
            .firstWhere(
              (p) => p.runtimeType.toString() == '_ElasticPhysicalPainter',
            );
        return painter;
      }

      dynamic frame(int index) => painter(index).frame;

      final moving = frame(1);
      final layouts = debugElasticPhysicalLayoutCount;
      var maximum = 0.0;
      for (var i = 0; i < 42; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        maximum = math.max(maximum, moving.offset(0).abs() as double);
      }
      expect(maximum, greaterThan(4));
      debugPrint(
        'Elastic arriving physical row peak: $maximum px at font32; baseline 385: 2.0785474869768943 px',
      );
      final value = moving.offset(0) as double;
      key.currentState!.active(2);
      await tester.pump();
      expect((moving.offset(0) as double) - value, closeTo(0, .01));
      final layoutsAfterRedirect = debugElasticPhysicalLayoutCount;
      final cachedPictures = painter(1).pictures;
      expect(layoutsAfterRedirect, greaterThanOrEqualTo(layouts));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        debugElasticPhysicalLayoutCount - layoutsAfterRedirect,
        lessThanOrEqualTo(3),
      );
      expect(identical(painter(1).pictures, cachedPictures), isTrue);
      expect(moving.offset(0), 0);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Host extends StatefulWidget {
  const _Host({super.key});
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int current = 0;
  final lines = [
    for (var i = 0; i < 8; i++)
      LyricLine(
        timestamp: Duration(seconds: i * 2),
        texts: ['这是第$i行中文歌词，需要实际折行的运动保持自然连贯', '译文保持跟随'],
      ),
  ];
  void active(int index) => setState(() => current = index);
  @override
  Widget build(BuildContext context) => MobileLyricsList(
    lines: lines,
    active: current,
    scrollEffect: LyricScrollEffect.elastic,
    karaokeLyricsEnabled: false,
    fontSize: 32,
    lineBlurEnabled: false,
    isPlaying: true,
    textAlign: TextAlign.left,
  );
}
