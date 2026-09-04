import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/theme/theme_motion.dart';

void main() {
  test('theme color transition lasts exactly 180 milliseconds', () {
    expect(ThemeMotion.transitionDuration, const Duration(milliseconds: 180));
  });

  test('theme color curve is continuous and visibly slow-fast-slow', () {
    const curve = ThemeMotion.transitionCurve;
    expect(curve.transform(0), 0);
    expect(curve.transform(1), 1);

    final earlyTravel = curve.transform(.1) - curve.transform(0);
    final middleTravel = curve.transform(.55) - curve.transform(.45);
    final lateTravel = curve.transform(1) - curve.transform(.9);
    expect(middleTravel, greaterThan(earlyTravel * 4));
    expect(middleTravel, greaterThan(lateTravel * 4));

    var previous = 0.0;
    for (var step = 1; step <= 20; step++) {
      final value = curve.transform(step / 20);
      expect(value, inInclusiveRange(previous, 1));
      previous = value;
    }
  });
}
