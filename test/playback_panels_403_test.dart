import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/services/continuous_skip_session.dart';
import 'package:myune_music/services/playback_navigation.dart';
import 'package:myune_music/services/playback_picker_memory.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/widgets/home_header_page_transition.dart';
import 'package:myune_music/widgets/playback_control_sheet_surface.dart';
import 'package:myune_music/widgets/playback_mode_glyph.dart';
import 'package:myune_music/widgets/transport_skip_button.dart';
import 'package:myune_music/widgets/playback_background/playback_background.dart';
import 'package:myune_music/widgets/playback_background/fluid_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('normal loads do not suspend, a hold covers all outstanding loads', () {
    final session = ContinuousSkipSession();
    final events = <bool>[];
    session.addListener(() => events.add(session.value));
    final oldLoad = session.trackLoad();
    expect(session.value, false);
    final release = session.hold();
    final load = session.trackLoad();
    final secondHold = session.hold();
    release();
    release();
    secondHold();
    load();
    expect(session.value, true);
    oldLoad();
    expect(events, [true, false]);
    session.dispose();
    oldLoad();
    session.hold()();
  });

  for (final cancel in [true, false]) {
    testWidgets('hold releases once and waits for final load: cancel=$cancel', (
      tester,
    ) async {
      final session = ContinuousSkipSession();
      final pending = Completer<void>();
      var starts = 0, releases = 0, calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransportSkipButton(
              tooltip: 'skip',
              icon: Icons.skip_next,
              onHoldStart: () {
                starts++;
                final release = session.hold();
                return () {
                  releases++;
                  release();
                };
              },
              onSkip: () async {
                calls++;
                final done = session.trackLoad();
                try {
                  await pending.future;
                } finally {
                  done();
                }
              },
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(IconButton)),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 3600));
      expect(calls, 1);
      expect(starts, 1);
      expect(session.value, true);
      if (cancel) {
        await gesture.cancel();
      } else {
        await gesture.up();
      }
      await tester.pump();
      expect(releases, 1);
      expect(session.value, true);
      pending.complete();
      await tester.pump();
      expect(session.value, false);
      await tester.pumpWidget(const SizedBox());
      expect(releases, 1);
      session.dispose();
    });
  }

  test(
    'picker memory survives provider restart and ignores malformed fields',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      await settings.initializationFuture;
      await settings.rememberPlaybackPicker(
        const PlaybackPickerMemory(
          page: PlaybackPickerPage.playlists,
          playlistId: 'evening',
          query: '月',
          offset: 176,
        ),
      );
      settings.dispose();
      final restored = SettingsProvider();
      await restored.initializationFuture;
      expect(restored.playbackPickerMemory.toJson(), {
        'page': 'playlists',
        'playlistId': 'evening',
        'query': '月',
        'offset': 176.0,
      });
      restored.dispose();
      final bad = PlaybackPickerMemory.fromJson({
        'page': 'future',
        'offset': double.nan,
        'query': 5,
        'playlistId': false,
      });
      expect(bad.toJson(), const PlaybackPickerMemory().toJson());
      SharedPreferences.setMockInitialValues({
        'playback_picker_memory_403': '{bad',
      });
      final corrupt = SettingsProvider();
      await corrupt.initializationFuture;
      expect(corrupt.playbackPickerMemory.page, PlaybackPickerPage.library);
      corrupt.dispose();
    },
  );

  testWidgets(
    'header keeps slide direction and adds continuous enter/exit fades',
    (tester) async {
      final progress = ValueNotifier<double>(0);
      for (final incoming in [true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            home: HomeHeaderPageTransition(
              animation: AlwaysStoppedAnimation(progress.value),
              incoming: incoming,
              child: const Text('title'),
            ),
          ),
        );
        var previous = -1.0;
        for (final value in [0.0, .1, .35, .7, 1.0]) {
          await tester.pumpWidget(
            MaterialApp(
              home: HomeHeaderPageTransition(
                animation: AlwaysStoppedAnimation(value),
                incoming: incoming,
                child: const Text('title'),
              ),
            ),
          );
          final opacity = tester
              .widget<FadeTransition>(find.byType(FadeTransition).last)
              .opacity
              .value;
          final offset = tester
              .widget<SlideTransition>(find.byType(SlideTransition).last)
              .position
              .value;
          expect(opacity, greaterThanOrEqualTo(previous));
          expect(
            offset.dx,
            closeTo((incoming ? 1.1 : -1.1) * (1 - value), 1e-9),
          );
          if (value == 0 || value == 1) expect(opacity, value);
          previous = opacity;
        }
      }
      progress.dispose();
    },
  );

  testWidgets(
    'shared sheets retain identical opacity, borders and reusable blur',
    (tester) async {
      for (final fluid in [true, false]) {
        Object? previousFilter;
        for (final brightness in Brightness.values) {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                body: PlaybackControlSheetSurface(
                  fluid: fluid,
                  child: const SizedBox(height: 200),
                ),
              ),
            ),
          );
          final root = find.byType(PlaybackControlSheetSurface);
          final box =
              tester
                      .widget<DecoratedBox>(
                        find
                            .descendant(
                              of: root,
                              matching: find.byType(DecoratedBox),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration;
          expect(box.color!.a, closeTo(fluid ? .28 : .10, 1e-9));
          expect((box.border! as Border).top.color.a, closeTo(.72, 1e-9));
          expect(box.borderRadius, PlaybackControlSheetSurface.radius);
          final filter = tester
              .widget<BackdropFilter>(
                find.descendant(
                  of: root,
                  matching: find.byType(BackdropFilter),
                ),
              )
              .filter;
          if (previousFilter != null) expect(filter, same(previousFilter));
          previousFilter = filter;
        }
      }
    },
  );

  testWidgets(
    'continuous switching retains background instance, freezes tickers and restores latest',
    (tester) async {
      Widget host(String id, bool suspended) => MaterialApp(
        home: PlaybackBackground(
          style: PlaybackArtworkBackgroundStyle.fluid,
          artworkIdentity: id,
          artworkCacheGeneration: 0,
          routeTransitionActive: true,
          fluidQuality: FluidBackgroundQuality.automatic,
          fallbackSeed: Colors.teal,
          path: null,
          customImageEnabled: false,
          customImageDim: 0,
          customImageBlur: 0,
          coverBytes: null,
          coverEnabled: true,
          coverDim: .3,
          coverBlur: 20,
          usePlaybackTheme: true,
          suspended: suspended,
          child: Text(id),
        ),
      );
      await tester.pumpWidget(host('first', false));
      final original = tester.widget<FluidPlaybackBackground>(
        find.byType(FluidPlaybackBackground),
      );
      final state = tester.state(find.byType(FluidPlaybackBackground));
      for (final id in ['second', 'third', 'final']) {
        await tester.pumpWidget(host(id, true));
        expect(
          tester.widget<FluidPlaybackBackground>(
            find.byType(FluidPlaybackBackground),
          ),
          same(original),
        );
        expect(
          TickerMode.valuesOf(
            tester.element(find.byType(FluidPlaybackBackground)),
          ).enabled,
          false,
        );
        expect(find.text(id), findsOneWidget);
      }
      await tester.pumpWidget(host('final', false));
      expect(
        tester
            .widget<FluidPlaybackBackground>(
              find.byType(FluidPlaybackBackground),
            )
            .artworkIdentity,
        'final',
      );
      expect(tester.state(find.byType(FluidPlaybackBackground)), same(state));
      expect(
        TickerMode.valuesOf(
          tester.element(find.byType(FluidPlaybackBackground)),
        ).enabled,
        true,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'combined icon fits control sizes and inherits foreground color',
    (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: const Color(0xff182127),
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: IconTheme(
                  data: const IconThemeData(color: Colors.white),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final size in [24.0, 28.0, 36.0])
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: PlaybackModeGlyph(
                            mode: PlayMode.repeatShuffle,
                            size: size,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final glyphs = find.byKey(const ValueKey('repeat-shuffle-glyph'));
      expect(glyphs, findsNWidgets(3));
      for (var i = 0; i < 3; i++) {
        expect(tester.getSize(glyphs.at(i)).width, [24.0, 28.0, 36.0][i]);
      }
      const directory = String.fromEnvironment('MYUNE_403_PREVIEW_DIR');
      if (directory.isNotEmpty) {
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 3);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(directory).create(recursive: true);
          await File(
            '$directory/repeat-shuffle.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(tester.takeException(), isNull);
    },
  );
}
