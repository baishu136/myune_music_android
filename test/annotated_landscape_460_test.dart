import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/now_playing_immersive_layout.dart';
import 'package:myune_music/widgets/playback_actions_menu.dart';
import 'package:myune_music/widgets/playback_system_ui.dart';

void main() {
  testWidgets('landscape controls precede the retained right visual', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NowPlayingImmersiveLayout(
            immersive: false,
            split: true,
            header: Text('header'),
            visual: ColoredBox(key: ValueKey('visual'), color: Colors.blue),
            controls: SizedBox(width: double.infinity, child: Text('controls')),
          ),
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.text('controls')).dx,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('visual'))).dx),
    );
    final visual = tester.getRect(find.byKey(const ValueKey('visual')));
    final scroll = tester.getRect(
      find.byKey(const PageStorageKey('landscape-playback-controls')),
    );
    final header = tester.getRect(find.text('header'));
    expect(scroll.width / (visual.width + scroll.width), closeTo(.43, .001));
    expect(header.right, lessThan(visual.left));
    expect(visual.top, lessThan(header.bottom));
    expect(visual.height, greaterThan(scroll.height));
  });
  testWidgets(
    'single actions menu opens every destination and respects optional analysis',
    (tester) async {
      PlaybackMenuAction? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaybackActionsMenu(
              showAnalysis: true,
              onSelected: (value) => selected = value,
            ),
          ),
        ),
      );
      for (final entry in {
        '队列': PlaybackMenuAction.queue,
        '音效': PlaybackMenuAction.effects,
        '歌词': PlaybackMenuAction.lyrics,
        '均衡器预设': PlaybackMenuAction.preset,
        '音频分析': PlaybackMenuAction.analysis,
      }.entries) {
        await tester.tap(find.text('播放功能'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        expect(selected, entry.value);
      }
    },
  );
  testWidgets('playback ownership restores on exit, background and disposal', (
    tester,
  ) async {
    final values = <bool>[];
    const channel = MethodChannel('com.myune.music/playback_ui');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      expect(call.method, 'setPlaybackActive');
      values.add(call.arguments as bool);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    var full = true;
    late StateSetter update;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (_, setState) {
          update = setState;
          return PlaybackSystemUi(active: full, child: const SizedBox());
        },
      ),
    );
    expect(values.last, true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(values.last, true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(values.last, true);
    update(() => full = false);
    await tester.pump();
    expect(values.last, false);
    update(() => full = true);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(values.last, false);
  });
}
