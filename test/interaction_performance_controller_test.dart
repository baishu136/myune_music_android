import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/services/interaction_performance_controller.dart';

void main() {
  final controller = InteractionPerformanceController.instance;

  test(
    'cancelled owner releases queued work without releasing another owner',
    () async {
      final guard = controller.beginTransition();
      bool needed() => true;
      final pending = controller.acquireIdleWork(isStillNeeded: needed);
      controller.cancelIdleWork(needed);
      expect((await pending).isGranted, isFalse);
      expect(controller.isCritical, isTrue);
      guard.release();
      final next = await controller.acquireIdleWork();
      expect(next.isGranted, isTrue);
      next.release();
    },
  );

  tearDown(() {
    controller.pulse(InteractionPhase.idle);
  });

  test(
    'owned entrance defers work without leaving a fixed settle tail',
    () async {
      final entrance = controller.beginVisualAnimation();
      addTearDown(entrance.release);
      expect(controller.isCritical, isTrue);
      expect(controller.blocksFluidAnimation, isFalse);
      final route = controller.beginTransition();
      expect(controller.blocksFluidAnimation, isTrue);
      route.release();
      expect(controller.phase, InteractionPhase.visualAnimation);
      entrance.release();
      final work = await controller.acquireIdleWork().timeout(
        const Duration(milliseconds: 100),
      );
      expect(controller.isCritical, isFalse);
      work.release();
    },
  );

  test(
    'newly selected target is promoted even while waiting for a lease',
    () async {
      final active = await controller.acquireIdleWork();
      var requested = false, backgroundGranted = false;
      final backgroundFuture = controller.acquireIdleWork().then((lease) {
        backgroundGranted = true;
        return lease;
      });
      final targetFuture = controller.acquireIdleWork(
        priority: InteractionWorkPriority.maintenance,
        priorityForWork: () => requested
            ? InteractionWorkPriority.userVisible
            : InteractionWorkPriority.maintenance,
      );
      requested = true;
      active.release();
      final target = await targetFuture.timeout(
        const Duration(milliseconds: 200),
      );
      expect(backgroundGranted, isFalse);
      target.release();
      final background = await backgroundFuture.timeout(
        const Duration(milliseconds: 200),
      );
      background.release();
    },
  );

  test('pending resource does not hold the idle publication queue', () async {
    final started = Completer<void>();
    final resource = Completer<int>();
    var completed = false;
    final pending = controller
        .runIdleResource<int>(() {
          started.complete();
          return resource.future;
        })
        .then((value) {
          completed = true;
          return value;
        });
    await started.future;
    final visible = await controller
        .acquireIdleWork(priority: InteractionWorkPriority.currentVisual)
        .timeout(const Duration(milliseconds: 200));
    expect(completed, isFalse);
    visible.release();
    resource.complete(42);
    expect(await pending, 42);
  });

  test('transition owners cannot release another route or gesture', () async {
    final first = controller.beginTransition();
    final second = controller.beginTransition();
    addTearDown(first.release);
    addTearDown(second.release);
    controller.pulse(InteractionPhase.idle);
    first.release();
    expect(controller.isCritical, isTrue);
    expect(controller.blocksFluidAnimation, isTrue);
    controller.pulse(
      InteractionPhase.interacting,
      settleAfter: const Duration(milliseconds: 80),
    );
    second.release();
    expect(controller.isCritical, isTrue);
    await controller.waitForIdle(maxWait: const Duration(milliseconds: 250));
    expect(controller.isCritical, isFalse);
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
