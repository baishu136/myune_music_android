import 'dart:math' as math;

/// One source projection for line focus, scrolling, glyph motion and translation.
/// Corrects small native clock jitter, never estimates wireless acoustic latency.
class LyricVisualTimeline {
  Duration? _source, _visual, _wall;
  double _rate = 1;
  bool _running = false;
  void reset() {
    _source = _visual = _wall = null;
  }

  Duration sample(
    Duration source,
    Duration wall, {
    required bool running,
    required double rate,
    required bool automatic,
  }) {
    if (!rate.isFinite || rate <= 0) rate = 1;
    if (_source == source && _running == running && _rate == rate) {
      return _visual ?? source;
    }
    final previous = _visual;
    final elapsed = _wall == null ? 0 : (wall - _wall!).inMicroseconds;
    var next = source;
    if (automatic &&
        running &&
        _running &&
        rate == _rate &&
        previous != null &&
        elapsed > 0 &&
        elapsed < 1000000) {
      final expected = previous.inMicroseconds + elapsed * rate;
      final error = source.inMicroseconds - expected;
      // Explicit seeks and buffer discontinuities must locate immediately.
      if (error.abs() < 120000 && (_source! - source).inMilliseconds < 100) {
        final step = elapsed * rate;
        final adjusted = expected + error.clamp(-step * .08, step * .08);
        next = Duration(
          microseconds: math.max(previous.inMicroseconds, adjusted.round()),
        );
      }
    }
    _source = source;
    _visual = next;
    _wall = wall;
    _running = running;
    _rate = rate;
    return next;
  }
}
