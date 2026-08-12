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

  test(
    'album artwork background selections are persisted independently',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      await settings.initializationFuture;

      await settings.setFollowAlbumArtOnHome(true);
      expect(settings.followAlbumArtOnHome, isTrue);
      expect(settings.followAlbumArtOnPlayback, isFalse);

      await settings.setFollowAlbumArtOnPlayback(true);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool('followAlbumArtOnHome'), isTrue);
      expect(preferences.getBool('followAlbumArtOnPlayback'), isTrue);
    },
  );
}
