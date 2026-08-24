import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/services/interaction_performance_controller.dart';

void main() {
  final controller = InteractionPerformanceController.instance;

  tearDown(() {
    controller.pulse(InteractionPhase.idle);
  });

  test('interaction pulse settles without a per-frame UI listener', () async {
    controller.pulse(
      InteractionPhase.fling,
      settleAfter: const Duration(milliseconds: 20),
    );

    expect(controller.isCritical, isTrue);
    await controller.waitForIdle(maxWait: const Duration(milliseconds: 200));
    expect(controller.phase, InteractionPhase.idle);
  });

  test('idle wait has a bounded timeout during continuous interaction', () async {
    controller.pulse(
      InteractionPhase.transition,
      settleAfter: const Duration(seconds: 1),
    );
    final stopwatch = Stopwatch()..start();

    await controller.waitForIdle(maxWait: const Duration(milliseconds: 25));

    expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(20));
    expect(controller.isCritical, isTrue);
  });
}
