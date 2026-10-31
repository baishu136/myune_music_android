import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/interaction_motion.dart';
import 'package:myune_music/widgets/play_pause_button.dart';
import 'package:myune_music/widgets/navigation_motion_icon.dart';

void main() {
  testWidgets(
    'the production navigation replays current destination without navigating',
    (tester) async {
      var selected = 0, callbacks = 0, pageChanges = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, update) => Scaffold(
              bottomNavigationBar: MyuneNavigationBar(
                selectedIndex: selected,
                onDestinationSelected: (index) {
                  callbacks++;
                  if (index == selected) return;
                  update(() {
                    selected = index;
                    pageChanges++;
                  });
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('音乐库'));
      expect(callbacks, 1);
      expect(pageChanges, 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester
            .widget<Transform>(
              find.byKey(const ValueKey('icon-motion-library')),
            )
            .transform
            .isIdentity(),
        isFalse,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('专辑'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(selected, 3);
      expect(
        tester
            .widget<Transform>(find.byKey(const ValueKey('icon-motion-album')))
            .transform
            .isIdentity(),
        isFalse,
      );
      expect(pageChanges, 1);
      await tester.pumpAndSettle();
      await tester.tap(find.text('专辑'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(pageChanges, 1);
      expect(
        tester
            .widget<Transform>(find.byKey(const ValueKey('icon-motion-album')))
            .transform
            .isIdentity(),
        isFalse,
      );
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  for (final cancellation in ['hidden', 'background', 'dispose']) {
    testWidgets('pending quick feedback cancels on $cancellation', (
      tester,
    ) async {
      var visible = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return TickerMode(
                enabled: visible,
                child: ButtonPressMotion(
                  child: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () {},
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      if (cancellation == 'hidden') {
        update(() => visible = false);
      } else if (cancellation == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      } else {
        await tester.pumpWidget(const SizedBox());
      }
      await tester.pumpAndSettle();
      if (cancellation != 'dispose') {
        expect(
          tester
              .widget<Transform>(
                find.byKey(const ValueKey('button-press-transform')),
              )
              .transform
              .isIdentity(),
          isTrue,
        );
        update(() => visible = true);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('cancel before first frame never starts a completed-tap pulse', (
    tester,
  ) async {
    var actions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ButtonPressMotion(
          child: IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => actions++,
          ),
        ),
      ),
    );
    final pointer = await tester.startGesture(
      tester.getCenter(find.byType(IconButton)),
    );
    await pointer.cancel();
    await tester.pumpAndSettle();
    expect(actions, 0);
    expect(
      tester
          .widget<Transform>(
            find.byKey(const ValueKey('button-press-transform')),
          )
          .transform
          .isIdentity(),
      isTrue,
    );
    expect(tester.binding.transientCallbackCount, 0);
  });
  testWidgets(
    'quick tap still plays visual feedback without delaying the action',
    (tester) async {
      var actions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ButtonPressMotion(
              child: IconButton(
                onPressed: () => actions++,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(IconButton));
      expect(actions, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final matrix = tester
          .widget<Transform>(
            find.byKey(const ValueKey('button-press-transform')),
          )
          .transform;
      expect(matrix.storage[0], lessThan(.99));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  for (final reduced in [false, true]) {
    testWidgets(
      'accessible navigation alone does not disable motion: reduced=$reduced',
      (tester) async {
        var playing = false;
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    accessibleNavigation: true,
                    disableAnimations: reduced,
                  ),
                  child: PlayPauseButton(
                    isPlaying: playing,
                    onPressed: () {},
                    color: Colors.black,
                  ),
                );
              },
            ),
          ),
        );
        update(() => playing = true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        final progress = tester
            .widget<AnimatedIcon>(find.byType(AnimatedIcon))
            .progress
            .value;
        if (reduced) {
          expect(progress, 1);
        } else {
          expect(progress, inExclusiveRange(0, 1));
        }
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }
}
