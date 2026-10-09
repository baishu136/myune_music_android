import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/home_tab_viewport.dart';

Widget host(
  HomeTabController controller, {
  IndexedWidgetBuilder? builder,
  ValueChanged<int>? changed,
  bool scroll = true,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  home: Directionality(
    textDirection: direction,
    child: HomeTabViewport(
      controller: controller,
      itemCount: 5,
      scrollEnabled: scroll,
      onPageChanged: changed ?? (_) {},
      itemBuilder:
          builder ??
          (_, i) =>
              SizedBox.expand(key: ValueKey('page-$i'), child: Text('tab $i')),
    ),
  ),
);

Future<void> start(
  WidgetTester tester,
  HomeTabController controller,
  int target,
) async {
  unawaited(controller.animateToPage(target));
  await tester.pump(); // cold layout, still at initial poses
  await tester.pump(); // establish ticker epoch
}

void main() {
  testWidgets(
    '300ms motion has only endpoints and no animation-frame layouts at 60/90/120Hz',
    (tester) async {
      for (final hz in [60, 90, 120]) {
        final controller = HomeTabController();
        final layouts = List.filled(5, 0), paints = List.filled(5, 0);
        final built = <int>{};
        var notifications = 0;
        controller.addListener(() => notifications++);
        await tester.pumpWidget(
          host(
            controller,
            builder: (_, i) {
              built.add(i);
              return _LayoutProbe(
                key: ValueKey('page-$i'),
                onLayout: () => layouts[i]++,
                onPaint: () => paints[i]++,
              );
            },
          ),
        );
        expect(built, {0});
        await start(tester, controller, 4);
        expect(built, {0, 4});
        final width = tester.getSize(find.byType(HomeTabViewport)).width;
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('page-4'))).dx,
          width,
        );
        final preparedLayouts = List<int>.of(layouts);
        var previous = 0.0;
        for (var frame = 1; frame < (hz * .3).ceil(); frame++) {
          await tester.pump(Duration(microseconds: (1000000 / hz).floor()));
          final x = tester.getTopLeft(find.byKey(const ValueKey('page-0'))).dx;
          final target = tester
              .getTopLeft(find.byKey(const ValueKey('page-4')))
              .dx;
          expect(x, lessThanOrEqualTo(previous + .001));
          expect(
            target - x,
            closeTo(width, .001),
            reason: 'rigid two-page scene, no intermediate page',
          );
          expect(
            (x - previous).abs(),
            lessThan(width * 3 / (hz * .3) + .001),
            reason: 'bounded by the 300ms cubic curve peak velocity',
          );
          expect(
            layouts,
            preparedLayouts,
            reason: 'paint-only animation ticks',
          );
          previous = x;
        }
        expect(controller.isTransitioning, isTrue);
        await tester.pumpAndSettle();
        expect(controller.index, 4);
        expect(controller.isTransitioning, isFalse);
        expect(
          notifications,
          lessThanOrEqualTo(2),
          reason: 'no per-frame global pulse',
        );
        expect(paints[1] + paints[2] + paints[3], 0);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  testWidgets(
    '300ms curve reaches its endpoint, with completion on the next ticker sample',
    (tester) async {
      final controller = HomeTabController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(host(controller));
      await start(tester, controller, 4);
      await tester.pump(const Duration(milliseconds: 299));
      expect(controller.isTransitioning, isTrue);
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('page-4'))).dx,
        closeTo(0, .001),
      );
      // Flutter's interpolation simulation completes after, not at, its limit.
      await tester.pump(const Duration(milliseconds: 1));
      expect(controller.index, 4);
      expect(controller.isTransitioning, isFalse);
      expect(tester.getTopLeft(find.byKey(const ValueKey('page-4'))).dx, 0);
    },
  );

  testWidgets('reversal keeps the exact pose and completes cancelled futures', (
    tester,
  ) async {
    final controller = HomeTabController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller));
    final outward = controller.animateToPage(4);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    final before = tester.getTopLeft(find.byKey(const ValueKey('page-0')));
    final inward = controller.animateToPage(0);
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(const ValueKey('page-0'))), before);
    await tester.pumpAndSettle();
    await outward;
    await inward;
    expect(controller.index, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rapid unrelated taps coalesce latest target without loading discarded tabs',
    (tester) async {
      final controller = HomeTabController();
      addTearDown(controller.dispose);
      final built = <int>{}, changed = <int>[];
      await tester.pumpWidget(
        host(
          controller,
          changed: changed.add,
          builder: (_, i) {
            built.add(i);
            return SizedBox.expand(key: ValueKey('page-$i'));
          },
        ),
      );
      await start(tester, controller, 4);
      await tester.pump(const Duration(milliseconds: 100));
      final discarded = controller.animateToPage(1);
      final latest = controller.animateToPage(2);
      await tester.pumpAndSettle();
      await discarded;
      await latest;
      expect(built, {0, 4, 2});
      expect(changed, [4, 2]);
      expect(controller.index, 2);
    },
  );

  testWidgets(
    'visited list retains State and scroll; hidden page ticker/layout stay idle',
    (tester) async {
      final controller = HomeTabController();
      addTearDown(controller.dispose);
      final keys = List.generate(5, (_) => GlobalKey<_ListProbeState>());
      final layouts = List.filled(5, 0), paints = List.filled(5, 0);
      await tester.pumpWidget(
        host(
          controller,
          builder: (_, i) => _LayoutProbe(
            onLayout: () => layouts[i]++,
            onPaint: () => paints[i]++,
            child: _ListProbe(key: keys[i]),
          ),
        ),
      );
      final original = keys[0].currentState!;
      original.scroll.jumpTo(160);
      await tester.pump();
      controller.jumpToPage(4);
      await tester.pump();
      final hiddenTicks = original.ticks,
          hiddenLayouts = layouts[0],
          hiddenPaints = paints[0];
      await start(tester, controller, 2);
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(original.ticks, hiddenTicks);
      expect(layouts[0], hiddenLayouts);
      expect(paints[0], hiddenPaints);
      controller.jumpToPage(0);
      await tester.pump();
      expect(keys[0].currentState, same(original));
      expect(original.scroll.offset, 160);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'controller replacement/unmount cancels outstanding requests safely',
    (tester) async {
      final first = HomeTabController(),
          second = HomeTabController(initialPage: 2);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await tester.pumpWidget(host(first));
      final pending = first.animateToPage(4);
      await tester.pump();
      await tester.pumpWidget(host(second));
      await pending;
      expect(first.hasClients, isFalse);
      expect(second.index, 2);
      final cancelled = second.animateToPage(0);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await cancelled;
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'horizontal drag follows finger, vertical scroll and selection isolation survive',
    (tester) async {
      final controller = HomeTabController();
      addTearDown(controller.dispose);
      final lists = List.generate(5, (_) => GlobalKey<_ListProbeState>());
      Widget page(BuildContext _, int i) => _ListProbe(key: lists[i]);
      await tester.pumpWidget(host(controller, builder: page));
      await tester.drag(find.byType(HomeTabViewport), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(lists[0].currentState!.scroll.offset, greaterThan(0));
      expect(controller.index, 0);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(HomeTabViewport)),
      );
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-250, 0));
      await tester.pump();
      expect(controller.isTransitioning, isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.index, 1);
      await tester.pumpWidget(host(controller, scroll: false, builder: page));
      await tester.drag(find.byType(HomeTabViewport), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(controller.index, 1);
      expect(lists[2].currentState, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'RTL far navigation is mirrored and semantics exclude hidden pages',
    (tester) async {
      final controller = HomeTabController();
      addTearDown(controller.dispose);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(controller, direction: TextDirection.rtl));
      await start(tester, controller, 4);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('page-4'))).dx,
        lessThan(0),
      );
      await tester.pump(const Duration(milliseconds: 180));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('page-0'))).dx,
        greaterThan(0),
      );
      await tester.pumpAndSettle();
      expect(find.text('tab 0'), findsNothing);
      expect(find.text('tab 0', skipOffstage: false), findsOneWidget);
      expect(tester.getSemantics(find.text('tab 4')).label, 'tab 4');
      semantics.dispose();
    },
  );
}

class _LayoutProbe extends SingleChildRenderObjectWidget {
  const _LayoutProbe({
    super.key,
    required this.onLayout,
    required this.onPaint,
    super.child,
  });
  final VoidCallback onLayout, onPaint;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderProbe(onLayout, onPaint);
}

class _RenderProbe extends RenderProxyBox {
  _RenderProbe(this.onLayout, this.onPaint);
  final VoidCallback onLayout, onPaint;
  @override
  void performLayout() {
    onLayout();
    super.performLayout();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    super.paint(context, offset);
  }
}

class _ListProbe extends StatefulWidget {
  const _ListProbe({super.key});
  @override
  State<_ListProbe> createState() => _ListProbeState();
}

class _ListProbeState extends State<_ListProbe>
    with SingleTickerProviderStateMixin {
  final scroll = ScrollController();
  late final AnimationController clock;
  var ticks = 0;
  @override
  void initState() {
    super.initState();
    clock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(() => ticks++);
    // Finite motion lets pumpAndSettle finish; hidden ticker still must mute.
    clock.forward();
  }

  @override
  void dispose() {
    scroll.dispose();
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    controller: scroll,
    children: const [SizedBox(height: 3000, child: Text('scrollable'))],
  );
}
