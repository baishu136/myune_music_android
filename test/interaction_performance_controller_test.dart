import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/services/interaction_performance_controller.dart';

void main() {
  final controller = InteractionPerformanceController.instance;

  tearDown(() {
    controller.pulse(InteractionPhase.idle);
  });

  test(
    'short scroll pulses cannot end a route protection window early',
    () async {
      controller.pulse(
        InteractionPhase.transition,
        settleAfter: const Duration(milliseconds: 300),
      );
      controller.pulse(
        InteractionPhase.interacting,
        settleAfter: const Duration(milliseconds: 1),
      );
      await controller.waitForIdle(maxWait: const Duration(milliseconds: 100));
      expect(controller.isCritical, isTrue);
      expect(controller.phase, InteractionPhase.transition);
      await controller.waitForIdle(maxWait: const Duration(milliseconds: 600));
      expect(controller.isCritical, isFalse);
    },
  );

  test('interaction pulse settles without a per-frame UI listener', () async {
    controller.pulse(
      InteractionPhase.fling,
      settleAfter: const Duration(milliseconds: 20),
    );

    expect(controller.isCritical, isTrue);
    await controller.waitForIdle(maxWait: const Duration(milliseconds: 200));
    expect(controller.phase, InteractionPhase.idle);
  });

  test('visual animation defers idle work without freezing fluid motion', () {
    controller.pulse(
      InteractionPhase.visualAnimation,
      settleAfter: const Duration(milliseconds: 20),
    );

    expect(controller.isCritical, isTrue);
    expect(controller.blocksFluidAnimation, isFalse);
  });

  test('visual animation cannot downgrade active transition protection', () {
    controller.pulse(
      InteractionPhase.transition,
      settleAfter: const Duration(milliseconds: 100),
    );
    controller.pulse(
      InteractionPhase.visualAnimation,
      settleAfter: const Duration(milliseconds: 10),
    );

    expect(controller.phase, InteractionPhase.transition);
    expect(controller.blocksFluidAnimation, isTrue);
  });

  test(
    'idle wait has a bounded timeout during continuous interaction',
    () async {
      controller.pulse(
        InteractionPhase.transition,
        settleAfter: const Duration(seconds: 1),
      );
      final stopwatch = Stopwatch()..start();

      await controller.waitForIdle(maxWait: const Duration(milliseconds: 25));

      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(20));
      expect(controller.isCritical, isTrue);
    },
  );

  test('deferred work leases are serialized across frames', () async {
    final first = await controller.acquireIdleWork();
    var secondGranted = false;
    final secondFuture = controller.acquireIdleWork().then((lease) {
      secondGranted = true;
      return lease;
    });

    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(secondGranted, isFalse);

    first.release();
    final second = await secondFuture.timeout(
      const Duration(milliseconds: 200),
    );
    second.release();
  });

  test('current visual work overtakes background work while queued', () async {
    controller.pulse(
      InteractionPhase.transition,
      settleAfter: const Duration(milliseconds: 25),
    );
    var backgroundGranted = false;
    final backgroundFuture = controller
        .acquireIdleWork(priority: InteractionWorkPriority.background)
        .then((lease) {
          backgroundGranted = true;
          return lease;
        });
    final visual = await controller
        .acquireIdleWork(priority: InteractionWorkPriority.currentVisual)
        .timeout(const Duration(milliseconds: 200));

    expect(backgroundGranted, isFalse);
    visual.release();
    final background = await backgroundFuture.timeout(
      const Duration(milliseconds: 200),
    );
    background.release();
  });

  test('cancelled queued work does not consume a frame lease', () async {
    controller.pulse(
      InteractionPhase.transition,
      settleAfter: const Duration(milliseconds: 25),
    );
    final cancelled = controller.acquireIdleWork(
      priority: InteractionWorkPriority.currentVisual,
      isStillNeeded: () => false,
    );
    final retained = controller.acquireIdleWork(
      priority: InteractionWorkPriority.userVisible,
    );

    final leases = await Future.wait([
      cancelled,
      retained,
    ]).timeout(const Duration(milliseconds: 200));
    leases[0].release();
    leases[1].release();
  });
}
