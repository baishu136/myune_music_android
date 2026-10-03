import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/lyric_scroll_motion.dart';

void main() {
  test('rest launch accelerates gently and is frame-rate independent', () {
    final offsets = <double>[];
    for (final hz in [60, 90, 120]) {
      final motion = LyricScrollMotion()..sync(0, viewportExtent: 600);
      motion.retarget(200, launchFromRest: true);
      expect(motion.velocity.abs(), lessThanOrEqualTo(200));
      final initialVelocity = motion.velocity;
      motion.advance(1 / hz);
      expect(motion.velocity, greaterThan(initialVelocity));
      for (var i = 1; i < hz ~/ 3; i++) {
        motion.advance(1 / hz);
      }
      offsets.add(motion.offset);
      final speed = motion.velocity;
      motion.retarget(260, launchFromRest: true);
      expect(motion.velocity, speed);
      motion.sync(420);
      expect(motion.velocity, 0);
      expect(motion.advance(1 / hz), 420);
    }
    expect(offsets[0], closeTo(offsets[1], 1e-8));
    expect(offsets[0], closeTo(offsets[2], 1e-8));
  });

  test('60/90/120 Hz retain a long tail rather than stopping at 250 ms', () {
    for (final hz in [60, 90, 120]) {
      final motion = LyricScrollMotion()..sync(0, viewportExtent: 600);
      motion.retarget(200, launchFromRest: true);
      var frame = 0;
      while (++frame <= hz ~/ 4) {
        motion.advance(1 / hz);
      }
      expect(motion.offset / 200, lessThan(.75));
      expect(motion.isSettled, isFalse);
      while (frame++ <= (hz * .52).round()) {
        motion.advance(1 / hz);
      }
      expect(motion.offset / 200, inInclusiveRange(.94, .97));
      expect(motion.velocity, greaterThan(1.2));
      var previous = motion.offset;
      while (!motion.isSettled && frame++ < hz * 2) {
        final speed = motion.velocity;
        motion.advance(1 / hz);
        // Settling may only remove subpixel displacement and tiny velocity.
        if (motion.isSettled) expect(speed.abs(), lessThan(2.0));
        expect((motion.offset - previous).abs(), lessThan(2.0));
        previous = motion.offset;
      }
      expect(motion.isSettled, isTrue);
    }
  });

  test('rapid lyric targets preserve velocity and latest target wins', () {
    final motion = LyricScrollMotion()..sync(0, viewportExtent: 600);
    motion.retarget(240, viewportExtent: 600);
    for (var frame = 0; frame < 6; frame++) {
      motion.advance(1 / 120);
    }

    final offsetBeforeRetarget = motion.offset;
    final velocityBeforeRetarget = motion.velocity;
    expect(offsetBeforeRetarget, greaterThan(0));
    expect(velocityBeforeRetarget, greaterThan(0));

    motion.retarget(420);
    expect(motion.velocity, velocityBeforeRetarget);
    expect(motion.advance(1 / 120), greaterThan(offsetBeforeRetarget));

    for (var frame = 0; frame < 360 && !motion.isSettled; frame++) {
      motion.advance(1 / 120);
    }
    expect(motion.isSettled, isTrue);
    expect(motion.offset, closeTo(420, .4));
  });

  test('95 percent travel is around 520 ms at actual frame rates', () {
    for (final hz in [60, 90, 120]) {
      final motion = LyricScrollMotion()..sync(0, viewportExtent: 600);
      motion.retarget(200, launchFromRest: true);
      var frame = 0;
      while (motion.offset < 190 && frame < hz * 2) {
        motion.advance(1 / hz);
        frame++;
      }
      expect(
        frame / hz,
        inInclusiveRange(.48, .53 + 1 / hz),
        reason: 'first rendered 95% sample may be one vsync after the crossing',
      );
      expect(
        motion.isSettled,
        isFalse,
        reason: '95% travel is not a hard stop',
      );
    }
  });

  test('a delayed frame remains finite and converges without overshoot', () {
    final motion = LyricScrollMotion()..sync(80, viewportExtent: 500);
    motion.retarget(900);

    final delayedFrameOffset = motion.advance(.4);
    expect(delayedFrameOffset.isFinite, isTrue);
    expect(delayedFrameOffset, inInclusiveRange(80, 900));

    for (var frame = 0; frame < 360 && !motion.isSettled; frame++) {
      motion.advance(1 / 90);
    }
    expect(motion.offset, closeTo(900, .4));
    expect(motion.velocity, closeTo(0, 4));
  });

  test('motion dynamics can slow large typography without resetting state', () {
    final motion = LyricScrollMotion()..sync(40, viewportExtent: 300);
    motion.retarget(180);
    motion.advance(1 / 60);
    final offset = motion.offset;
    final velocity = motion.velocity;

    motion.updateDynamics(frequency: 7.2);

    expect(motion.offset, offset);
    expect(motion.velocity, velocity);
    expect(motion.target, 180);
    expect(motion.frequency, 7.2);
  });
}
