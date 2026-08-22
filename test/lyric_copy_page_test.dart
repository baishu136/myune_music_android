import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/lyric_copy_page.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';

void main() {
  test('lyrics clipboard text keeps display order and skips interludes', () {
    final lines = [
      LyricLine(
        timestamp: Duration.zero,
        texts: const ['第一行', ' First translation '],
      ),
      LyricLine(
        timestamp: const Duration(seconds: 1),
        texts: const ['•••'],
        isInterlude: true,
      ),
      LyricLine(
        timestamp: const Duration(seconds: 2),
        texts: const ['第二行', ''],
      ),
    ];

    expect(lyricsClipboardText(lines), '第一行\nFirst translation\n第二行');
  });

  testWidgets('selected lyric lines update clipboard in original order', (
    tester,
  ) async {
    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['第一行']),
      LyricLine(timestamp: const Duration(seconds: 1), texts: const ['第二行']),
      LyricLine(timestamp: const Duration(seconds: 2), texts: const ['第三行']),
    ];
    await tester.pumpWidget(
      MaterialApp(home: LyricCopyPage(lines: lines, activeLineIndex: 1)),
    );

    await tester.tap(find.byKey(const ValueKey('lyric_copy_line_1')));
    await tester.pump();
    expect(clipboardText, '第二行');

    await tester.tap(find.byKey(const ValueKey('lyric_copy_line_0')));
    await tester.pump();
    expect(clipboardText, '第一行\n第二行');
  });
}
