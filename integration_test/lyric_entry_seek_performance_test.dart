import 'dart:convert';
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
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';
import 'package:myune_music/widgets/now_playing_cover_hero.dart';
import 'package:myune_music/widgets/now_playing_immersive_layout.dart';

// Actual installed library/audio and production routes. No screen recording
// concurrently: the encoder is an extra GPU workload. Restore all settings.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'cover handoff, first phrase jump and automatic same-song replay',
    (tester) async {
      // app.main installs the production fault logger synchronously. Keep the
      // test binding's handler so an assertion cannot be reported as a pass.
      final testErrorHandler = FlutterError.onError;
      app.main();
      FlutterError.onError = testErrorHandler;
      for (
        var i = 0;
        i < 100 && find.byType(MobileShell).evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await tester.pump();
      }
      final context = tester.element(find.byType(MobileShell));
      final player = context.read<PlaylistContentNotifier>();
      final settings = context.read<SettingsProvider>();
      for (
        var i = 0;
        i < 100 && (!player.allSongsLoaded || player.currentSong == null);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await tester.pump();
      }
      expect(
        player.currentSong,
        isNotNull,
        reason: 'select the comparison song before launch',
      );
      for (var i = 0; i < 80 && player.currentLyrics.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await tester.pump();
      }
      expect(player.currentLyrics, isNotEmpty);
      final startupError = tester.takeException();
      if (startupError != null) {
        // The desktop hotkey plugin has no Android implementation. Startup
        // can report that existing plugin diagnostic in the test binding.
        expect(startupError.toString(), contains('hotkey_manager'));
      }
      final originalPosition = player.currentPosition;
      final playing = player.isPlaying;
      final immersive = settings.playbackImmersiveEnabled;
      final karaoke = settings.enableKaraokeLyrics;
      final karaokeMode = settings.karaokeLyricsMode;
      final effect = settings.lyricScrollEffect;
      final blur = settings.enableLyricBlur;
      final playMode = player.playMode;
      final song = player.currentSong!.normalizedPath;
      final first = player.currentLyrics
          .firstWhere((l) => !l.isInterlude && l.texts.first.trim().isNotEmpty)
          .timestamp;
      final later = player
          .currentLyrics[(player.currentLyrics.length ~/ 3).clamp(
            1,
            player.currentLyrics.length - 1,
          )]
          .timestamp;
      final stages = <Map<String, Object?>>[];
      var success = false;
      Future<void> seek(Duration target) async {
        player.signalLyricSeekIntent();
        await player.mediaPlayer.seek(target);
        player.signalLyricSeek(target);
        await tester.pump(const Duration(milliseconds: 450));
      }

      Future<void> measure(
        String name,
        Future<void> Function() action, {
        Duration tail = const Duration(milliseconds: 1100),
      }) async {
        await tester.pump(const Duration(milliseconds: 300));
        final samples = <FrameTiming>[];
        void record(List<FrameTiming> frames) => samples.addAll(frames);
        SchedulerBinding.instance.addTimingsCallback(record);
        try {
          await action();
          await tester.pump(tail);
        } finally {
          SchedulerBinding.instance.removeTimingsCallback(record);
        }
        final builds =
            samples.map((f) => f.buildDuration.inMicroseconds / 1000).toList()
              ..sort();
        final rasters =
            samples.map((f) => f.rasterDuration.inMicroseconds / 1000).toList()
              ..sort();
        double p95(List<double> values) =>
            values.isEmpty ? 0 : values[((values.length - 1) * .95).round()];
        stages.add({
          'name': name,
          'frames': samples.length,
          'buildP95Ms': p95(builds),
          'rasterP95Ms': p95(rasters),
          'buildMaxMs': builds.isEmpty ? 0 : builds.last,
          'rasterMaxMs': rasters.isEmpty ? 0 : rasters.last,
          'over16_67Ms': samples
              .where(
                (f) =>
                    f.buildDuration.inMicroseconds > 16667 ||
                    f.rasterDuration.inMicroseconds > 16667,
              )
              .length,
          'over8_33Ms': samples
              .where(
                (f) =>
                    f.buildDuration.inMicroseconds > 8333 ||
                    f.rasterDuration.inMicroseconds > 8333,
              )
              .length,
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
        expect(tester.takeException(), isNull);
      }

      MobileLyricsList lyrics() =>
          tester.widget<MobileLyricsList>(find.byType(MobileLyricsList));
      Finder visual() => find.byWidget(
        tester
            .widget<NowPlayingImmersiveLayout>(
              find.byType(NowPlayingImmersiveLayout),
            )
            .visual,
      );
      Future<void> toggleVisual() async {
        // The fullscreen centre can hit a lyric-row browse/seek gesture rather
        // than switching to the cover. Use the production root callback for a
        // deterministic comparison; Release gestures are checked separately.
        tester.widget<GestureDetector>(visual()).onTap!();
      }

      void expectLyricsVisible() => expect(
        tester
            .widget<NowPlayingImmersiveLayout>(
              find.byType(NowPlayingImmersiveLayout),
            )
            .immersive,
        isTrue,
      );
      try {
        await player.pause();
        await settings.setPlaybackImmersiveEnabled(true);
        await settings.setEnableKaraokeLyrics(true);
        await settings.setKaraokeLyricsMode(KaraokeLyricsMode.all);
        settings.setEnableLyricBlur(true);
        await tester.pump(const Duration(seconds: 2));
        await tester.tap(find.byType(NowPlayingCoverHero).first);
        await tester.pump(const Duration(seconds: 2));
        for (final selected in [
          LyricScrollEffect.dynamic,
          LyricScrollEffect.elastic,
        ]) {
          await settings.setLyricScrollEffect(selected);
          await tester.pump(const Duration(milliseconds: 500));
          for (var pass = 0; pass < 2; pass++) {
            await seek(first);
            await measure('${selected.name}-enter-$pass', toggleVisual);
            expectLyricsVisible();
            final count = lyrics().controller!.fullTextLayoutCount;
            stages.last['fullTextLayouts'] = count;
            await toggleVisual();
            await tester.pump(const Duration(milliseconds: 600));
            await seek(later);
            await measure(
              '${selected.name}-hidden-index-enter-$pass',
              toggleVisual,
            );
            expectLyricsVisible();
            stages.last['fullTextLayouts'] =
                lyrics().controller!.fullTextLayoutCount;
            await measure('${selected.name}-jump-first-$pass', () async {
              lyrics().onBrowseTargetSelected!(first);
            });
            expect(
              (player.currentPosition - first).inMilliseconds.abs(),
              lessThan(1800),
            );
            stages.last['fullTextLayouts'] =
                lyrics().controller!.fullTextLayoutCount;
            await player.pause();
            await tester.pump(const Duration(milliseconds: 400));
            await toggleVisual();
            await tester.pump(const Duration(milliseconds: 600));
          }
          await seek(later);
          await toggleVisual();
          await tester.pump(const Duration(seconds: 1));
          while (player.playMode != PlayMode.repeatOne) {
            player.togglePlayMode();
          }
          final beforeLyrics = player.currentLyrics;
          final beforeLayouts = lyrics().controller!.fullTextLayoutCount;
          await seek(player.totalDuration - const Duration(milliseconds: 900));
          await measure('${selected.name}-automatic-replay', () async {
            await player.play();
            // Include native completion, list reset and first sung phrase.
            for (var i = 0; i < 80; i++) {
              await tester.pump(const Duration(milliseconds: 250));
              if (player.currentPosition < later &&
                  player.currentPosition >
                      first + const Duration(milliseconds: 700)) {
                break;
              }
            }
          });
          expect(player.currentSong!.normalizedPath, song);
          expect(player.currentPosition, lessThan(later));
          stages.last['lyricsIdentityRetained'] = identical(
            beforeLyrics,
            player.currentLyrics,
          );
          stages.last['layoutsBefore'] = beforeLayouts;
          stages.last['fullTextLayouts'] =
              lyrics().controller!.fullTextLayoutCount;
          await player.pause();
          await tester.pump(const Duration(milliseconds: 400));
          await toggleVisual();
          await tester.pump(const Duration(milliseconds: 600));
        }
        success = true;
      } finally {
        await player.pause();
        while (player.playMode != playMode) {
          player.togglePlayMode();
        }
        await settings.setPlaybackImmersiveEnabled(immersive);
        await settings.setEnableKaraokeLyrics(karaoke);
        await settings.setKaraokeLyricsMode(karaokeMode);
        await settings.setLyricScrollEffect(effect);
        settings.setEnableLyricBlur(blur);
        await seek(originalPosition);
        if (playing) await player.play();
        final result = {
          'mode': 'profile',
          'song': player.currentSong?.title,
          'firstMs': first.inMilliseconds,
          'laterMs': later.inMilliseconds,
          'lyricLines': player.currentLyrics.length,
          'blur': true,
          'advertisedDisplayHz': View.of(context).display.refreshRate,
          'rssBytes': ProcessInfo.currentRss,
          'success': success,
          'stages': stages,
        };
        binding.reportData = result;
        final directory = await getExternalStorageDirectory();
        if (directory != null) {
          await File(
            '${directory.path}/lyric-entry-seek-profile.json',
          ).writeAsString(jsonEncode(result));
        }
      }
    },
  );
}
