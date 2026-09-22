part of 'mobile_lyrics_list.dart';

/// One media-time clock for the active lyric. The ticker only supplies wall
/// elapsed time; a frame never integrates glyph displacement. Native position
/// updates correct small drift, while explicit seeks replace the anchor.
class KaraokeMediaClock extends ValueNotifier<Duration> {
  KaraokeMediaClock(super.value, {double rate = 1})
    : _rate = rate,
      _anchor = value,
      _lastSource = value;

  double _rate;
  bool _running = false;
  Duration _anchor;
  Duration _lastSource;
  Duration _lastElapsed = Duration.zero;
  Duration _anchorElapsed = Duration.zero;
  Duration _lastSourceElapsed = Duration.zero;

  void setRunning(bool running, Duration source) {
    if (_running == running) return;
    _running = running;
    _lastElapsed = Duration.zero;
    _anchorElapsed = Duration.zero;
    _lastSourceElapsed = Duration.zero;
    _anchor = source;
    _lastSource = source;
    value = source;
  }

  /// Freeze the current pose for a normal line exit without rewinding it to
  /// the inactive row's pre-start preview position.
  void freeze() => _running = false;

  void changeRate(double rate, Duration source) {
    if (!rate.isFinite || rate <= 0 || _rate == rate) return;
    _rate = rate;
    _anchor = value;
    _anchorElapsed = _lastElapsed;
    _lastSource = source;
    _lastSourceElapsed = _lastElapsed;
  }

  void seek(Duration target) {
    _anchor = target;
    _anchorElapsed = _lastElapsed;
    _lastSource = target;
    _lastSourceElapsed = _lastElapsed;
    value = target;
  }

  void readSource(Duration source) {
    if (!_running) {
      seek(source);
      return;
    }
    final elapsed = _lastElapsed - _lastSourceElapsed;
    final discontinuity = karaokePlaybackPositionDiscontinuity(
      previousSource: _lastSource,
      source: source,
      elapsedSinceSource: elapsed,
      playbackRate: _rate,
    );
    if (discontinuity ||
        (source.inMicroseconds - value.inMicroseconds).abs() > 420000) {
      value = source;
    }
    _anchor = source;
    _anchorElapsed = _lastElapsed;
    _lastSource = source;
    _lastSourceElapsed = _lastElapsed;
  }

  void tick(Duration elapsed) {
    if (!_running) return;
    final delta = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    final target = karaokeVisualClockTarget(
      _anchor,
      elapsed,
      _anchorElapsed,
      _rate,
    );
    if (delta > const Duration(milliseconds: 120) ||
        (target.inMicroseconds - value.inMicroseconds).abs() > 420000) {
      value = target;
      return;
    }
    value = karaokeAdvanceVisualClock(
      value,
      target,
      delta,
      playbackRate: _rate,
    );
  }
}
