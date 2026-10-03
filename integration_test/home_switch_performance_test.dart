import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:myune_music/main.dart' as app;
import 'package:myune_music/mobile/mobile_shell.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';
import 'package:myune_music/widgets/home_tab_viewport.dart';

// Same installed library, theme and production navigation for both versions.
// No screen recording during FrameTiming collection. Does not change settings,
// songs, playlists or progress; temporarily pauses audio and restores its intent.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('production home navigation: cold, warm, drag and reverse', (
    tester,
  ) async {
    final errorHandler = FlutterError.onError;
    app.main();
    FlutterError.onError = errorHandler;
    for (
      var i = 0;
      i < 120 && find.byType(MobileShell).evaluate().isEmpty;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await tester.pump();
    }
    final context = tester.element(find.byType(MobileShell));
    final player = context.read<PlaylistContentNotifier>();
    for (var i = 0; i < 120 && !player.allSongsLoaded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await tester.pump();
    }
    expect(player.allSongs, isNotEmpty);
    final startupError = tester.takeException();
    if (startupError != null) {
      expect(startupError.toString(), contains('hotkey_manager'));
    }
    final wasPlaying = player.isPlaying;
    final stages = <Map<String, Object?>>[];
    var complete = false;

    Future<void> save() async {
      final report = {
        'mode': 'profile',
        'baseline': const bool.fromEnvironment('MYUNE_HOME_BASELINE'),
        'complete': complete,
        'songs': player.allSongs.length,
        'advertisedDisplayHz': View.of(context).display.refreshRate,
        'rssBytes': ProcessInfo.currentRss,
        'stages': stages,
      };
      binding.reportData = report;
      final directory = await getExternalStorageDirectory();
      if (directory != null) {
        await File(
          '${directory.path}/home-switch-profile.json',
        ).writeAsString(jsonEncode(report));
      }
    }

    Future<void> tapTab(int index) => tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(['音乐库', '歌单', '歌手', '专辑', '设置'][index]),
      ),
    );

    Future<void> measure(String name, Future<void> Function() action) async {
      await tester.pump(const Duration(milliseconds: 350));
      final samples = <FrameTiming>[];
      void record(List<FrameTiming> frames) => samples.addAll(frames);
      SchedulerBinding.instance.addTimingsCallback(record);
      final startUs = developer.Timeline.now;
      try {
        await action();
        await tester.pump(const Duration(milliseconds: 1100));
      } finally {
        SchedulerBinding.instance.removeTimingsCallback(record);
      }
      // Page slide is 320 ms, header 380 ms. Include 40 ms scheduling slack.
      // ALSO retain the entire window: deferred cold work is not hidden.
      final motion = samples.where((f) {
        final vsync = f.timestampInMicroseconds(ui.FramePhase.vsyncStart);
        return vsync >= startUs && vsync < startUs + 420000;
      }).toList();
      Map<String, Object> summarize(List<FrameTiming> frames) {
        final builds =
            frames.map((f) => f.buildDuration.inMicroseconds / 1000).toList()
              ..sort();
        final rasters =
            frames.map((f) => f.rasterDuration.inMicroseconds / 1000).toList()
              ..sort();
        return {
          'frames': frames.length,
          'buildMaxMs': builds.isEmpty ? 0 : builds.last,
          'rasterMaxMs': rasters.isEmpty ? 0 : rasters.last,
          'buildP95Ms': builds.isEmpty
              ? 0
              : builds[((builds.length - 1) * .95).round()],
          'rasterP95Ms': rasters.isEmpty
              ? 0
              : rasters[((rasters.length - 1) * .95).round()],
          'over16_67Ms': frames
              .where(
                (f) =>
                    f.buildDuration.inMicroseconds > 16667 ||
                    f.rasterDuration.inMicroseconds > 16667,
              )
              .length,
        };
      }

      stages.add({
        'name': name,
        'actionStartUs': startUs,
        'whole': summarize(samples),
        'motion': summarize(motion),
        'raw': samples
            .map(
              (f) => [
                f.timestampInMicroseconds(ui.FramePhase.vsyncStart),
                f.buildDuration.inMicroseconds,
                f.rasterDuration.inMicroseconds,
              ],
            )
            .toList(),
      });
      expect(
        motion,
        isNotEmpty,
        reason: 'verify the clocks used to mark animation frames',
      );
      expect(tester.takeException(), isNull);
      debugPrint('HomeSwitch: $name ${stages.last['motion']}');
      await save();
    }

    try {
      await player.pause();
      await tester.pump(const Duration(seconds: 3));
      for (var pass = 0; pass < 3; pass++) {
        for (final target in [1, 0, 2, 3, 4, 0]) {
          await measure('pass-$pass-to-$target', () => tapTab(target));
          expect(
            tester
                .widget<NavigationBar>(find.byType(NavigationBar))
                .selectedIndex,
            target,
          );
          final controller = tester
              .widget<HomeTabViewport>(find.byType(HomeTabViewport))
              .controller;
          expect(controller.page, closeTo(target.toDouble(), .01));
        }
      }
      final width = tester.getSize(find.byType(HomeTabViewport)).width;
      await measure(
        'gesture-library-playlists',
        () =>
            tester.drag(find.byType(HomeTabViewport), Offset(-width * .72, 0)),
      );
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      await measure('rapid-4-0', () async {
        await tapTab(4);
        await tester.pump(const Duration(milliseconds: 80));
        await tapTab(0);
      });
      final controller = tester
          .widget<HomeTabViewport>(find.byType(HomeTabViewport))
          .controller;
      expect(controller.page, closeTo(0, .01));
      complete = true;
    } finally {
      await tapTab(0);
      if (wasPlaying) await player.play();
      await save();
    }
  });
}
