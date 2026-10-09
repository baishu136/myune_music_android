part of 'mobile_lyrics_list.dart';

enum KaraokeSourceUpdate { continuous, stale, discontinuity }

/// Explicit seeks bypass this filter. Ordinary samples may arrive late or out
/// of order; a moderate isolated outlier must not install a seek lock.
class KaraokePositionSampleTracker {
  Duration? _source, _stamp, _candidate, _candidateStamp;

  void reset(Duration source, Duration stamp) {
    _source = source;
    _stamp = stamp;
    _candidate = _candidateStamp = null;
  }

  KaraokeSourceUpdate observe(Duration source, Duration stamp, double rate) {
    final previous = _source, previousStamp = _stamp;
    if (previous == null || previousStamp == null) {
      reset(source, stamp);
      return KaraokeSourceUpdate.continuous;
    }
    final elapsed = math.max(0, (stamp - previousStamp).inMicroseconds);
    final delta = (source - previous).inMicroseconds;
    final drift = delta - elapsed * rate;
    if (delta <= 0 && delta >= -250000) return KaraokeSourceUpdate.stale;
    if (drift.abs() <= 420000 && delta >= 0) {
      reset(source, stamp);
      return KaraokeSourceUpdate.continuous;
    }
    final candidate = _candidate, candidateStamp = _candidateStamp;
    final confirmed =
        candidate != null &&
        candidateStamp != null &&
        ((source - candidate).inMicroseconds -
                    math.max(0, (stamp - candidateStamp).inMicroseconds) * rate)
                .abs() <=
            160000;
    if (drift.abs() > 1000000 || confirmed) {
      reset(source, stamp);
      return KaraokeSourceUpdate.discontinuity;
    }
    _candidate = source;
    _candidateStamp = stamp;
    return KaraokeSourceUpdate.stale;
  }
}

/// One media-time clock for the active lyric. The ticker only supplies wall
/// elapsed time; a frame never integrates glyph displacement. Native position
/// updates correct small drift, while explicit seeks replace the anchor.
class KaraokeMediaClock extends ValueNotifier<Duration> {
  KaraokeMediaClock(super.value, {double rate = 1})
    : _rate = rate,
      _anchor = value {
    _samples.reset(value, Duration.zero);
  }

  double _rate;
  bool _running = false;
  Duration _anchor;
  final _samples = KaraokePositionSampleTracker();
  Duration _lastElapsed = Duration.zero;
  Duration _anchorElapsed = Duration.zero;
  Duration _seekGuardUntil = Duration.zero;

  void setRunning(bool running, Duration source) {
    if (_running == running) return;
    _running = running;
    final remainingGuard = _seekGuardUntil - _lastElapsed;
    _lastElapsed = Duration.zero;
    _anchorElapsed = Duration.zero;
    _seekGuardUntil = remainingGuard > Duration.zero
        ? remainingGuard
        : Duration.zero;
    final stale =
        _seekGuardUntil > Duration.zero &&
        (source - value).inMicroseconds.abs() > 160000;
    _anchor = stale || !running ? value : source;
    _samples.reset(source, Duration.zero);
    // Small final decoder corrections must not rewind a frozen glyph pose.
    // On resume they are handled by the same gradual drift correction as play.
    if (!stale && (source - value).inMicroseconds.abs() > 160000) {
      value = source;
    }
  }

  /// Freeze the current pose for a normal line exit without rewinding it to
  /// the inactive row's pre-start preview position.
  void freeze() => _running = false;

  /// A subscription has its own elapsed origin, even if the shared ticker
  /// keeps running. Preserve the pose and the remaining explicit-seek guard.
  void rebaseElapsed([Duration elapsed = Duration.zero]) {
    final remainingGuard = _seekGuardUntil - _lastElapsed;
    _anchor = value;
    _lastElapsed = _anchorElapsed = elapsed;
    _seekGuardUntil = remainingGuard > Duration.zero
        ? elapsed + remainingGuard
        : elapsed;
    _samples.reset(value, elapsed);
  }

  void changeRate(double rate, Duration source) {
    if (!rate.isFinite || rate <= 0 || _rate == rate) return;
    _rate = rate;
    _anchor = value;
    _anchorElapsed = _lastElapsed;
    _samples.reset(source, _lastElapsed);
  }

  void seek(Duration target, {bool protectFromStaleSource = false}) {
    _anchor = target;
    _anchorElapsed = _lastElapsed;
    _samples.reset(target, _lastElapsed);
    value = target;
    _seekGuardUntil = protectFromStaleSource
        ? _lastElapsed + const Duration(milliseconds: 750)
        : Duration.zero;
  }

  void readSource(Duration source) {
    if (_lastElapsed < _seekGuardUntil &&
        (source - value).inMicroseconds.abs() > 160000) {
      return;
    }
    if (!_running) {
      if ((source - value).inMicroseconds.abs() > 160000) seek(source);
      return;
    }
    final update = _samples.observe(source, _lastElapsed, _rate);
    if (update == KaraokeSourceUpdate.stale) return;
    if (update == KaraokeSourceUpdate.discontinuity) {
      value = source;
    }
    _anchor = source;
    _anchorElapsed = _lastElapsed;
  }

  void tick(Duration elapsed) {
    if (!_running) return;
    if (elapsed < _lastElapsed) {
      rebaseElapsed(elapsed);
      return;
    }
    final delta = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    final target = karaokeVisualClockTarget(
      _anchor,
      elapsed,
      _anchorElapsed,
      _rate,
    );
    // Wall-time gaps still advance media time. A delayed ordinary anchor must
    // never rewind the pose just because one frame took longer than 120ms.
    value = karaokeAdvanceVisualClock(
      value,
      target,
      delta,
      playbackRate: _rate,
    );
  }
}
