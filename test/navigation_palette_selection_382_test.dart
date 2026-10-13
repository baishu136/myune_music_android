import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/services/artwork_palette_cache.dart';
import 'package:myune_music/services/library_song_visibility.dart';
import 'package:myune_music/widgets/android_system_bars.dart';
import 'package:myune_music/widgets/home_glass_surface.dart';
import 'package:myune_music/widgets/fullscreen_swipe_song_hint.dart';
import 'package:myune_music/widgets/song_selection_actions.dart';
import 'package:myune_music/widgets/playback_background/fluid_frame_uniforms.dart';

void main() {
  testWidgets('hint handoff during fade-in retains its current translation', (
    tester,
  ) async {
    final signal = FullscreenSwipeSongHintController();
    final song = Song(filePath: '/a', title: 'Song', artist: 'Singer');
    await tester.pumpWidget(
      MaterialApp(
        home: FullscreenSwipeSongHint(
          enabled: true,
          currentSongIdentity: song.normalizedPath,
          songChanges: signal,
        ),
      ),
    );
    signal.show(song);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    double x() => tester
        .widget<Transform>(
          find.byKey(const ValueKey('fullscreen-swipe-song-hint-slide')),
        )
        .transform
        .storage[12];
    final before = x();
    signal.beginSwitch(next: true);
    await tester.pump();
    expect(x(), closeTo(before, .001));
    await tester.pump(const Duration(milliseconds: 60));
    expect(x(), lessThan(before));
    await tester.pumpWidget(const SizedBox());
    signal.dispose();
  });
  test(
    'mixed vivid artwork retains a dark pigment without pale neutral blobs',
    () {
      const dark = Color(0xff12243b);
      final palette = buildWeightedFluidPalette([
        const FluidColorSample(dark, .34),
        const FluidColorSample(Color(0xffbbbbbc), .22),
        const FluidColorSample(Color(0xffed3883), .24),
        const FluidColorSample(Color(0xff24b4a8), .20),
      ], fallbackSeed: Colors.yellow);
      final hsl = palette.colors.map(HSLColor.fromColor).toList();
      expect(
        hsl.any((c) => c.lightness <= HSLColor.fromColor(dark).lightness + .01),
        isTrue,
      );
      expect(
        hsl.where((c) => c.saturation < .12 && c.lightness > .45),
        isEmpty,
      );
      expect(hsl.every((c) => c.lightness <= .59), isTrue);
      expect(HSLColor.fromColor(palette.baseColor).lightness, lessThan(.08));
    },
  );

  test('pastel colours remain related to artwork and black stays black', () {
    const pastel = Color(0xffb2b5c0);
    final palette = buildFluidPalette([pastel], fallbackSeed: Colors.red);
    expect(
      palette.colors.every((c) => HSLColor.fromColor(c).saturation < .20),
      isTrue,
    );
    final black = buildFluidPalette([Colors.black], fallbackSeed: Colors.red);
    expect(black.colors.every((c) => c.computeLuminance() == 0), isTrue);
  });

  test('restoring chosen paths and identities keeps other hidden rows', () {
    final visibility = LibrarySongVisibility();
    visibility.hide(
      ['/Music/A.flac', '/Music/copy.flac', '/Music/B.flac'],
      ['a', 'b'],
    );
    expect(
      visibility.restore(['/Music/A.flac', '/Music/copy.flac'], ['a']),
      isTrue,
    );
    expect(visibility.isHidden('/Music/A.flac', 'a'), isFalse);
    expect(visibility.isHidden('/Music/copy.flac', 'a'), isFalse);
    expect(visibility.isHidden('/Music/B.flac', 'b'), isTrue);
    expect(visibility.restore(['/Music/A.flac'], ['a']), isFalse);
  });

  test('each orbit varies speed gradually with continuous cycle velocity', () {
    const h = .0001;
    double velocity(double t, int field) =>
        (fluidOrbitAngle(t + h, field, 1) - fluidOrbitAngle(t - h, field, 1)) /
        (2 * h);
    for (var field = 0; field < 4; field++) {
      var minimum = double.infinity, maximum = 0.0;
      var previous = velocity(0, field);
      for (var step = 1; step <= 1200; step++) {
        final t = 2 * math.pi * step / 1200;
        final current = velocity(t, field);
        minimum = math.min(minimum, current);
        maximum = math.max(maximum, current);
        // No speed step; at .15 radians/s this spans ~35ms per sample.
        expect((current - previous).abs(), lessThan(.003));
        previous = current;
      }
      expect(minimum, greaterThan(.51));
      expect(maximum, lessThan(1.49));
      expect(maximum - minimum, greaterThan(.45));
      expect(
        velocity(0, field),
        closeTo(velocity(2 * math.pi, field), .000001),
      );
      expect(
        fluidOrbitAngle(2 * math.pi, field, 1) - fluidOrbitAngle(0, field, 1),
        closeTo(2 * math.pi, .000001),
      );
    }
    expect(velocity(1, 0), isNot(closeTo(velocity(1, 1), .01)));
  });

  testWidgets(
    'selection toolbar has only the four actions and dispatches each',
    (tester) async {
      final events = <String>[];
      Future<void> host(bool restore) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                SongSelectionActions(
                  onSelectAll: () => events.add('all'),
                  onDeselectAll: () => events.add('none'),
                  onExit: () => events.add('exit'),
                  onVisibility: () => events.add(restore ? 'restore' : 'hide'),
                  restoreHidden: restore,
                ),
              ],
            ),
          ),
        ),
      );
      await host(false);
      expect(find.byType(IconButton), findsNWidgets(4));
      for (final tooltip in ['全选', '取消全选', '取消多选', '隐藏歌曲']) {
        await tester.tap(find.byTooltip(tooltip));
      }
      expect(events, ['all', 'none', 'exit', 'hide']);
      await host(true);
      expect(find.byTooltip('隐藏歌曲'), findsNothing);
      await tester.tap(find.byTooltip('取消隐藏'));
      expect(events.last, 'restore');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'nav annotation removes scrim while footer paints the safe inset',
    (tester) async {
      final key = GlobalKey();
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.only(bottom: 24),
              viewPadding: EdgeInsets.only(bottom: 24),
            ),
            child: AndroidSystemBars(
              child: RepaintBoundary(
                key: key,
                child: const ColoredBox(
                  color: Color(0xff005577),
                  child: Scaffold(
                    backgroundColor: Colors.transparent,
                    bottomNavigationBar: HomeNavigationSurface(
                      child: SizedBox(
                        height: 72,
                        child: Center(child: Text('footer')),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final styles = calls.where(
        (call) => call.method == 'SystemChrome.setSystemUIOverlayStyle',
      );
      expect(styles, isNotEmpty);
      final style = styles.last.arguments as Map;
      expect(style['systemNavigationBarContrastEnforced'], false);
      expect(style['systemNavigationBarColor'], 0);
      expect(style['systemNavigationBarDividerColor'], 0);
      expect(style['systemNavigationBarIconBrightness'], 'Brightness.light');
      expect(tester.getBottomLeft(find.text('footer')).dy, lessThan(576));
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        Color pixel(int y) {
          final i = (y * image.width + 10) * 4;
          return Color.fromARGB(
            bytes[i + 3],
            bytes[i],
            bytes[i + 1],
            bytes[i + 2],
          );
        }

        expect(pixel(image.height - 2), pixel(image.height - 25));
        expect(pixel(image.height - 2).computeLuminance(), lessThan(.3));
        image.dispose();
      });
    },
  );

  testWidgets('24px song hint fades in gradually after a completed switch', (
    tester,
  ) async {
    final signal = FullscreenSwipeSongHintController();
    final song = Song(filePath: '/a', title: 'Song', artist: 'Singer');
    await tester.pumpWidget(
      MaterialApp(
        home: FullscreenSwipeSongHint(
          enabled: true,
          currentSongIdentity: song.normalizedPath,
          songChanges: signal,
        ),
      ),
    );
    signal.show(song);
    await tester.pump();
    double opacity() => tester
        .widget<FadeTransition>(
          find.byKey(const ValueKey('fullscreen-swipe-song-hint-fade')),
        )
        .opacity
        .value;
    expect(opacity(), 0);
    await tester.pump(const Duration(milliseconds: 55));
    expect(opacity(), inExclusiveRange(0, .2));
    await tester.pump(const Duration(milliseconds: 55));
    expect(opacity(), inExclusiveRange(.45, .60));
    await tester.pump(const Duration(milliseconds: 110));
    expect(opacity(), 1);
    expect(tester.widget<Text>(find.text('Song')).style!.fontSize, 24);
    await tester.pumpWidget(const SizedBox());
    signal.dispose();
  });
}
