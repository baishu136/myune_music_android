import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/lyric_normalized_motion.dart';

void main() {
  test('ordinary travel ramps once then settles without a creeping tail', () {
    for (final hz in [60, 90, 120]) {
      final motion = LyricNormalizedMotion()..sync(10);
      motion.retarget(210);
      expect(motion.velocity, 0);
      final seconds = motion.transitionDuration.inMicroseconds / 1000000;
      var previous = motion.offset;
      var speed = 0.0;
      for (var frame = 1; frame <= (hz * seconds).ceil(); frame++) {
        motion.advance(1 / hz);
        final t = (frame / hz / seconds).clamp(0.0, 1.0);
        expect(
          motion.offset,
          closeTo(10 + 200 * lyricTransitionCurve.transform(t), 1e-8),
        );
        expect(motion.offset, greaterThanOrEqualTo(previous));
        expect(motion.velocity, greaterThanOrEqualTo(0));
        if (t < 1 / 7) expect(motion.velocity, greaterThan(speed));
        if ((frame - 1) / hz / seconds >= 1 / 7) {
          expect(motion.velocity, lessThanOrEqualTo(speed));
        }
        if (t < 1) expect(motion.isSettled, isFalse);
        if (frame == 1) expect(motion.offset - 10, lessThan(1.5));
        speed = motion.velocity;
        previous = motion.offset;
      }
      expect(motion.offset, 210);
      expect(motion.velocity, 0);
      expect(motion.isSettled, isTrue);
    }
  });

  test(
    'frame cadence and repeated identical retargets do not change progress',
    () {
      final stepped = LyricNormalizedMotion()..retarget(120);
      final direct = LyricNormalizedMotion()..retarget(120);
      for (var i = 0; i < 30; i++) {
        stepped.retarget(120, viewportExtent: 600);
        stepped.advance(1 / 120);
      }
      direct.advance(.25);
      expect(stepped.offset, closeTo(direct.offset, 1e-9));
      expect(stepped.velocity, closeTo(direct.velocity, 1e-9));
      for (var i = 0; i < 30; i++) {
        stepped.retarget(120);
        stepped.advance(1 / 120);
      }
      expect(stepped.isSettled, isTrue);
    },
  );

  test('in-flight target changes preserve position and velocity', () {
    for (final target in [230.0, 110.0]) {
      final motion = LyricNormalizedMotion()..retarget(200);
      motion.advance(.1);
      final position = motion.offset;
      final speed = motion.velocity;
      motion.retarget(target);
      expect(motion.offset, position);
      expect(motion.velocity, closeTo(speed, 1e-8));
      var previous = position;
      for (var i = 0; i < 60; i++) {
        motion.advance(1 / 120);
        expect(motion.offset, inInclusiveRange(previous - 1e-9, target));
        previous = motion.offset;
      }
      expect(motion.isSettled, isTrue);
      expect(motion.offset, target);
      expect(motion.velocity, 0);
    }
  });

  test('negative long travel is bounded and ends at exactly 480 ms', () {
    final motion = LyricNormalizedMotion()..sync(300);
    motion.retarget(100);
    motion.advance(.479);
    expect(motion.offset, inInclusiveRange(100, 101));
    expect(motion.velocity, lessThan(0));
    expect(motion.isSettled, isFalse);
    motion.advance(.001);
    expect(motion.offset, 100);
    expect(motion.velocity, 0);
    expect(motion.isSettled, isTrue);
  });

  test(
    'seek clears the trajectory and the next ordinary move starts fresh',
    () {
      final motion = LyricNormalizedMotion()..retarget(200);
      motion.advance(.08);
      for (final seek in [800.0, 20.0]) {
        motion.sync(seek);
        expect(motion.advance(.1), seek);
        expect(motion.velocity, 0);
        expect(motion.isSettled, isTrue);
        motion.retarget(seek + 40);
        motion.advance(.25);
        expect(
          motion.offset,
          closeTo(seek + 40 * lyricTransitionCurve.transform(.25 / .42), 1e-9),
        );
      }
    },
  );

  test('elapsed wall time is not clamped into a slow spring tail', () {
    final motion = LyricNormalizedMotion()..retarget(200);
    motion.advance(.4);
    expect(motion.offset, greaterThan(197));
    motion.advance(.2);
    expect(motion.isSettled, isTrue);
    expect(motion.offset, 200);
  });

  test('distance duration is bounded, symmetric and not a frame gate', () {
    for (final distance in [1.0, 70.0, 105.0, 140.0, 500.0]) {
      final motion = LyricNormalizedMotion()..retarget(distance);
      final duration = motion.transitionDuration;
      expect(duration.inMilliseconds, inInclusiveRange(420, 480));
      expect(duration, lyricTransitionDurationForDistance(-distance));
      motion.advance((duration.inMicroseconds - 1) / 1000000);
      expect(motion.isSettled, isFalse);
      motion.advance(.000001);
      expect(motion.offset, distance);
      expect(motion.isSettled, isTrue);
    }
    expect(lyricTransitionDurationForDistance(105).inMilliseconds, 450);
  });

  test(
    'curve derivative agrees with actual displacement at all frame rates',
    () {
      for (final hz in [60, 90, 120]) {
        final motion = LyricNormalizedMotion()..retarget(70);
        var previous = 0.0;
        var previousStep = 0.0;
        for (var i = 1; i <= (hz * .42).ceil(); i++) {
          motion.advance(1 / hz);
          final step = motion.offset - previous;
          // Finite differences at real display cadence, not sub-ms samples.
          expect(step, inInclusiveRange(0, 70 * 2 / .42 / hz + 1e-8));
          expect((step - previousStep).abs(), lessThan(3));
          previous = motion.offset;
          previousStep = step;
        }
        expect(previous, 70);
        for (final t in [.02, .1, 1 / 7, .3, .9]) {
          final finite =
              (lyricTransitionCurve.transform(t + 1e-5) -
                  lyricTransitionCurve.transform(t - 1e-5)) /
              2e-5;
          expect(finite, closeTo(lyricTransitionCurve.derivative(t), 1e-6));
        }
      }
    },
  );

  test('invalid inputs cannot contaminate motion', () {
    expect(
      () => LyricNormalizedMotion(duration: Duration.zero),
      throwsRangeError,
    );
    final motion = LyricNormalizedMotion()..retarget(100);
    motion.retarget(double.nan);
    motion.advance(double.infinity);
    expect(motion.offset, 0);
    expect(motion.target, 100);
    motion.advance(.5);
    expect(motion.isSettled, isTrue);
  });
}
