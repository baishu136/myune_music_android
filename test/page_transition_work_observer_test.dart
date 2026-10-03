import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/services/interaction_performance_controller.dart';
import 'package:myune_music/services/page_transition_work_observer.dart';

void main() {
  testWidgets(
    'all detail pushes/pops protect background work without UI signals',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final work = InteractionPerformanceController.instance;
      work.endPhase(work.phase);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          navigatorObservers: [PageTransitionWorkObserver()],
          home: const Scaffold(body: Text('home')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(work.isCritical, isFalse);
      var granted = false;
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('detail')),
        ),
      );
      expect(work.blocksFluidAnimation, isTrue);
      final lease = work.acquireIdleWork().then((value) {
        granted = value.isGranted;
        value.release();
      });
      await tester.pump(const Duration(milliseconds: 150));
      expect(granted, isFalse);
      await tester.pumpAndSettle();
      work.endPhase(work.phase);
      await tester.pump(const Duration(seconds: 1));
      await lease;
      expect(granted, isTrue);
      nav.currentState!.pop();
      expect(work.phase, InteractionPhase.transition);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      work.endPhase(work.phase);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
