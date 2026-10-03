import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/page/setting/tabs/custom_theme_settings_section.dart';
import 'package:myune_music/page/setting/tabs/playback_page_tab.dart';
import 'package:myune_music/services/desktop_lyrics_controller.dart';
import 'package:myune_music/theme/theme_provider.dart';
import 'package:myune_music/widgets/custom_theme_background.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Native overlay permission is not involved in page navigation/style preview.
class _PreviewController extends DesktopLyricsController {
  _PreviewController(this.settings);
  final SettingsProvider settings;
  @override
  double get fontSize => settings.desktopLyricsFontSize;
  @override
  bool get outlineEnabled => settings.desktopLyricsOutlineEnabled;
  @override
  Future<void> setFontSize(double value) async {
    await settings.setDesktopLyricsFontSize(value);
    notifyListeners();
  }

  @override
  Future<void> setOutlineEnabled(bool value) async {
    await settings.setDesktopLyricsOutlineEnabled(value);
    notifyListeners();
  }
}

void main() {
  Future<void> prepareViewport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (const bool.fromEnvironment('EXPORT_UI_332')) {
      await tester.runAsync(() async {
        final font = FontLoader('Misans')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                await File('assets/fonts/MiSansVF.ttf').readAsBytes(),
              ),
            ),
          );
        await font.load().timeout(const Duration(seconds: 10));
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load().timeout(const Duration(seconds: 10));
      });
    }
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    if (!const bool.fromEnvironment('EXPORT_UI_332')) return;
    await tester.pump();
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage().timeout(
        const Duration(seconds: 10),
      );
      final bytes = await image
          .toByteData(format: ui.ImageByteFormat.png)
          .timeout(const Duration(seconds: 10));
      await File(
        'F:/AGENT/1/test-artifacts/ui-332/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'desktop route stays opaque and preview stays pinned while scrolling/tuning',
    (tester) async {
      await prepareViewport(tester);
      final captureKey = GlobalKey();
      SharedPreferences.setMockInitialValues({
        'homeThemeImageEnabled': true,
        'homeThemeImagePath': File(
          'test/fixtures/expected-cover.png',
        ).absolute.path,
      });
      final settings = SettingsProvider();
      await settings.initializationFuture;
      final theme = ThemeProvider();
      final controller = _PreviewController(settings);
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: settings),
              ChangeNotifierProvider.value(value: theme),
              ChangeNotifierProvider<DesktopLyricsController>.value(
                value: controller,
              ),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                brightness: Brightness.dark,
                fontFamily: 'Misans',
              ),
              home: const Scaffold(body: DesktopLyricsSettingsEntry()),
            ),
          ),
        ),
      );
      expect(find.byType(ExpansionTile), findsNothing);
      await tester.tap(find.byKey(const ValueKey('desktop-lyrics-entry')));
      await tester.pumpAndSettle();
      expect(find.byType(DesktopLyricsPage), findsOneWidget);
      expect(find.byType(CustomThemeBackground), findsNothing);
      final page = tester.widget<Scaffold>(
        find.descendant(
          of: find.byType(DesktopLyricsPage),
          matching: find.byType(Scaffold),
        ),
      );
      expect(page.backgroundColor!.a, 1);
      final preview = find.byKey(
        const ValueKey('desktop-lyrics-style-preview'),
      );
      final top = tester.getTopLeft(preview);
      await capture(tester, captureKey, 'desktop-initial');
      final scroll = find.byKey(
        const ValueKey('desktop-lyrics-controls-scroll'),
      );
      await tester.drag(scroll, const Offset(0, -750));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(preview), top);
      await capture(tester, captureKey, 'desktop-scrolled');
      expect(
        tester.getRect(preview).bottom,
        lessThan(
          tester.view.physicalSize.height / tester.view.devicePixelRatio,
        ),
      );
      await controller.setFontSize(38);
      await controller.setOutlineEnabled(true);
      await tester.pumpAndSettle();
      final previewTexts = tester
          .widgetList<Text>(
            find.descendant(
              of: preview,
              matching: find.text(desktopLyricsPreviewText),
            ),
          )
          .toList();
      expect(previewTexts, hasLength(2));
      expect(previewTexts.last.style!.fontSize, 36);
      expect(tester.getTopLeft(preview), top);
      await capture(tester, captureKey, 'desktop-preview-updated');
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(DesktopLyricsPage), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      settings.dispose();
      theme.dispose();
      controller.dispose();
    },
  );

  testWidgets(
    'theme route displays the enabled custom background and existing controls',
    (tester) async {
      await prepareViewport(tester);
      final captureKey = GlobalKey();
      final path = File('test/fixtures/expected-cover.png').absolute.path;
      SharedPreferences.setMockInitialValues({
        'homeThemeImageEnabled': true,
        'homeThemeImagePath': path,
      });
      final settings = SettingsProvider();
      await settings.initializationFuture;
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: ChangeNotifierProvider.value(
            value: settings,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                brightness: Brightness.dark,
                fontFamily: 'Misans',
              ),
              home: const ThemeConfigurationPage(),
            ),
          ),
        ),
      );
      final background = tester.widget<CustomThemeBackground>(
        find.byType(CustomThemeBackground),
      );
      expect(background.enabled, isTrue);
      expect(background.path, path);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        Colors.transparent,
      );
      expect(find.text('背景风格跟随音乐封面'), findsOneWidget);
      expect(find.byType(ExpansionTile), findsNothing);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      settings.dispose();
    },
  );
}
