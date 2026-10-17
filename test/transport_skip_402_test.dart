import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/transport_skip_button.dart';

void main() {
  testWidgets(
    'single tap skips once; hold repeats every 0.6 seconds and release cancels without extra tap',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransportSkipButton(
              tooltip: '下一首',
              icon: Icons.skip_next,
              onSkip: () async {
                calls++;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(calls, 1);
      final pointer = await tester.startGesture(
        tester.getCenter(find.byType(IconButton)),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls, 2);
      await tester.pump(const Duration(milliseconds: 599));
      expect(calls, 2);
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, 3);
      await pointer.up();
      await tester.pump(const Duration(seconds: 5));
      expect(calls, 3);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'slow loads never overlap, pointer cancel and background stop repetition',
    (tester) async {
      var calls = 0;
      final pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransportSkipButton(
              tooltip: '上一首',
              icon: Icons.skip_previous,
              onSkip: () async {
                calls++;
                await pending.future;
              },
            ),
          ),
        ),
      );
      var pointer = await tester.startGesture(
        tester.getCenter(find.byType(IconButton)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(seconds: 6));
      expect(calls, 1);
      pending.complete();
      await tester.pump();
      await pointer.cancel();
      await tester.pump(const Duration(seconds: 4));
      expect(calls, 1);
      pointer = await tester.startGesture(
        tester.getCenter(find.byType(IconButton)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(calls, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 4));
      expect(calls, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pointer.up();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
