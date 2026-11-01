import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/playback_bottom_sheet.dart';

const _fade = ValueKey('playback-bottom-sheet-fade');
void main() {
  testWidgets(
    'whole Material sheet fades on its existing route and completes its result',
    (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showPlaybackBottomSheet<String>(
                    context: context,
                    showDragHandle: true,
                    backgroundColor: Colors.blue,
                    sheetAnimationStyle: const AnimationStyle(
                      duration: Duration(milliseconds: 260),
                      reverseDuration: Duration(milliseconds: 220),
                    ),
                    builder: (context) => SizedBox(
                      height: 220,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, 'selected'),
                        child: const Text('Close'),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      double opacity() =>
          tester.widget<FadeTransition>(find.byKey(_fade)).opacity.value;
      expect(opacity(), 0);
      expect(
        find.ancestor(
          of: find.byType(BottomSheet),
          matching: find.byKey(_fade),
        ),
        findsOneWidget,
        reason: 'surface, drag handle, outline and content must all fade',
      );
      await tester.pump(const Duration(milliseconds: 65));
      expect(opacity(), inExclusiveRange(0, 1));
      final route = ModalRoute.of(tester.element(find.text('Close')))!;
      expect(route, isA<ModalBottomSheetRoute<String>>());
      expect(route.transitionDuration, const Duration(milliseconds: 260));
      expect(
        route.reverseTransitionDuration,
        const Duration(milliseconds: 220),
      );
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(opacity(), inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(result, 'selected');
      expect(find.byKey(_fade), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets(
    'drag cancellation returns opacity continuously; full drag dismisses',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showPlaybackBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (_) => const SizedBox(
                    height: 400,
                    child: Center(child: Text('Panel')),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      double opacity() =>
          tester.widget<FadeTransition>(find.byKey(_fade)).opacity.value;
      final handle = find.byType(BottomSheet);
      final gesture = await tester.startGesture(
        tester.getTopLeft(handle) + const Offset(150, 20),
      );
      await gesture.moveBy(
        const Offset(0, 20),
        timeStamp: const Duration(milliseconds: 200),
      );
      await tester.pump();
      await gesture.moveBy(
        const Offset(0, 60),
        timeStamp: const Duration(milliseconds: 600),
      );
      await tester.pump();
      expect(opacity(), inExclusiveRange(0, 1));
      final before = opacity();
      await gesture.up(timeStamp: const Duration(milliseconds: 1000));
      await tester.pump();
      expect(opacity(), closeTo(before, .01));
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      await tester.dragFrom(
        tester.getTopLeft(handle) + const Offset(150, 20),
        const Offset(0, 450),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_fade), findsNothing);
    },
  );

  testWidgets('reduced motion retains a usable sheet and immediate dismissal', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showPlaybackBottomSheet<void>(
                  context: context,
                  builder: (context) => SizedBox(
                    height: 120,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Close'), findsOneWidget);
    expect(find.byKey(_fade), findsNothing);
    final route = ModalRoute.of(tester.element(find.text('Close')))!;
    expect(route.transitionDuration, Duration.zero);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Close'), findsNothing);
  });
}
