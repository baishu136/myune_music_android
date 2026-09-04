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

  test('fast fling keeps the prefetch window bounded around its target', () {
    final plan = planArtworkPrefetch(
      itemCount: 10000,
      pixels: 35000,
      viewportPixels: 700,
      itemExtent: 70,
      velocityPixelsPerSecond: 6000,
    );
    expect(plan.end - plan.start, lessThanOrEqualTo(100));
    expect(plan.predictedIndex, inInclusiveRange(plan.start, plan.end - 1));
  });
}
