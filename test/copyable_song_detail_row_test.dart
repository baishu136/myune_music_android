import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/services/notification_service.dart';
import 'package:myune_music/widgets/copyable_song_detail_row.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );

  Future<NotificationService> mount(
    WidgetTester tester, {
    String label = '歌曲名',
    String value = '歌曲名 / Song 🎵',
    Brightness brightness = Brightness.light,
  }) async {
    final notices = NotificationService();
    addTearDown(notices.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<NotificationService>.value(
        value: notices,
        child: MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: SongDetailsFeedbackSurface(
                child: CopyableSongDetailRow(label: label, value: value),
              ),
            ),
          ),
        ),
      ),
    );
    return notices;
  }

  testWidgets(
    'underlines values and long press copies exact information in both themes',
    (tester) async {
      final copied = <String>[];
      var haptics = 0;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        } else if (call.method == 'HapticFeedback.vibrate') {
          expect(call.arguments, 'HapticFeedbackType.lightImpact');
          haptics++;
        }
        return null;
      });
      for (final brightness in Brightness.values) {
        for (final entry in {
          '歌曲名': '歌曲名 / Song 🎵',
          '歌手': '甲 / 乙 / Artist',
          '收听次数': '0 次',
          '比特率': '未知',
          '文件路径': 'content://media/external/audio/media/1234567890123456789',
        }.entries) {
          final notices = await mount(
            tester,
            label: entry.key,
            value: entry.value,
            brightness: brightness,
          );
          expect(
            tester.widget<Text>(find.text(entry.value)).style?.decoration,
            TextDecoration.underline,
          );
          expect(
            tester.widget<Text>(find.text(entry.key)).style?.decoration,
            isNot(TextDecoration.underline),
          );
          final count = copied.length;
          await tester.tap(find.text(entry.key));
          await tester.pump();
          expect(copied, hasLength(count));
          await tester.longPress(find.text(entry.key));
          await tester.pump();
          expect(copied.last, entry.value);
          expect(haptics, copied.length);
          expect(notices.current, isNull);
          expect(find.text('已复制歌曲信息'), findsOneWidget);
          await tester.pumpAndSettle();
          expect(
            tester.getRect(find.byType(SnackBar)).bottom,
            greaterThan(500),
          );
          await tester.pump(const Duration(milliseconds: 1600));
          await tester.pumpAndSettle();
          expect(find.text('已复制歌曲信息'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      }
    },
  );

  testWidgets('clipboard failure reports an error instead of success', (
    tester,
  ) async {
    var haptics = 0;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        throw PlatformException(code: 'clipboard_unavailable');
      } else if (call.method == 'HapticFeedback.vibrate') {
        haptics++;
      }
      return null;
    });
    final notices = await mount(tester);
    await tester.longPress(find.text('歌曲名'));
    await tester.pump();
    expect(notices.current?.kind, AppNoticeKind.error);
    expect(haptics, 0);
    expect(find.text('已复制歌曲信息'), findsNothing);
    expect(tester.takeException(), isNull);
    notices.dismiss();
  });

  testWidgets(
    'empty values do not copy and late completion does not use a disposed row',
    (tester) async {
      var writes = 0;
      var haptics = 0;
      final pending = Completer<void>();
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          writes++;
          await pending.future;
        } else if (call.method == 'HapticFeedback.vibrate') {
          haptics++;
        }
        return null;
      });
      await mount(tester, value: ' ');
      await tester.longPress(find.text('歌曲名'));
      await tester.pump();
      expect(writes, 0);
      final notices = await mount(tester, value: 'New song');
      await tester.longPress(find.text('New song'));
      await tester.pump();
      expect(writes, 1);
      expect(haptics, 0);
      expect(find.text('已复制歌曲信息'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      pending.complete();
      await tester.pump();
      expect(notices.current, isNull);
      expect(haptics, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'feedback appears at the screen bottom above a draggable details sheet',
    (tester) async {
      messenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (_) async => null,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => DraggableScrollableSheet(
                    expand: false,
                    initialChildSize: .72,
                    builder: (_, controller) => SongDetailsFeedbackSurface(
                      child: ListView(
                        controller: controller,
                        children: const [
                          CopyableSongDetailRow(label: '歌曲名', value: 'Solo'),
                        ],
                      ),
                    ),
                  ),
                ),
                child: const Text('歌曲详情'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('歌曲详情'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Solo'));
      await tester.pumpAndSettle();
      expect(find.text('已复制歌曲信息'), findsOneWidget);
      final bounds = tester.getRect(find.byType(SnackBar));
      expect(bounds.top, greaterThan(500));
      expect(bounds.bottom, lessThanOrEqualTo(600));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'repeated copies replace the notice and optional haptic failure does not fail copying',
    (tester) async {
      final copied = <String>[];
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        } else if (call.method == 'HapticFeedback.vibrate') {
          throw PlatformException(code: 'haptics_unavailable');
        }
        return null;
      });
      final notices = await mount(tester, value: 'Repeat');
      for (var i = 0; i < 2; i++) {
        await tester.longPress(find.text('Repeat'));
        await tester.pumpAndSettle();
        expect(find.text('已复制歌曲信息'), findsOneWidget);
      }
      expect(copied, ['Repeat', 'Repeat']);
      expect(notices.current, isNull);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    },
  );
}
