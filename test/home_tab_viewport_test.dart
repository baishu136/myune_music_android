import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/home_tab_viewport.dart';
import 'package:myune_music/services/interaction_performance_controller.dart';

void main() {
  testWidgets(
    'warm slides retain cache policy and controller replacement is safe',
    (tester) async {
      final first = PageController();
      final second = PageController();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      Widget host(PageController controller) => MaterialApp(
        home: HomeTabViewport(
          controller: controller,
          itemCount: 5,
          onPageChanged: (_) {},
          itemBuilder: (_, index) => Text('tab $index'),
        ),
      );
      await tester.pumpWidget(host(first));
      for (var page = 1; page < 5; page++) {
        first.jumpToPage(page);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 220));
        await tester.pumpAndSettle();
      }
      first.animateToPage(
        3,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      for (var frame = 0; frame < 21; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          tester.widget<PageView>(find.byType(PageView)).allowImplicitScrolling,
          isTrue,
          reason: 'warm motion must not retoggle viewport cache extent',
        );
      }
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(second));
      await tester.pump();
      second.animateToPage(
        1,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.widget<PageView>(find.byType(PageView)).controller, second);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 220));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reverse navigation cancels stale idle preparation', (
    tester,
  ) async {
    final activity = InteractionPerformanceController.instance;
    activity.pulse(
      InteractionPhase.transition,
      settleAfter: const Duration(seconds: 5),
    );
    addTearDown(() => activity.endPhase(InteractionPhase.transition));
    final controller = PageController();
    addTearDown(controller.dispose);
    final built = <int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: HomeTabViewport(
          controller: controller,
          itemCount: 5,
          onPageChanged: (_) {},
          itemBuilder: (_, index) {
            built.add(index);
            return Text('tab $index');
          },
        ),
      ),
    );
    controller.animateToPage(
      1,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 220));
    expect(built, isNot(contains(2)));
    controller.animateToPage(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
    await tester.pumpAndSettle();
    activity.endPhase(InteractionPhase.transition);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();
    expect(controller.page, 0);
    expect(built, isNot(contains(2)));
    controller.jumpToPage(1);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 220));
    expect(tester.takeException(), isNull);
  });

  testWidgets('vertical list scroll does not suppress horizontal preparation', (
    tester,
  ) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeTabViewport(
          controller: controller,
          itemCount: 5,
          onPageChanged: (_) {},
          itemBuilder: (_, index) => ListView(
            key: ValueKey('list-$index'),
            children: const [SizedBox(height: 2000)],
          ),
        ),
      ),
    );
    await tester.drag(
      find.byKey(const ValueKey('list-0')),
      const Offset(0, -200),
    );
    expect(
      tester.widget<PageView>(find.byType(PageView)).allowImplicitScrolling,
      isTrue,
    );
    expect(controller.page, 0);
    await tester.pumpAndSettle();
  });

  testWidgets('invisible next tab is not first built during a slide', (
    tester,
  ) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    final firstBuilds = <int, bool>{};
    await tester.pumpWidget(
      MaterialApp(
        home: HomeTabViewport(
          controller: controller,
          itemCount: 5,
          onPageChanged: (_) {},
          itemBuilder: (_, index) {
            firstBuilds.putIfAbsent(
              index,
              () => controller.position.isScrollingNotifier.value,
            );
            return Text('tab $index');
          },
        ),
      ),
    );
    expect(firstBuilds.keys, containsAll([0, 1]));
    final slide = controller.animateToPage(
      1,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
    for (var frame = 0; frame < 21; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        firstBuilds.containsKey(2),
        isFalse,
        reason: 'tab 2 is neither source nor target of this transition',
      );
    }
    expect(controller.page, closeTo(1, .001));
    await tester.pumpAndSettle();
    await slide;
    expect(controller.position.isScrollingNotifier.value, isFalse);
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();
    expect(firstBuilds[2], isFalse, reason: 'prepare after motion has settled');
    expect(firstBuilds.length, lessThan(5));
  });

  testWidgets(
    'adjacent playlist is laid out before navigation and retained on return',
    (tester) async {
      final controller = PageController();
      addTearDown(controller.dispose);
      final built = <int>{};
      final keys = List.generate(5, (_) => GlobalKey());
      await tester.pumpWidget(
        MaterialApp(
          home: HomeTabViewport(
            controller: controller,
            itemCount: 5,
            onPageChanged: (_) {},
            itemBuilder: (_, index) {
              built.add(index);
              return SizedBox.expand(
                key: keys[index],
                child: Text('tab $index'),
              );
            },
          ),
        ),
      );
      await tester.pump();
      expect(built, containsAll([0, 1]));
      expect(
        built.length,
        lessThan(5),
        reason: 'bounded adjacent preparation, not all pages',
      );
      final playlist = keys[1].currentContext;
      expect(playlist, isNotNull);
      expect(
        find.ancestor(
          of: find.byKey(keys[1], skipOffstage: false),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
      final navigation = controller.animateToPage(
        1,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          keys[1].currentContext,
          same(playlist),
          reason: 'no empty replacement frame during slide',
        );
      }
      await tester.pumpAndSettle();
      await navigation;
      controller.jumpToPage(0);
      await tester.pumpAndSettle();
      controller.jumpToPage(1);
      await tester.pumpAndSettle();
      expect(keys[1].currentContext, same(playlist));
    },
  );
}
