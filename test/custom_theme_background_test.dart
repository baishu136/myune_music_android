import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/widgets/custom_theme_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  test('background strength maps to a wide Gaussian sigma', () {
    expect(backgroundGaussianSigma(0), 0);
    expect(backgroundGaussianSigma(22), 49.5);
    expect(backgroundGaussianSigma(40), 90);
    expect(backgroundGaussianSigma(100), 90);
  });

  testWidgets('album artwork can be used as a blurred theme background', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CustomThemeBackground(
          path: null,
          enabled: false,
          dim: 0.6,
          coverBytes: pixel,
          coverEnabled: true,
          child: const Text('content'),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('cover-follow-background')), findsOne);
    expect(find.byType(ImageFiltered), findsOne);
    expect(find.text('content'), findsOne);
  });

  testWidgets('theme falls back to normal content without usable artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CustomThemeBackground(
          path: null,
          enabled: false,
          dim: 0.6,
          coverEnabled: true,
          child: Text('fallback'),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('cover-follow-background')), findsNothing);
    expect(find.text('fallback'), findsOne);
  });

  testWidgets('background blur can be disabled without hiding artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CustomThemeBackground(
          path: null,
          enabled: false,
          dim: 0.6,
          blurSigma: 0,
          coverBlurSigma: 0,
          coverBytes: pixel,
          coverEnabled: true,
          child: const Text('sharp background'),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('cover-follow-background')), findsOne);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.text('sharp background'), findsOne);
  });

  testWidgets('playback background can force a dark overlay', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: CustomThemeBackground(
          path: null,
          enabled: false,
          dim: 0.6,
          coverDim: 0.4,
          coverBytes: pixel,
          coverEnabled: true,
          brightnessOverride: Brightness.dark,
          child: const Text('dark playback'),
        ),
      ),
    );

    final overlay = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final decoration = overlay.decoration! as BoxDecoration;
    expect(decoration.color, Colors.black.withValues(alpha: 0.4));
  });

  test(
    'custom and album artwork background controls persist independently',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      await settings.initializationFuture;

      await settings.setFollowAlbumArtOnHome(true);
      expect(settings.followAlbumArtOnHome, isTrue);
      expect(settings.followAlbumArtOnPlayback, isFalse);

      await settings.setFollowAlbumArtOnPlayback(true);
      await settings.setHomeThemeImageBlur(8);
      await settings.setPlaybackThemeImageBlur(30);
      await settings.setHomeAlbumArtBackgroundDim(0.45);
      await settings.setPlaybackAlbumArtBackgroundDim(0.7);
      await settings.setHomeAlbumArtBackgroundBlur(12);
      await settings.setPlaybackAlbumArtBackgroundBlur(36);
      await settings.setPlaybackLyricGlowEnabled(true);
      await settings.setPlaybackLyricGlowRadius(14);
      await settings.setArtistGroupGridView(true);
      await settings.setGroupCoverPath(
        artist: true,
        group: '测试歌手',
        songPath: r'C:\Music\cover.mp3',
      );
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool('followAlbumArtOnHome'), isTrue);
      expect(preferences.getBool('followAlbumArtOnPlayback'), isTrue);
      expect(preferences.getDouble('homeThemeImageBlur'), 8);
      expect(preferences.getDouble('playbackThemeImageBlur'), 30);
      expect(preferences.getDouble('homeAlbumArtBackgroundDim'), 0.45);
      expect(preferences.getDouble('playbackAlbumArtBackgroundDim'), 0.7);
      expect(preferences.getDouble('homeAlbumArtBackgroundBlur'), 12);
      expect(preferences.getDouble('playbackAlbumArtBackgroundBlur'), 36);
      expect(preferences.getBool('playbackLyricGlowEnabled'), isTrue);
      expect(preferences.getDouble('playbackLyricGlowRadius'), 14);
      expect(settings.homeThemeImageBlur, 8);
      expect(settings.playbackThemeImageBlur, 30);
      expect(settings.homeAlbumArtBackgroundBlur, 12);
      expect(settings.playbackAlbumArtBackgroundBlur, 36);
      expect(settings.playbackLyricGlowEnabled, isTrue);
      expect(settings.playbackLyricGlowRadius, 14);
      expect(preferences.getBool('artistGroupGridView'), isTrue);
      expect(preferences.getBool('albumGroupGridView'), isNull);

      final restored = SettingsProvider();
      await restored.initializationFuture;
      expect(restored.playbackLyricGlowEnabled, isTrue);
      expect(restored.playbackLyricGlowRadius, 14);
      expect(restored.artistGroupCoverPaths['测试歌手'], r'C:\Music\cover.mp3');
      expect(restored.albumGroupCoverPaths, isEmpty);
    },
  );

  test('album artwork backgrounds use matching independent defaults', () async {
    SharedPreferences.setMockInitialValues({
      'homeThemeImageBlur': 8.0,
      'playbackThemeImageBlur': 30.0,
    });
    final settings = SettingsProvider();
    await settings.initializationFuture;

    expect(settings.homeAlbumArtBackgroundBlur, 40);
    expect(settings.playbackAlbumArtBackgroundBlur, 40);
    expect(settings.homeAlbumArtBackgroundDim, 0.52);
    expect(settings.playbackAlbumArtBackgroundDim, 0.52);
    expect(settings.playbackLyricGlowEnabled, isFalse);
    expect(settings.playbackLyricGlowRadius, 8);
  });

  test('legacy integer sliders do not interrupt background restoration', () async {
    SharedPreferences.setMockInitialValues({
      'fontSize': 20,
      'lyricVerticalSpacing': 6,
      'homeThemeImagePath': '/persisted/home-background.jpg',
      'homeThemeImageEnabled': true,
      'homeThemeImageDim': 1,
      'homeThemeImageBlur': 18,
    });

    final settings = SettingsProvider();
    await settings.initializationFuture;

    expect(settings.fontSize, 20);
    expect(settings.lyricVerticalSpacing, 6);
    expect(settings.homeThemeImagePath, '/persisted/home-background.jpg');
    expect(settings.homeThemeImageEnabled, isTrue);
    expect(settings.homeThemeImageDim, 0.9);
    expect(settings.homeThemeImageBlur, 18);
  });

  test(
    'persisted background controls are clamped to supported ranges',
    () async {
      SharedPreferences.setMockInitialValues({
        'homeThemeImageDim': -1.0,
        'playbackThemeImageDim': 2.0,
        'homeThemeImageBlur': -5.0,
        'playbackThemeImageBlur': 90.0,
        'homeAlbumArtBackgroundDim': -1.0,
        'playbackAlbumArtBackgroundDim': 2.0,
        'homeAlbumArtBackgroundBlur': -5.0,
        'playbackAlbumArtBackgroundBlur': 90.0,
      });
      final settings = SettingsProvider();
      await settings.initializationFuture;

      expect(settings.homeThemeImageDim, 0.2);
      expect(settings.playbackThemeImageDim, 0.9);
      expect(settings.homeThemeImageBlur, 0);
      expect(settings.playbackThemeImageBlur, 40);
      expect(settings.homeAlbumArtBackgroundDim, 0.2);
      expect(settings.playbackAlbumArtBackgroundDim, 0.9);
      expect(settings.homeAlbumArtBackgroundBlur, 0);
      expect(settings.playbackAlbumArtBackgroundBlur, 40);
    },
  );
}
