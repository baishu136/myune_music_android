import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/page/setting/tabs/custom_theme_settings_section.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('theme configuration opens a route instead of expanding inline', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.initializationFuture;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: CustomThemeSettingsSection()),
          ),
        ),
      ),
    );

    expect(find.text('主题配置'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.byType(Card), findsNothing);
    expect(find.text('背景风格跟随音乐封面'), findsNothing);
    expect(find.text('导入图片后可双指缩放、拖动裁剪。主界面与播放页使用独立背景。'), findsNothing);

    await tester.tap(find.text('主题配置'));
    await tester.pumpAndSettle();

    expect(find.text('背景风格跟随音乐封面'), findsOneWidget);
    expect(find.text('主界面背景'), findsOneWidget);
    // The default enabled playback background expands its controls. Scroll
    // the real route rather than assuming all three cards fit the viewport.
    await tester.scrollUntilVisible(find.text('播放页背景'), 200);
    expect(find.text('播放页背景'), findsOneWidget);
    expect(find.byType(ThemeConfigurationPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ThemeConfigurationPage), findsNothing);
    expect(find.text('背景风格跟随音乐封面'), findsNothing);
  });
}
