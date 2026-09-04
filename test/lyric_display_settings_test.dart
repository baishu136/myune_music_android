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
      expect(settings.enableLyricBlur, isFalse);
      expect(settings.highlightActiveLyric, isFalse);
      expect(settings.lyricFontWeightIndex, 5);
      expect(settings.lyricFontWeight, FontWeight.w600);
      expect(settings.desktopLyricsOutlineEnabled, isFalse);
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
      'enableLyricBlur': true,
      'highlightActiveLyric': true,
      'lyricFontWeight': 7,
      'duetLyricLayout': true,
      'lyricBlurStrength': 3.5,
      'desktopLyricsOutlineEnabled': true,
      'desktopLyricsOutlineWidth': 2.4,
      'desktopLyricsOutlineColor': 0xFF00AAFF,
      'desktopLyricsOutlineOpacity': 0.6,
      'desktopLyricsCustomColors': <String>['FF112233', 'FF445566'],
    });
    final settings = SettingsProvider();
    await settings.initializationFuture;

    expect(settings.lyricAlignment, TextAlign.right);
    expect(settings.enableLyricElasticScroll, isTrue);
    expect(settings.enableLyricBlur, isTrue);
    expect(settings.highlightActiveLyric, isTrue);
    expect(settings.lyricFontWeightIndex, 7);
    expect(settings.lyricFontWeight, FontWeight.w800);
    expect(settings.desktopLyricsOutlineEnabled, isTrue);
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
}
