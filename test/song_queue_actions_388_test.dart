import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/song_queue_actions.dart';

void main() {
  testWidgets(
    'two independent accessible actions disable during an outstanding write',
    (tester) async {
      var added = 0, next = 0;
      final pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 100,
              child: SongQueueActions(
                onAdd: () async {
                  added++;
                  await pending.future;
                },
                onNext: () async {
                  next++;
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('加入播放队列'));
      await tester.pump();
      await tester.tap(find.byTooltip('下一首播放'));
      expect(added, 1);
      expect(next, 0);
      pending.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下一首播放'));
      await tester.pumpAndSettle();
      expect(next, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('queue failure reports and restores the actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongQueueActions(
            onAdd: () async => throw StateError('disk'),
            onNext: () async {},
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('加入播放队列'));
    await tester.pumpAndSettle();
    expect(find.text('无法更新播放队列，请重试'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == '下一首播放',
            ),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
}
