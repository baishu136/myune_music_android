import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/services/interaction_performance_controller.dart';
import 'package:myune_music/widgets/home_tab_viewport.dart';

void main() {
  testWidgets('failed preparation is bounded and can be retried', (
    tester,
  ) async {
    final controller = HomeTabController();
    var attempts = 0;
    final work = InteractionPerformanceController.instance;
    work.pulse(InteractionPhase.idle);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeTabViewport(
          controller: controller,
          itemCount: 2,
          progressiveWarmup: true,
          preparePage: (_) async {
            attempts++;
            if (attempts == 1) throw StateError('delayed groups failed');
          },
          loadingBuilder: (_, i) => Text('preparing $i'),
          onPageChanged: (_) {},
          itemBuilder: (_, i) => Text('ready $i'),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 24));
    }
    expect(attempts, 1);
    controller.jumpToPage(1);
    await tester.pump();
    await tester.tap(find.text('加载失败，点击重试'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 24));
    }
    expect(attempts, 2);
    expect(find.text('ready 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    work.pulse(InteractionPhase.idle);
    await tester.pump(const Duration(milliseconds: 100));
  });
  testWidgets('slow group preparation does not block playlists or settings', (
    tester,
  ) async {
    final controller = HomeTabController();
    final slow = Completer<void>();
    final built = <int>[];
    final work = InteractionPerformanceController.instance;
    work.pulse(InteractionPhase.idle);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeTabViewport(
          controller: controller,
          itemCount: 5,
          progressiveWarmup: true,
          preparePage: (i) =>
              i == 2 || i == 3 ? slow.future : Future<void>.value(),
          loadingBuilder: (_, i) => Text('preparing $i'),
          onPageChanged: (_) {},
          itemBuilder: (_, i) {
            built.add(i);
            return Text('ready $i');
          },
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 24));
    }
    expect(controller.preparedPages, {0, 1, 4});
    expect(built, isNot(contains(2)));
    controller.jumpToPage(2);
    await tester.pump();
    expect(find.text('preparing 2'), findsOneWidget);
    expect(find.text('ready 2'), findsNothing);
    slow.complete();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 24));
    }
    expect(controller.preparedPages, {0, 1, 2, 3, 4});
    expect(find.text('ready 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    work.pulse(InteractionPhase.idle);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets(
    'unmount cancels deferred preparation without mounting a cold page',
    (tester) async {
      final controller = HomeTabController();
      final work = InteractionPerformanceController.instance;
      work.pulse(
        InteractionPhase.transition,
        settleAfter: const Duration(seconds: 2),
      );
      final built = <int>{};
      await tester.pumpWidget(
        MaterialApp(
          home: HomeTabViewport(
            controller: controller,
            itemCount: 5,
            progressiveWarmup: true,
            onPageChanged: (_) {},
            itemBuilder: (_, i) {
              built.add(i);
              return Text('$i');
            },
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      work.endPhase(InteractionPhase.transition);
      await tester.pump(const Duration(milliseconds: 100));
      expect(built, {0});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('idle preparation lays out hidden pages without navigation', (
    tester,
  ) async {
    final controller = HomeTabController();
    addTearDown(controller.dispose);
    final built = <int>{};
    final changes = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: HomeTabViewport(
          controller: controller,
          itemCount: 5,
          progressiveWarmup: true,
          onPageChanged: changes.add,
          itemBuilder: (_, i) {
            built.add(i);
            return Text('page $i');
          },
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 24));
    }
    expect(built, {0, 1, 2, 3, 4});
    expect(controller.preparedPages, {0, 1, 2, 3, 4});
    expect(controller.index, 0);
    expect(changes, isEmpty);
    expect(find.text('page 4'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cold drag never mounts destination until interaction settles', (
    tester,
  ) async {
    final controller = HomeTabController();
    addTearDown(controller.dispose);
    final built = <int>{};
    final work = InteractionPerformanceController.instance;
    work.pulse(
      InteractionPhase.interacting,
      settleAfter: const Duration(seconds: 3),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomeTabViewport(
          controller: controller,
          itemCount: 5,
          progressiveWarmup: true,
          onPageChanged: (_) {},
          itemBuilder: (_, i) {
            built.add(i);
            return Text('page $i');
          },
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(600, 250));
    await gesture.moveBy(const Offset(-250, 0));
    await tester.pump();
    expect(built, {0});
    await gesture.up();
    await tester.pumpAndSettle();
    expect(built, {0});
    work.endPhase(InteractionPhase.interacting);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 24));
    }
    expect(built, contains(1));
    expect(controller.index, 1);
    expect(tester.takeException(), isNull);
  });
}
