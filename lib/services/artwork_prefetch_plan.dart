import 'dart:math' as math;

class ArtworkPrefetchPlan {
  const ArtworkPrefetchPlan({
    required this.start,
    required this.end,
    required this.predictedIndex,
  });

  final int start;
  final int end;
  final int predictedIndex;
}

/// Produces a bounded, direction-aware prefetch window. It deliberately uses
/// indices rather than widgets so the plan is reusable by lists and grids.
ArtworkPrefetchPlan planArtworkPrefetch({
  required int itemCount,
  required double pixels,
  required double viewportPixels,
  required double itemExtent,
  required double velocityPixelsPerSecond,
}) {
  if (itemCount <= 0 || itemExtent <= 0 || viewportPixels <= 0) {
    return const ArtworkPrefetchPlan(start: 0, end: 0, predictedIndex: 0);
  }
  final first = (pixels / itemExtent).floor().clamp(0, itemCount - 1);
  final visible = math.max(1, (viewportPixels / itemExtent).ceil());
  final speed = velocityPixelsPerSecond.abs();
  final screens = speed >= 3500
      ? 8
      : speed >= 1400
      ? 6
      : 4;
  final predictedPixels = math.max(
    0.0,
    pixels + velocityPixelsPerSecond * 0.20,
  );
  final predicted = (predictedPixels / itemExtent).round().clamp(
    0,
    itemCount - 1,
  );
  final forward = velocityPixelsPerSecond >= 0;
  final baseStart = forward ? first - visible : first - visible * screens;
  final baseEnd = forward
      ? first + visible * (screens + 1)
      : first + visible * 2;
  final radius = visible * 2;
  return ArtworkPrefetchPlan(
    start: math.max(0, math.min(baseStart, predicted - radius)),
    end: math.min(itemCount, math.max(baseEnd, predicted + radius + 1)),
    predictedIndex: predicted,
  );
}
