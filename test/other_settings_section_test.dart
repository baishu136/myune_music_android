import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/setting/tabs/other_settings_section.dart';

void main() {
  testWidgets('other settings replace sponsorship with the GitHub Star link', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: OtherSettingsSection())),
    );

    await tester.tap(find.text('其他'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('支持项目'));
    await tester.pumpAndSettle();

    expect(find.text('如果您喜欢此软件，请在GitHub留下star'), findsOneWidget);
    expect(
      find.text('https://github.com/baishu136/myune_music_android'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('project-github-link')), findsOneWidget);
    expect(find.text('赞助'), findsNothing);
    expect(find.text('微信'), findsNothing);
    expect(find.text('支付宝'), findsNothing);
    expect(find.text('保存两张二维码到相册'), findsNothing);
  });

  testWidgets('other settings explain that the changelog starts at 0.99', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: OtherSettingsSection())),
    );

    await tester.tap(find.text('其他'));
    await tester.pumpAndSettle();

    expect(find.text('查看 0.99 发布以来的全部有效更改'), findsOneWidget);
  });
}
