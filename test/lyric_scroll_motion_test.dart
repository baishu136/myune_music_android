import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/lyric_scroll_motion.dart';

void main() {
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
}
