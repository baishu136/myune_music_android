import 'dart:typed_data';

/// Continuous estimated advance across adjacent synthetic tokens. PCHIP
/// tangents keep velocity continuous and avoid overshoot when widths/cadence
/// differ. Built once per physical row; never changes real token timestamps.
class KaraokeSweepTimeline {
  KaraokeSweepTimeline(
    List<({int startUs, int endUs, double advance})> segments,
  ) {
    if (segments.isEmpty) throw ArgumentError('An empty sweep has no timeline');
    final count = segments.length;
    _times = Int64List(count + 1);
    _distances = Float64List(count + 1);
    _slopes = Float64List(count + 1);
    final durations = Float64List(count);
    final speeds = Float64List(count);
    _times[0] = segments.first.startUs;
    for (var i = 0; i < count; i++) {
      final segment = segments[i];
      if (segment.startUs != _times[i] ||
          segment.endUs <= segment.startUs ||
          !segment.advance.isFinite ||
          segment.advance <= 0) {
        throw ArgumentError('Sweep segments must be positive and contiguous');
      }
      _times[i + 1] = segment.endUs;
      _distances[i + 1] = _distances[i] + segment.advance;
      durations[i] = (segment.endUs - segment.startUs).toDouble();
      speeds[i] = segment.advance / durations[i];
    }
    _slopes[0] = speeds[0];
    _slopes[count] = speeds[count - 1];
    for (var i = 1; i < count; i++) {
      final w1 = 2 * durations[i] + durations[i - 1];
      final w2 = durations[i] + 2 * durations[i - 1];
      _slopes[i] = (w1 + w2) / (w1 / speeds[i - 1] + w2 / speeds[i]);
    }
  }

  late final Int64List _times;
  late final Float64List _distances;
  late final Float64List _slopes;

  double phaseAt(int mediaUs) {
    if (mediaUs <= _times[0]) return 0;
    if (mediaUs >= _times.last) return 1;
    var low = 0;
    var high = _times.length - 2;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (mediaUs >= _times[mid + 1]) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final duration = (_times[low + 1] - _times[low]).toDouble();
    final t = (mediaUs - _times[low]) / duration;
    final t2 = t * t;
    final t3 = t2 * t;
    final distance =
        (2 * t3 - 3 * t2 + 1) * _distances[low] +
        (t3 - 2 * t2 + t) * duration * _slopes[low] +
        (-2 * t3 + 3 * t2) * _distances[low + 1] +
        (t3 - t2) * duration * _slopes[low + 1];
    return (distance / _distances.last).clamp(0.0, 1.0);
  }
}
