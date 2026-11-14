import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/plugins/plugin_view.dart';

void main() {
  test('rejects unsupported, oversized, deep or invalid plugin UI', () {
    expect(
      () => PluginView({'type': 'webview', 'url': 'file:///'}),
      throwsFormatException,
    );
    expect(
      () => PluginView({'type': 'text', 'text': 'x' * 2001}),
      throwsFormatException,
    );
    Map<String, dynamic> tree = {'type': 'text', 'text': 'a'};
    for (var i = 0; i < 10; i++) {
      tree = {
        'type': 'column',
        'children': [tree],
      };
    }
    expect(() => PluginView(tree), throwsFormatException);
    expect(
      () => PluginView({
        'type': 'column',
        'children': [
          for (var i = 0; i < 121; i++) {'type': 'text', 'text': 'x'},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => PluginView({'type': 'button', 'text': 'x', 'action': 'bad();'}),
      throwsFormatException,
    );
  });
  testWidgets(
    'host rendered plugin controls work in portrait and narrow landscape',
    (tester) async {
      final actions = <String>[];
      final view = PluginView({
        'type': 'column',
        'children': [
          {'type': 'text', 'text': '插件页面', 'style': 'title'},
          {
            'type': 'row',
            'children': [
              {'type': 'button', 'text': '播放', 'action': 'play'},
              {'type': 'text', 'text': '长标题' * 20},
            ],
          },
        ],
      });
      for (final size in [const Size(360, 720), const Size(640, 240)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Builder(
                  builder: (context) => view.build(
                    context,
                    (action, data) => actions.add(action),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('播放'));
        await tester.pump();
        expect(tester.takeException(), null);
      }
      expect(actions, ['play', 'play']);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    },
  );
}
