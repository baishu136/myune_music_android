import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/theme/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void expectDefaultConfiguration(SettingsProvider settings) {
  expect(settings.enableOnlineLyrics, isFalse);
  expect(settings.enableLyricTranslation, isFalse);
  expect(settings.enableLyricSourceFallback, isFalse);
  expect(settings.primaryLyricSource, 'netease');
  expect(settings.secondaryLyricSource, 'qq');
  expect(settings.lyricAlignment, TextAlign.left);
  expect(settings.lyricScrollEffect, LyricScrollEffect.standard);
  expect(settings.enableLyricElasticScroll, isFalse);
  expect(settings.enableKaraokeLyrics, isFalse);
  expect(settings.karaokeLyricsMode, KaraokeLyricsMode.timedOnly);
  expect(settings.lyricFontWeight, FontWeight.w800);
  expect(settings.enableLyricBlur, isFalse);
  expect(settings.highlightActiveLyric, isTrue);
  expect(settings.playbackLyricGlowEnabled, isFalse);
  expect(settings.followAlbumArtOnHome, isFalse);
  expect(settings.followAlbumArtOnPlayback, isTrue);
  expect(
    settings.playbackArtworkBackgroundStyle,
    PlaybackArtworkBackgroundStyle.fluid,
  );
  expect(settings.homeAlbumArtBackgroundDim, .3);
  expect(settings.playbackAlbumArtBackgroundDim, .3);
  expect(settings.homeAlbumArtBackgroundBlur, 40);
  expect(settings.playbackAlbumArtBackgroundBlur, 40);
  expect(settings.homeThemeImageEnabled, isFalse);
  expect(settings.playbackThemeImageEnabled, isFalse);
  expect(settings.homeThemeImageDim, .2);
  expect(settings.playbackThemeImageDim, .2);
  expect(settings.homeThemeImageBlur, 0);
  expect(settings.playbackThemeImageBlur, 0);
  expect(settings.useDynamicColor, isTrue);
  expect(settings.pauseOnAudioInterruption, isTrue);
  expect(settings.preferExternalLyrics, isTrue);
  expect(settings.ignorePlaybackErrors, isFalse);
  expect(settings.enableLoudness, isFalse);
  expect(settings.enableReplayGain, isFalse);
  expect(settings.enableGaplessPlayback, isFalse);
  expect(settings.showAudioAnalysis, isFalse);
  expect(settings.sleepTimerFinishCurrentTrack, isFalse);
  expect(settings.playbackImmersiveEnabled, isFalse);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'fresh configuration is consistent before and after async loading',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      expectDefaultConfiguration(settings);
      await settings.initializationFuture;
      expectDefaultConfiguration(settings);
      // Switching styles selects a preset; it must not reset tuning or enable
      // either custom image. Defaults are not a forced migration on each load.
      await settings.setPlaybackArtworkBackgroundStyle(
        PlaybackArtworkBackgroundStyle.blurred,
      );
      expect(settings.playbackAlbumArtBackgroundDim, .3);
      expect(settings.playbackAlbumArtBackgroundBlur, 40);
      final restored = SettingsProvider();
      await restored.initializationFuture;
      expect(
        restored.playbackArtworkBackgroundStyle,
        PlaybackArtworkBackgroundStyle.blurred,
      );
      expect(restored.playbackAlbumArtBackgroundDim, .3);
      expect(restored.playbackAlbumArtBackgroundBlur, 40);
      expect(restored.playbackThemeImageEnabled, isFalse);
      restored.dispose();
      settings.dispose();
    },
  );

  test(
    'saved non-default choices survive the new defaults without rewriting',
    () async {
      final saved = <String, Object>{
        'enableOnlineLyrics': true,
        'enableLyricTranslation': true,
        'enableLyricSourceFallback': true,
        'primaryLyricSource': 'qq',
        'secondaryLyricSource': 'kugou',
        'lyricAlignment': TextAlign.center.toString(),
        'enableLyricElasticScroll': true,
        'enableKaraokeLyrics': true,
        'karaokeLyricsMode': 'all',
        'lyricFontWeight': 5,
        'enableLyricBlur': true,
        'highlightActiveLyric': false,
        'playbackLyricGlowEnabled': true,
        'followAlbumArtOnHome': true,
        'followAlbumArtOnPlayback': false,
        'playbackArtworkBackgroundStyle': 'blurred',
        'homeThemeImageDim': .62,
        'playbackThemeImageDim': .68,
        'homeThemeImageBlur': 22.0,
        'playbackThemeImageBlur': 22.0,
        'homeAlbumArtBackgroundDim': .52,
        'playbackAlbumArtBackgroundDim': .52,
        'useDynamicColor': false,
        'pauseOnAudioInterruption': false,
        'preferExternalLyrics': false,
        'enableGaplessPlayback': true,
      };
      SharedPreferences.setMockInitialValues(saved);
      final settings = SettingsProvider();
      await settings.initializationFuture;
      expect(settings.enableOnlineLyrics, isTrue);
      expect(settings.enableLyricTranslation, isTrue);
      expect(settings.enableLyricSourceFallback, isTrue);
      expect(settings.primaryLyricSource, 'qq');
      expect(settings.secondaryLyricSource, 'kugou');
      expect(settings.lyricAlignment, TextAlign.center);
      expect(settings.lyricScrollEffect, LyricScrollEffect.elastic);
      expect(settings.enableLyricElasticScroll, isTrue);
      expect(settings.enableKaraokeLyrics, isTrue);
      expect(settings.karaokeLyricsMode, KaraokeLyricsMode.all);
      expect(settings.lyricFontWeight, FontWeight.w600);
      expect(settings.enableLyricBlur, isTrue);
      expect(settings.highlightActiveLyric, isFalse);
      expect(settings.playbackLyricGlowEnabled, isTrue);
      expect(settings.followAlbumArtOnHome, isTrue);
      expect(settings.followAlbumArtOnPlayback, isFalse);
      expect(
        settings.playbackArtworkBackgroundStyle,
        PlaybackArtworkBackgroundStyle.blurred,
      );
      expect(settings.homeThemeImageDim, .62);
      expect(settings.playbackThemeImageDim, .68);
      expect(settings.homeThemeImageBlur, 22);
      expect(settings.playbackThemeImageBlur, 22);
      expect(settings.homeAlbumArtBackgroundDim, .52);
      expect(settings.playbackAlbumArtBackgroundDim, .52);
      expect(settings.useDynamicColor, isFalse);
      expect(settings.pauseOnAudioInterruption, isFalse);
      expect(settings.preferExternalLyrics, isFalse);
      expect(settings.enableGaplessPlayback, isTrue);
      final prefs = await SharedPreferences.getInstance();
      for (final entry in saved.entries) {
        expect(prefs.get(entry.key), entry.value, reason: entry.key);
      }
      settings.dispose();
    },
  );

  test(
    'partial or invalid preferences fall back without overriding valid keys',
    () async {
      SharedPreferences.setMockInitialValues({
        'enableKaraokeLyrics': 'invalid-type',
        'lyricAlignment': 'unknown-alignment',
        'playbackArtworkBackgroundStyle': 'unknown-style',
        'highlightActiveLyric': false,
      });
      final settings = SettingsProvider();
      await settings.initializationFuture;
      expect(settings.enableKaraokeLyrics, isFalse);
      expect(settings.lyricAlignment, TextAlign.left);
      expect(
        settings.playbackArtworkBackgroundStyle,
        PlaybackArtworkBackgroundStyle.fluid,
      );
      expect(settings.highlightActiveLyric, isFalse);
      expect(settings.preferExternalLyrics, isTrue);
      settings.dispose();
    },
  );

  test(
    'dark is the fresh theme while saved light and system modes survive',
    () async {
      for (final mode in [null, 'invalid', 'light', 'system']) {
        SharedPreferences.setMockInitialValues({
          if (mode != null) 'user_theme_mode': mode,
        });
        final theme = ThemeProvider();
        expect(theme.themeMode, ThemeMode.dark);
        // Drain the constructor's actual initialization instead of launching
        // a second concurrent initialize() that could outlive this fixture.
        await Future<void>.delayed(Duration.zero);
        expect(theme.themeMode, switch (mode) {
          'light' => ThemeMode.light,
          'system' => ThemeMode.system,
          _ => ThemeMode.dark,
        });
        theme.dispose();
      }
    },
  );
}
