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
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/mobile/mobile_shell.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';
import 'package:myune_music/widgets/now_playing_cover_hero.dart';
import 'package:myune_music/widgets/now_playing_immersive_layout.dart';

// Production library/audio/routes. No recording during FrameTiming sampling.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('Chinese sweep, viewport depth and fluid cover', (tester) async {
    final handler = FlutterError.onError;
    app.main();
    FlutterError.onError = handler;
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
    final startupError = tester.takeException();
    if (startupError != null) {
      expect(startupError.toString(), contains('hotkey_manager'));
    }
    final originalSong = player.currentSong!;
    final originalSource = player.capturePlaybackSource();
    final originalPosition = player.currentPosition;
    final originalPlaying = player.isPlaying;
    final originalImmersive = settings.playbackImmersiveEnabled;
    final originalKaraoke = settings.enableKaraokeLyrics;
    final originalMode = settings.karaokeLyricsMode;
    final originalEffect = settings.lyricScrollEffect;
    final originalBlur = settings.enableLyricBlur;
    final originalArtworkStyle = settings.playbackArtworkBackgroundStyle;
    final originalFollow = settings.followAlbumArtOnPlayback;
    final stages = <Map<String, Object?>>[];
    var success = false;
    String? testedSong;
    int? firstMs;
    String? restoreError;
    Future<void> saveReport() async {
      final result = {
        'mode': 'profile',
        'song': testedSong,
        'firstMs': firstMs,
        'success': success,
        'restoreError': restoreError,
        'advertisedDisplayHz': View.of(context).display.refreshRate,
        'rssBytes': ProcessInfo.currentRss,
        'stages': stages,
      };
      binding.reportData = result;
      final directory = await getExternalStorageDirectory();
      if (directory != null) {
        await File(
          '${directory.path}/chinese-sweep-depth-profile.json',
        ).writeAsString(jsonEncode(result));
      }
    }

    Future<void> seek(Duration target) async {
      debugPrint('SweepDepth: seek ${target.inMilliseconds}ms');
      player.signalLyricSeekIntent();
      await player.mediaPlayer
          .seek(target)
          .timeout(const Duration(seconds: 10));
      player.signalLyricSeek(target);
      await tester.pump(const Duration(milliseconds: 500));
      debugPrint('SweepDepth: seek complete');
    }

    Future<void> measure(
      String name,
      Future<void> Function() action,
      Duration tail,
    ) async {
      debugPrint('SweepDepth: begin $name');
      await tester.pump(const Duration(milliseconds: 500));
      final samples = <FrameTiming>[];
      void record(List<FrameTiming> frames) => samples.addAll(frames);
      SchedulerBinding.instance.addTimingsCallback(record);
      try {
        await action().timeout(const Duration(seconds: 10));
        debugPrint('SweepDepth: action complete $name');
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
      stages.add({
        'name': name,
        'frames': samples.length,
        'buildMaxMs': builds.isEmpty ? 0 : builds.last,
        'rasterMaxMs': rasters.isEmpty ? 0 : rasters.last,
        'buildP95Ms': builds.isEmpty
            ? 0
            : builds[((builds.length - 1) * .95).round()],
        'rasterP95Ms': rasters.isEmpty
            ? 0
            : rasters[((rasters.length - 1) * .95).round()],
        'over16_67Ms': samples
            .where(
              (f) =>
                  f.buildDuration.inMicroseconds > 16667 ||
                  f.rasterDuration.inMicroseconds > 16667,
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
      debugPrint('SweepDepth: end $name (${samples.length} frames)');
      expect(tester.takeException(), isNull);
      // Persist outside the measured interval: a restoration error must not
      // discard completed samples or make an incomplete run look successful.
      await saveReport();
    }

    Future<void> toggle() async {
      final layout = tester.widget<NowPlayingImmersiveLayout>(
        find.byType(NowPlayingImmersiveLayout),
      );
      tester.widget<GestureDetector>(find.byWidget(layout.visual)).onTap!();
    }

    try {
      debugPrint('SweepDepth: select comparison song');
      await player.pause();
      final index = player.allSongs.indexWhere(
        (song) => song.title.contains('杀死那个石家庄人'),
      );
      expect(
        index,
        greaterThanOrEqualTo(0),
        reason: 'the selected device comparison song must exist',
      );
      await player.playSongFromAllSongs(index);
      await player.pause();
      for (var i = 0; i < 80 && player.currentLyrics.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await tester.pump();
      }
      final first = player.currentLyrics.firstWhere(
        (l) => !l.isInterlude && l.texts.first.trim().isNotEmpty,
      );
      expect(
        hasUsableKaraokeTiming(first),
        isFalse,
        reason:
            'this test must exercise synthetic Chinese, not supplied timestamps',
      );
      testedSong = player.currentSong!.title;
      firstMs = first.timestamp.inMilliseconds;
      await settings.setPlaybackImmersiveEnabled(true);
      await settings.setEnableKaraokeLyrics(true);
      await settings.setKaraokeLyricsMode(KaraokeLyricsMode.all);
      settings.setEnableLyricBlur(true);
      await settings.setFollowAlbumArtOnPlayback(true);
      await settings.setPlaybackArtworkBackgroundStyle(
        PlaybackArtworkBackgroundStyle.fluid,
      );
      debugPrint('SweepDepth: open cover');
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byType(NowPlayingCoverHero).first);
      await tester.pump(const Duration(seconds: 2));
      final glowFinder = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'NowPlayingCoverGlow',
      );
      expect(glowFinder, findsNothing);
      await measure('fluid-cover', () async {}, const Duration(seconds: 4));
      for (final effect in LyricScrollEffect.values) {
        debugPrint('SweepDepth: effect ${effect.name}');
        await settings.setLyricScrollEffect(effect);
        await seek(first.timestamp);
        await measure(
          '${effect.name}-entry',
          toggle,
          const Duration(seconds: 2),
        );
        expect(
          tester
              .widget<NowPlayingImmersiveLayout>(
                find.byType(NowPlayingImmersiveLayout),
              )
              .immersive,
          isTrue,
        );
        await measure(
          '${effect.name}-Chinese-sweep-depth',
          player.play,
          const Duration(seconds: 12),
        );
        stages.last['fullTextLayouts'] = tester
            .widget<MobileLyricsList>(find.byType(MobileLyricsList))
            .controller!
            .fullTextLayoutCount;
        await player.pause();
        await toggle();
        await tester.pump(const Duration(milliseconds: 600));
      }
      await settings.setFollowAlbumArtOnPlayback(false);
      await tester.pump(const Duration(milliseconds: 600));
      expect(glowFinder, findsNothing);
      success = true;
    } finally {
      debugPrint('SweepDepth: restore');
      await player.pause();
      await settings.setPlaybackImmersiveEnabled(originalImmersive);
      await settings.setEnableKaraokeLyrics(originalKaraoke);
      await settings.setKaraokeLyricsMode(originalMode);
      await settings.setLyricScrollEffect(originalEffect);
      settings.setEnableLyricBlur(originalBlur);
      await settings.setFollowAlbumArtOnPlayback(originalFollow);
      await settings.setPlaybackArtworkBackgroundStyle(originalArtworkStyle);
      final restore = player.allSongs.indexWhere(
        (song) => song.normalizedPath == originalSong.normalizedPath,
      );
      try {
        if (restore >= 0) await player.playSongFromAllSongs(restore);
        await player.restorePlaybackSource(originalSource);
        await player.pause();
        // Playback loading is deferred; allow the native duration stream to
        // confirm the restored file before seeking into it.
        await tester.pump(const Duration(seconds: 1));
        await seek(originalPosition);
        if (originalPlaying) await player.play();
      } catch (error) {
        restoreError = error.toString();
        debugPrint('SweepDepth: restore failed: $error');
      }
      await saveReport();
    }
  });
}
