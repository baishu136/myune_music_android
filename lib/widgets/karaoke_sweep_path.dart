import 'dart:math' as math;
import 'dart:typed_data';

/// Cached visual advance, excluding blank gaps. This changes only where a
/// feathered highlight front is drawn, never a source token's timestamps or
/// the shaped text/ink coverage. No allocations in the frame-time queries.
class KaraokeSweepPath {
  KaraokeSweepPath(Iterable<({double start, double end})> spans) {
    final ordered =
        spans
            .where((s) => s.start.isFinite && s.end.isFinite && s.end > s.start)
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    final merged = <({double start, double end})>[];
    for (final span in ordered) {
      if (merged.isNotEmpty && span.start <= merged.last.end) {
        final previous = merged.removeLast();
        merged.add((
          start: previous.start,
          end: math.max(previous.end, span.end),
        ));
      } else {
        merged.add(span);
      }
    }
    _spans = Float64List(merged.length * 3);
    var advance = 0.0;
    for (var i = 0; i < merged.length; i++) {
      final span = merged[i];
      advance += span.end - span.start;
      _spans[i * 3] = span.start;
      _spans[i * 3 + 1] = span.end;
      _spans[i * 3 + 2] = advance;
    }
    length = advance;
  }

  late final Float64List _spans;
  late final double length;

  /// Layout-time composition only; frame-time queries use the packed buffer.
  Iterable<({double start, double end})> get spans sync* {
    for (var i = 0; i < _spans.length; i += 3) {
      yield (start: _spans[i], end: _spans[i + 1]);
    }
  }

  double distanceBefore(double x) {
    var result = 0.0;
    for (var i = 0; i < _spans.length; i += 3) {
      if (x <= _spans[i]) break;
      result += (x - _spans[i]).clamp(0.0, _spans[i + 1] - _spans[i]);
    }
    return result;
  }

  double frontAt(double phase, double feather, {bool rtl = false}) {
    if (_spans.isEmpty) return 0;
    final directionPhase = rtl ? 1 - phase : phase;
    final distance =
        (length + feather) * directionPhase.clamp(0.0, 1.0) - feather / 2;
    if (distance <= 0) return _spans[0] + distance;
    if (distance >= length) {
      return _spans[_spans.length - 2] + distance - length;
    }
    var low = 0;
    var high = _spans.length ~/ 3 - 1;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (distance >= _spans[mid * 3 + 2]) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final previous = low == 0 ? 0.0 : _spans[low * 3 - 1];
    return _spans[low * 3] + distance - previous;
  }
}
