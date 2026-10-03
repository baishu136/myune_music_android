import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:myune_music/main.dart' as app;
import 'package:myune_music/mobile/mobile_shell.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/page/setting/tabs/custom_theme_settings_section.dart';
import 'package:myune_music/page/setting/tabs/playback_page_tab.dart';
import 'package:myune_music/widgets/now_playing_cover_hero.dart';
import 'package:myune_music/widgets/now_playing_immersive_layout.dart';
import 'package:myune_music/widgets/playback_jump_feedback.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';

// Uses the installed library, never clears it or imports synthetic songs. Do not
// run concurrently with screen recording. Settings changed here are restored.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('real home, playback, immersive and detail route transitions', (
    tester,
  ) async {
    app.main();
    for (
      var i = 0;
      i < 60 && find.byType(MobileShell).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byType(MobileShell), findsOneWidget);
    final context = tester.element(find.byType(MobileShell));
    final player = context.read<PlaylistContentNotifier>();
    final settings = context.read<SettingsProvider>();
    for (var i = 0; i < 60 && !player.allSongsLoaded; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(
      player.allSongs,
      isNotEmpty,
      reason: 'import a library before testing',
    );
    final immersive = settings.playbackImmersiveEnabled;
    final karaoke = settings.enableKaraokeLyrics;
    final mode = settings.karaokeLyricsMode;
    final wasPlaying = player.isPlaying;
    if (player.currentSong == null) await player.playSongFromAllSongs(0);
    await player.pause();
    await settings.setPlaybackImmersiveEnabled(true);
    await settings.setEnableKaraokeLyrics(true);
    await settings.setKaraokeLyricsMode(KaraokeLyricsMode.all);
    await tester.pump(const Duration(seconds: 3));
    final stages = <Map<String, Object?>>[];
    var featuresVerified = false;
    Future<void> measure(String name, Future<void> Function() action) async {
      // Flush batched FrameTiming reports from the previous phase first.
      await tester.pump(const Duration(milliseconds: 300));
      final samples = <FrameTiming>[];
      void record(List<FrameTiming> frames) => samples.addAll(frames);
      SchedulerBinding.instance.addTimingsCallback(record);
      await action();
      await tester.pump(const Duration(milliseconds: 1100));
      SchedulerBinding.instance.removeTimingsCallback(record);
      final build =
          samples.map((f) => f.buildDuration.inMicroseconds / 1000).toList()
            ..sort();
      final raster =
          samples.map((f) => f.rasterDuration.inMicroseconds / 1000).toList()
            ..sort();
      double percentile(List<double> values) =>
          values.isEmpty ? 0 : values[((values.length - 1) * .95).round()];
      stages.add({
        'name': name,
        'frames': samples.length,
        'buildP95Ms': percentile(build),
        'rasterP95Ms': percentile(raster),
        'buildMaxMs': build.isEmpty ? 0 : build.last,
        'rasterMaxMs': raster.isEmpty ? 0 : raster.last,
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

    try {
      for (var pass = 0; pass < 2; pass++) {
        await measure(
          'home-library-playlists-$pass',
          () => tester.tap(find.text('歌单').last),
        );
        await measure(
          'home-playlists-library-$pass',
          () => tester.tap(find.text('音乐库').last),
        );
        // The mini-player's hero is also its tap surface (no coordinate guesses).
        await measure(
          'open-playback-$pass',
          () => tester.tap(find.byType(NowPlayingCoverHero).first),
        );
        expect(find.byType(NowPlayingImmersiveLayout), findsOneWidget);
        await measure(
          'enter-fullscreen-lyrics-$pass',
          () => tester.tap(find.byType(NowPlayingCoverHero).last),
        );
        final lyricController = tester
            .widget<MobileLyricsList>(find.byType(MobileLyricsList))
            .controller!;
        expect(
          lyricController.fullTextLayoutCount,
          1,
          reason:
              'fullscreen height animation must not repeatedly remeasure the song',
        );
        stages.last['fullTextLayouts'] = lyricController.fullTextLayoutCount;
        // The retained single visual's centre is outside the long-press edge zones.
        final visual = tester
            .widget<NowPlayingImmersiveLayout>(
              find.byType(NowPlayingImmersiveLayout),
            )
            .visual;
        await measure(
          'exit-fullscreen-lyrics-$pass',
          () => tester.tap(find.byWidget(visual)),
        );
        await measure(
          'close-playback-$pass',
          () async => Navigator.of(
            tester.element(find.byType(NowPlayingImmersiveLayout)),
          ).pop(),
        );
      }
      // Production detail widgets on their normal Material route, not a mock.
      for (final tab in ['歌手', '专辑', '设置', '音乐库']) {
        await measure('home-to-$tab', () => tester.tap(find.text(tab).last));
      }
      for (final page in [
        const ThemeConfigurationPage(),
        const DesktopLyricsPage(),
      ]) {
        await measure('open-${page.runtimeType}', () async {
          Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => page));
        });
        await measure('close-${page.runtimeType}', () async {
          Navigator.of(tester.element(find.byType(page.runtimeType))).pop();
        });
      }
      await tester.tap(find.byType(NowPlayingCoverHero).first);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byType(NowPlayingCoverHero).last);
      await tester.pump(const Duration(seconds: 2));
      Offset lyricCentre() => tester.getCenter(
        find.byWidget(
          tester
              .widget<NowPlayingImmersiveLayout>(
                find.byType(NowPlayingImmersiveLayout),
              )
              .visual,
        ),
      );
      Future<void> doubleTap() async {
        final centre = lyricCentre();
        await tester.tapAt(centre);
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(centre);
        await tester.pump(const Duration(milliseconds: 800));
      }

      await doubleTap();
      expect(player.isPlaying, isTrue);
      expect(
        tester
            .widget<NowPlayingImmersiveLayout>(
              find.byType(NowPlayingImmersiveLayout),
            )
            .immersive,
        isTrue,
      );
      await doubleTap();
      expect(player.isPlaying, isFalse);
      await tester.tapAt(lyricCentre());
      await tester.pump(const Duration(seconds: 1));
      final slider = tester.widget<Slider>(find.byType(Slider).first);
      final target = slider.max * .35;
      slider.onChangeStart!(target);
      slider.onChangeEnd!(target);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(PlaybackJumpFeedback), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(
        (player.currentPosition.inMilliseconds - target).abs(),
        lessThan(1500),
      );
      expect(
        tester
            .widget<PlaybackJumpFeedback>(find.byType(PlaybackJumpFeedback))
            .pending
            .value,
        isFalse,
      );
      Navigator.of(
        tester.element(find.byType(NowPlayingImmersiveLayout)),
      ).pop();
      await tester.pump(const Duration(seconds: 1));
      featuresVerified = true;
    } finally {
      await settings.setPlaybackImmersiveEnabled(immersive);
      await settings.setEnableKaraokeLyrics(karaoke);
      await settings.setKaraokeLyricsMode(mode);
      if (wasPlaying) {
        await player.play();
      } else {
        await player.pause();
      }
      binding.reportData = {
        'pageTransitions': {
          'mode': 'profile',
          'song': player.currentSong?.title,
          'lyricLines': player.currentLyrics.length,
          'advertisedDisplayHz': View.of(context).display.refreshRate,
          'rssBytes': ProcessInfo.currentRss,
          'stages': stages,
          'featuresVerified': featuresVerified,
        },
      };
      // OEM logcat may hide the VM discovery URL. Export diagnostic results
      // directly so a normal profile launch needs no VM auth/launch overrides.
      final directory = await getExternalStorageDirectory();
      if (directory != null) {
        await File(
          '${directory.path}/page-transition-profile.json',
        ).writeAsString(jsonEncode(binding.reportData));
      }
    }
  });
}
