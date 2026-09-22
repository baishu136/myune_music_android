import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/setting/tabs/playback_page_tab.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('desktop lyrics preview uses the requested two-line sample', () {
    expect(desktopLyricsPreviewText, '桌面歌词\nZhuo Mian Ge Ci');
  });

  test(
    'lyric display settings default to regular centered presentation',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      await settings.initializationFuture;

      expect(settings.lyricAlignment, TextAlign.center);
      expect(settings.enableLyricElasticScroll, isFalse);
      expect(settings.enableKaraokeLyrics, isTrue);
      expect(settings.karaokeLyricsMode, KaraokeLyricsMode.timedOnly);
      expect(settings.sleepTimerFinishCurrentTrack, isFalse);
      expect(settings.enableLyricBlur, isFalse);
      expect(settings.highlightActiveLyric, isFalse);
      expect(settings.lyricFontWeightIndex, 5);
      expect(settings.lyricFontWeight, FontWeight.w600);
      expect(settings.desktopLyricsOutlineEnabled, isFalse);
      expect(settings.desktopLyricsOpacity, 1.0);
      expect(settings.desktopLyricsFontWeight, 600);
      expect(settings.desktopLyricsOutlineWidth, 1.15);
      expect(settings.desktopLyricsOutlineColor, 0xFFFFFFFF);
      expect(settings.desktopLyricsOutlineOpacity, 1.0);
      expect(settings.desktopLyricsCustomColors, isEmpty);
    },
  );

  test('lyric display preferences are restored', () async {
    SharedPreferences.setMockInitialValues({
      'lyricAlignment': TextAlign.right.toString(),
      'enableLyricElasticScroll': true,
      'enableKaraokeLyrics': false,
      'karaokeLyricsMode': 'all',
      'sleepTimerFinishCurrentTrack': true,
      'enableLyricBlur': true,
      'highlightActiveLyric': true,
      'lyricFontWeight': 7,
      'duetLyricLayout': true,
      'lyricBlurStrength': 3.5,
      'desktopLyricsOutlineEnabled': true,
      'desktopLyricsOpacity': 0.55,
      'desktopLyricsFontWeight': 800,
      'desktopLyricsOutlineWidth': 2.4,
      'desktopLyricsOutlineColor': 0xFF00AAFF,
      'desktopLyricsOutlineOpacity': 0.6,
      'desktopLyricsCustomColors': <String>['FF112233', 'FF445566'],
    });
    final settings = SettingsProvider();
    await settings.initializationFuture;

    expect(settings.lyricAlignment, TextAlign.right);
    expect(settings.enableLyricElasticScroll, isTrue);
    expect(settings.enableKaraokeLyrics, isFalse);
    expect(settings.karaokeLyricsMode, KaraokeLyricsMode.all);
    expect(settings.sleepTimerFinishCurrentTrack, isTrue);
    expect(settings.enableLyricBlur, isTrue);
    expect(settings.highlightActiveLyric, isTrue);
    expect(settings.lyricFontWeightIndex, 7);
    expect(settings.lyricFontWeight, FontWeight.w800);
    expect(settings.desktopLyricsOutlineEnabled, isTrue);
    expect(settings.desktopLyricsOpacity, 0.55);
    expect(settings.desktopLyricsFontWeight, 800);
    expect(settings.desktopLyricsOutlineWidth, 2.4);
    expect(settings.desktopLyricsOutlineColor, 0xFF00AAFF);
    expect(settings.desktopLyricsOutlineOpacity, 0.6);
    expect(settings.desktopLyricsCustomColors, const <int>[
      0xFF112233,
      0xFF445566,
    ]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('duetLyricLayout'), isFalse);
    expect(prefs.containsKey('lyricBlurStrength'), isFalse);
  });

  test('karaoke and sleep timer preferences are persisted', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.initializationFuture;

    await settings.setEnableKaraokeLyrics(false);
    await settings.setKaraokeLyricsMode(KaraokeLyricsMode.all);
    await settings.setSleepTimerFinishCurrentTrack(true);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('enableKaraokeLyrics'), isFalse);
    expect(prefs.getString('karaokeLyricsMode'), 'all');
    expect(prefs.getBool('sleepTimerFinishCurrentTrack'), isTrue);
  });

  test('desktop lyric custom colors keep five newest unique colors', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.initializationFuture;

    for (final color in const <int>[
      0xFF000001,
      0xFF000002,
      0xFF000003,
      0xFF000004,
      0xFF000005,
      0xFF000006,
      0xFF000003,
    ]) {
      await settings.rememberDesktopLyricsCustomColor(color);
    }

    expect(settings.desktopLyricsCustomColors, const <int>[
      0xFF000003,
      0xFF000006,
      0xFF000005,
      0xFF000004,
      0xFF000002,
    ]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('desktopLyricsCustomColors'), const <String>[
      'ff000003',
      'ff000006',
      'ff000005',
      'ff000004',
      'ff000002',
    ]);
  });

  test('desktop lyric opacity and weight are clamped and persisted', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.initializationFuture;

    await settings.setDesktopLyricsOpacity(0.05);
    await settings.setDesktopLyricsFontWeight(765);

    expect(settings.desktopLyricsOpacity, 0.2);
    expect(settings.desktopLyricsFontWeight, 800);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('desktopLyricsOpacity'), 0.2);
    expect(prefs.getInt('desktopLyricsFontWeight'), 800);
  });
}
