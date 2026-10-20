import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/page/setting/tabs/playback_page_tab.dart';
import 'package:myune_music/services/artwork_palette_cache.dart';
import 'package:myune_music/widgets/playback_background/fluid_colour_motion.dart';
import 'package:myune_music/widgets/playback_background/fluid_frame_uniforms.dart';

void main() {
  testWidgets('bright encoded artwork suppresses black printing as a pigment', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(Colors.white, BlendMode.src);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 64, 16),
        Paint()..color = const Color(0xff55bbe5),
      );
      canvas.drawRect(
        const Rect.fromLTWH(0, 16, 64, 6),
        Paint()..color = Colors.black,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(64, 64);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final cache = ArtworkPaletteCache();
      final palette = await cache.resolve(
        key: 'paper-profile-385',
        bytes: data!.buffer.asUint8List(),
        fallbackSeed: Colors.purple,
      );
      expect(palette.colors.contains(Colors.black), isFalse);
      expect(HSLColor.fromColor(palette.baseColor).lightness, greaterThan(.20));
      image.dispose();
      picture.dispose();
      cache.clear();
    });
  });

  testWidgets(
    'one blob has round physical influence on tall and wide screens',
    (tester) async {
      await tester.runAsync(() async {
        final program = await ui.FragmentProgram.fromAsset(
          'shaders/fluid_background.frag',
        );
        final shader = program.fragmentShader();
        try {
          for (final size in [const Size(160, 320), const Size(320, 160)]) {
            final packed = FluidFrameUniforms();
            packed.write(
              shader,
              size: size,
              time: 0,
              motion: 0,
              dim: 0,
              source: const FluidPalette(
                Colors.black,
                Colors.white,
                Colors.black,
                Colors.black,
              ),
              target: const FluidPalette(
                Colors.black,
                Colors.white,
                Colors.black,
                Colors.black,
              ),
            );
            for (var f = 0; f < 4; f++) {
              shader.setFloat(6 + f * 2, .5);
              shader.setFloat(7 + f * 2, .5);
              // Broader black fields provide a spatial reference; identical
              // coincident fields cancel in the restored 391 convex mixing.
              if (f > 0) {
                shader.setFloat(29 + f * 4, 1 / .8);
                shader.setFloat(29 + f * 4 + 1, 0);
                shader.setFloat(29 + f * 4 + 2, 0);
                shader.setFloat(29 + f * 4 + 3, 1 / .8);
              }
              for (var c = 0; c < 3; c++) {
                shader.setFloat(14 + f * 3 + c, f == 0 ? 1 : 0);
              }
            }
            final recorder = ui.PictureRecorder();
            Canvas(
              recorder,
            ).drawRect(Offset.zero & size, Paint()..shader = shader);
            final picture = recorder.endRecording();
            final image = await picture.toImage(
              size.width.toInt(),
              size.height.toInt(),
            );
            final pixels = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            int red(int dx, int dy) =>
                pixels[((size.height ~/ 2 + dy) * image.width +
                        size.width ~/ 2 +
                        dx) *
                    4];
            expect((red(40, 0) - red(0, 40)).abs(), lessThanOrEqualTo(2));
            final outside = size.width > size.height
                ? red(size.width ~/ 2 - 3, 0)
                : red(0, size.height ~/ 2 - 3);
            expect(outside, lessThan(red(0, 0)));
            expect(red(0, 0), greaterThan(45));
            image.dispose();
            picture.dispose();
          }
        } finally {
          shader.dispose();
        }
      });
    },
  );
  test(
    'coordinated colour rates are smooth and other blobs slow when one leads',
    () {
      var low = double.infinity, high = 0.0;
      for (var i = 0; i <= 1200; i++) {
        final orbit = i / 1200 * math.pi * 2;
        final rates = [for (var f = 0; f < 4; f++) fluidColourRate(orbit, f)];
        expect(rates.reduce((a, b) => a + b), closeTo(3.2, 1e-10));
        for (var f = 0; f < 4; f++) {
          low = math.min(low, rates[f]);
          high = math.max(high, rates[f]);
          final numeric =
              (fluidColourPhase(orbit + .00001, f) -
                  fluidColourPhase(orbit - .00001, f)) /
              .00002;
          expect(numeric, closeTo(rates[f], 1e-7));
          if (rates[f] > 1.6) {
            expect(
              rates.where((r) => r != rates[f]).every((r) => r < .816),
              isTrue,
            );
          }
          expect(
            fluidColourRate(orbit + 10 * math.pi, f),
            closeTo(rates[f], 1e-10),
          );
        }
      }
      expect(low, greaterThan(.12));
      expect(high, greaterThan(.8));
    },
  );

  test(
    'eight shared cover colours stay in gamut and preserve neutral artwork',
    () {
      final variants = Float64List(96);
      final palette = buildFluidPalette(const [
        Colors.red,
        Colors.blue,
        Colors.green,
        Colors.orange,
      ], fallbackSeed: Colors.pink);
      cacheFluidColourVariants(variants, palette);
      final colours = <String>{};
      for (var i = 0; i < 32; i++) {
        final rgb = variants.sublist(i * 3, i * 3 + 3);
        expect(rgb.every((c) => c >= 0 && c <= 1), isTrue);
        colours.add(rgb.map((c) => c.toStringAsFixed(5)).join(','));
      }
      expect(colours.length, inInclusiveRange(6, 8));
      cacheFluidColourVariants(
        variants,
        const FluidPalette(Colors.grey, Colors.grey, Colors.grey, Colors.grey),
      );
      for (var i = 0; i < 32; i++) {
        expect(variants[i * 3], variants[i * 3 + 1]);
        expect(variants[i * 3 + 1], variants[i * 3 + 2]);
      }
    },
  );

  test(
    'cover size restores only the three supported choices and persists',
    () async {
      for (final initial in [null, 1.0, .9, .8, .6, .75, double.nan]) {
        SharedPreferences.setMockInitialValues({
          if (initial != null) 'playbackCoverScale': initial,
        });
        final settings = SettingsProvider();
        await settings.initializationFuture;
        expect(
          settings.playbackCoverScale,
          initial == .9 || initial == .8
              ? initial
              : initial == .6
              ? .8
              : 1,
        );
        await settings.setPlaybackCoverScale(.8);
        expect(
          (await SharedPreferences.getInstance()).getDouble(
            'playbackCoverScale',
          ),
          .8,
        );
        await settings.setPlaybackCoverScale(.75);
        expect(settings.playbackCoverScale, .8);
        settings.dispose();
      }
    },
  );

  testWidgets(
    'playback cover choice has three labels, no note and updates immediately',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      await settings.initializationFuture;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: settings,
          child: const MaterialApp(
            home: Scaffold(body: PlaybackCoverSizeSetting()),
          ),
        ),
      );
      expect(find.byType(Text), findsNWidgets(4));
      expect(find.text('播放页封面大小'), findsOneWidget);
      await tester.tap(find.text('90%'));
      await tester.pump();
      expect(settings.playbackCoverScale, .9);
      expect(
        tester
            .widget<SegmentedButton<double>>(
              find.byKey(const ValueKey('playback-cover-size')),
            )
            .selected,
        {.9},
      );
      await tester.tap(find.text('100%'));
      await tester.pump();
      expect(settings.playbackCoverScale, 1);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );
  test('bright coloured artwork preserves colour without black pigments', () {
    final palette = buildWeightedFluidPalette(const [
      FluidColorSample(Colors.white, .60),
      FluidColorSample(Color(0xff55bbe5), .25),
      FluidColorSample(Colors.black, .10),
      FluidColorSample(Color(0xff8e8e8e), .05),
    ], fallbackSeed: Colors.purple);
    expect(palette.colors, isNot(contains(Colors.black)));
    expect(
      palette.colors.any((c) => HSLColor.fromColor(c).saturation > .5),
      isTrue,
    );
  });

  test('a muted cover restores 383 colourful accents', () {
    final palette = buildWeightedFluidPalette(const [
      FluidColorSample(Color(0xff929496), .88),
      FluidColorSample(Color(0xfff02947), .12),
    ], fallbackSeed: Colors.orange);
    expect(
      palette.colors.any((c) => HSLColor.fromColor(c).saturation > .5),
      isTrue,
    );
  });

  test('genuinely dark monochrome artwork remains neutral and dark', () {
    final palette = buildWeightedFluidPalette(const [
      FluidColorSample(Colors.black, 1),
    ], fallbackSeed: Colors.pink);
    expect(palette.colors.every((c) => c.computeLuminance() == 0), isTrue);
    expect(palette.baseColor, Colors.black);
  });
}
