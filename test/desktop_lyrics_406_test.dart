import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/page/setting/tabs/playback_page_tab.dart';
import 'package:myune_music/services/desktop_lyric_presentation.dart';
import 'package:myune_music/services/desktop_lyrics_controller.dart';
import 'package:myune_music/theme/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DesktopController extends DesktopLyricsController {
  _DesktopController(this.settings);
  final SettingsProvider settings;
  @override
  bool get autoSize => settings.desktopLyricsAutoSize;
  @override
  bool get karaoke => settings.desktopLyricsKaraoke;
  @override
  int get highlightColor => settings.desktopLyricsHighlightColor;
  @override
  TextAlign get alignment => settings.desktopLyricsAlignment;
  @override
  double get fontSize => settings.desktopLyricsFontSize;
  @override
  Future<void> setAutoSize(bool value) =>
      settings.setDesktopLyricsAutoSize(value);
  @override
  Future<void> setKaraoke(bool value) =>
      settings.setDesktopLyricsKaraoke(value);
  @override
  Future<void> setAlignment(TextAlign value) =>
      settings.setDesktopLyricsAlignment(value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'desktop options default safely, persist and retain custom highlight',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      await settings.initializationFuture;
      expect(settings.desktopLyricsAutoSize, isFalse);
      expect(settings.desktopLyricsKaraoke, isFalse);
      expect(settings.desktopLyricsAlignment, TextAlign.center);
      final automatic = settings.desktopLyricsHighlightColor;
      expect(automatic, isNot(settings.desktopLyricsColor));
      expect(automatic, isNot(settings.desktopLyricsOutlineColor));
      await settings.setDesktopLyricsAutoSize(true);
      await settings.setDesktopLyricsKaraoke(true);
      await settings.setDesktopLyricsAlignment(TextAlign.right);
      await settings.setDesktopLyricsHighlightColor(0xFFFF4488);
      await settings.setDesktopLyricsColor(0xFF101010);
      await settings.setDesktopLyricsOutlineColor(0xFF202020);
      expect(settings.desktopLyricsHighlightColor, 0xFFFF4488);
      final restored = SettingsProvider();
      await restored.initializationFuture;
      expect(restored.desktopLyricsAutoSize, isTrue);
      expect(restored.desktopLyricsKaraoke, isTrue);
      expect(restored.desktopLyricsAlignment, TextAlign.right);
      expect(restored.desktopLyricsHighlightColor, 0xFFFF4488);
      await restored.setDesktopLyricsHighlightColor(null);
      expect(restored.desktopLyricsHighlightColor, 0xFFFFFFFF);
      expect(
        (await SharedPreferences.getInstance()).containsKey(
          'desktopLyricsHighlightColor',
        ),
        isFalse,
      );
      restored.dispose();
      settings.dispose();
    },
  );

  test(
    'invalid saved alignment uses center and extreme colours contrast',
    () async {
      SharedPreferences.setMockInitialValues({
        'desktopLyricsAlignment': 'justify',
      });
      final settings = SettingsProvider();
      await settings.initializationFuture;
      expect(settings.desktopLyricsAlignment, TextAlign.center);
      expect(desktopLyricHighlightColor(0xFF000000, 0xFF000000), 0xFFFFFFFF);
      expect(desktopLyricHighlightColor(0xFFFFFFFF, 0xFFFFFFFF), 0xFF000000);
      final middle = Color(
        desktopLyricHighlightColor(0xFF000000, 0xFFFFFFFF),
      ).computeLuminance();
      expect(middle, closeTo(.179, .004));
      settings.dispose();
    },
  );

  test('real timed text keeps UTF16 offsets and translation timings', () {
    final line = LyricLine(
      timestamp: const Duration(seconds: 2),
      texts: ['中👨‍👩‍👦é', 'translation'],
      tokens: [
        [
          LyricToken(
            text: '中',
            start: const Duration(seconds: 2),
            end: const Duration(seconds: 3),
          ),
          LyricToken(
            text: '👨‍👩‍👦é',
            start: const Duration(seconds: 3),
            end: const Duration(seconds: 4),
          ),
        ],
        [
          LyricToken(
            text: 'translation',
            start: const Duration(seconds: 2),
            end: const Duration(seconds: 4),
          ),
        ],
      ],
    );
    final result = DesktopLyricPresentation.fromLine(line, karaoke: true);
    expect(result.text, line.texts.join('\n'));
    expect(result.words[1], {
      'offset': 1,
      'length': line.texts.first.length - 1,
      'start': 3000,
      'end': 4000,
    });
    expect(result.words.last['offset'], line.texts.first.length + 1);
    expect(
      DesktopLyricPresentation.fromLine(line, karaoke: false).words,
      isEmpty,
    );
  });

  test('ordinary LRC estimates original only, interludes stay plain', () {
    final line = LyricLine(
      timestamp: const Duration(seconds: 2),
      texts: ['你好 hello', '翻译'],
    );
    final result = DesktopLyricPresentation.fromLine(
      line,
      karaoke: true,
      nextTimestamp: const Duration(seconds: 6),
    );
    expect(result.words, isNotEmpty);
    expect(
      DesktopLyricPresentation.fromLine(
        line.withSyntheticKaraoke(false),
        karaoke: true,
        nextTimestamp: const Duration(seconds: 6),
      ).words,
      isNotEmpty,
    );
    expect(
      result.words.every(
        (w) => w['offset']! + w['length']! <= line.texts.first.length,
      ),
      isTrue,
    );
    expect(
      DesktopLyricPresentation.fromLine(
        LyricLine(timestamp: Duration.zero, texts: ['间奏'], isInterlude: true),
        karaoke: true,
      ).words,
      isEmpty,
    );
    expect(
      DesktopLyricPresentation.fromLine(null, karaoke: true).words,
      isEmpty,
    );
  });

  test('mismatched provider words never colour unrelated text', () {
    final line = LyricLine(
      timestamp: Duration.zero,
      texts: ['', '有效文字'],
      tokens: [
        [
          LyricToken(
            text: '错误',
            start: Duration.zero,
            end: const Duration(seconds: 1),
          ),
        ],
        [
          LyricToken(
            text: '有效文字',
            start: Duration.zero,
            end: const Duration(seconds: 2),
          ),
        ],
      ],
    );
    final result = DesktopLyricPresentation.fromLine(line, karaoke: true);
    expect(result.text, '有效文字');
    expect(result.words, [
      {'offset': 0, 'length': 4, 'start': 0, 'end': 2000},
    ]);
  });

  testWidgets(
    'desktop controls update preview and independent settings on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'desktopLyricsFontSize': 40.0});
      final settings = SettingsProvider();
      await settings.initializationFuture;
      final theme = ThemeProvider();
      final controller = _DesktopController(settings);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider<DesktopLyricsController>.value(
              value: controller,
            ),
          ],
          child: const MaterialApp(home: DesktopLyricsPage()),
        ),
      );
      final scroll = find.byKey(
        const ValueKey('desktop-lyrics-controls-scroll'),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('desktop-lyrics-auto-size')),
        180,
        scrollable: find.descendant(
          of: scroll,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('desktop-lyrics-auto-size')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('desktop-lyrics-karaoke')));
      await tester.pumpAndSettle();
      expect(settings.desktopLyricsAutoSize, isTrue);
      expect(settings.desktopLyricsKaraoke, isTrue);
      expect(settings.enableKaraokeLyrics, isFalse);
      expect(find.text('已播放部分颜色'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('desktop-lyrics-alignment')),
        150,
        scrollable: find.descendant(
          of: scroll,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('右对齐'));
      await tester.pumpAndSettle();
      expect(settings.desktopLyricsAlignment, TextAlign.right);
      final preview = find.byKey(
        const ValueKey('desktop-lyrics-style-preview'),
      );
      final text = tester.widget<Text>(
        find.descendant(of: preview, matching: find.text('桌面歌词')).first,
      );
      expect(text.textAlign, TextAlign.right);
      expect(
        tester
            .widget<Text>(
              find
                  .descendant(
                    of: preview,
                    matching: find.text('Zhuo Mian Ge Ci'),
                  )
                  .first,
            )
            .style!
            .fontSize,
        lessThan(40),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      settings.dispose();
      theme.dispose();
    },
  );
}
