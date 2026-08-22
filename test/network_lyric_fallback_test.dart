import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'selected lyric source runs first then follows fixed fallback priority',
    () {
      expect(networkLyricSourceOrder('netease'), ['netease', 'qq', 'kugou']);
      expect(networkLyricSourceOrder('qq'), ['qq', 'netease', 'kugou']);
      expect(networkLyricSourceOrder('kugou'), ['kugou', 'netease', 'qq']);
    },
  );

  test('lyric source fallback can be disabled', () {
    expect(networkLyricSourceOrder('netease', enableFallback: false), [
      'netease',
    ]);
    expect(networkLyricSourceOrder('qq', enableFallback: false), ['qq']);
    expect(networkLyricSourceOrder('kugou', enableFallback: false), ['kugou']);
  });

  test('unknown lyric source falls back to the complete default chain', () {
    expect(networkLyricSourceOrder('unknown'), ['netease', 'qq', 'kugou']);
  });

  test(
    'network lyric translation can be excluded without changing original',
    () {
      const original = ['[00:01.00]Original'];
      const translated = ['[00:01.00]翻译'];

      expect(
        combineNetworkLyricLines(
          original,
          translated,
          includeTranslation: false,
        ),
        original,
      );
      expect(
        combineNetworkLyricLines(
          original,
          translated,
          includeTranslation: true,
        ),
        ['[00:01.00]Original', '', '[00:01.00]翻译'],
      );
    },
  );

  test('network lyric translation defaults on and is persisted', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.initializationFuture;
    expect(settings.enableLyricTranslation, isTrue);

    await settings.setEnableLyricTranslation(false);
    final restored = SettingsProvider();
    await restored.initializationFuture;
    expect(restored.enableLyricTranslation, isFalse);
  });

  test('lyric source fallback defaults off and is persisted', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.initializationFuture;
    expect(settings.enableLyricSourceFallback, isFalse);

    await settings.setEnableLyricSourceFallback(true);
    final restored = SettingsProvider();
    await restored.initializationFuture;
    expect(restored.enableLyricSourceFallback, isTrue);
  });
}
