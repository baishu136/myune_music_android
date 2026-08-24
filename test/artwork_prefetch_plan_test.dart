import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/services/artwork_prefetch_plan.dart';

void main() {
  test('fast forward fling looks farther ahead', () {
    final slow = planArtworkPrefetch(
      itemCount: 1000,
      pixels: 1000,
      viewportPixels: 700,
      itemExtent: 70,
      velocityPixelsPerSecond: 200,
    );
    final fast = planArtworkPrefetch(
      itemCount: 1000,
      pixels: 1000,
      viewportPixels: 700,
      itemExtent: 70,
      velocityPixelsPerSecond: 5000,
    );
    expect(fast.end, greaterThan(slow.end));
    expect(fast.predictedIndex, greaterThan(slow.predictedIndex));
  });

  test('reverse scrolling biases the window toward lower indices', () {
    final plan = planArtworkPrefetch(
      itemCount: 1000,
      pixels: 7000,
      viewportPixels: 700,
      itemExtent: 70,
      velocityPixelsPerSecond: -4000,
    );
    expect(plan.start, lessThan(50));
    expect(plan.end, lessThan(140));
  });
}
