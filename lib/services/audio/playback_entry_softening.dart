import 'dart:async';
import 'dart:math' as math;

const playbackEntrySofteningDuration = Duration(milliseconds: 480);

double playbackEntryTrebleDb(double progress) {
  final t = progress.clamp(0.0, 1.0);
  if (t == 0) return -6;
  if (t == 1) return 0;
  return -3 * (1 + math.cos(math.pi * t));
}

/// Brief high-shelf attenuation; no full-band volume reduction.
class PlaybackEntrySoftening {
  PlaybackEntrySoftening(this.write);
  final Future<void> Function(double) write;
  int _generation = 0;
  bool _armed = false, _playing = false, _disposed = false, _supported = true;
  Timer? _timer;
  final _clock = Stopwatch();
  bool _draining = false;
  double? _pendingGain;
  int _pendingGeneration = 0;
  List<Completer<void>> _pendingWaiters = [];

  Future<void> _send(double gain, int generation) {
    final completion = Completer<void>();
    _pendingGain = gain;
    _pendingGeneration = generation;
    _pendingWaiters.add(completion);
    if (!_draining) unawaited(_drain());
    return completion.future;
  }

  Future<void> _drain() async {
    _draining = true;
    while (_pendingGain != null) {
      final gain = _pendingGain!, generation = _pendingGeneration;
      final waiters = _pendingWaiters;
      _pendingGain = null;
      _pendingWaiters = [];
      if (!_disposed && generation == _generation && _supported) {
        try {
          await write(gain);
        } catch (_) {
          _supported = false;
          _armed = false;
          _timer?.cancel();
          _timer = null;
          _clock.stop();
          if (!_disposed) {
            try {
              await write(0);
            } catch (_) {
              // Optional native tone-filter support.
            }
          }
        }
      }
      for (final waiter in waiters) {
        waiter.complete();
      }
    }
    _draining = false;
  }

  Future<void> prepare() async {
    final generation = ++_generation;
    _timer?.cancel();
    _timer = null;
    _clock.stop();
    _clock.reset();
    _armed = false;
    await _send(-6, generation);
  }

  void begin({required bool playing}) {
    if (_disposed || !_supported) return;
    _armed = true;
    setPlaying(playing);
  }

  void setPlaying(bool playing) {
    _playing = playing;
    if (!_armed || _disposed || !_supported) return;
    if (!playing) {
      _clock.stop();
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_timer != null) return;
    _clock.start();
    final generation = _generation;
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_disposed || generation != _generation || !_playing) {
        _timer?.cancel();
        return;
      }
      final t =
          _clock.elapsedMicroseconds /
          playbackEntrySofteningDuration.inMicroseconds;
      unawaited(_send(playbackEntryTrebleDb(t), generation));
      if (t >= 1) {
        _armed = false;
        _timer?.cancel();
        _timer = null;
        _clock.stop();
      }
    });
  }

  Future<void> cancel({bool restore = true}) async {
    final generation = ++_generation;
    _armed = false;
    _timer?.cancel();
    _timer = null;
    _clock.stop();
    _clock.reset();
    if (restore) await _send(0, generation);
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _clock.stop();
  }
}
