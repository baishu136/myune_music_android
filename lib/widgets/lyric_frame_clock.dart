import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// One vsync source for list motion and active karaoke clocks. It sleeps when
/// neither scrolling nor subscribed playback needs frames; no frame snapshots
/// or timer pulses are allocated here. Exits keep their wall-time controller.
class LyricFrameClock extends ChangeNotifier {
  LyricFrameClock(TickerProvider vsync, this.onMotionFrame) {
    _ticker = vsync.createTicker(_tick);
  }

  final void Function(Duration) onMotionFrame;
  late final Ticker _ticker;
  final moving = ValueNotifier(false);
  // Includes row-elastic waves without driving the list a second time.
  final visualMoving = ValueNotifier(false);
  int _elasticRows = 0;
  Duration elapsed = Duration.zero;
  bool _disposed = false;

  void _tick(Duration stamp) {
    elapsed = stamp;
    if (moving.value) onMotionFrame(stamp);
    notifyListeners();
    // Removal during notifyListeners is compacted only after it returns.
    // Re-check here so the last completed row spring really lets vsync sleep.
    _sync();
  }

  void setMoving(bool value) {
    moving.value = value;
    _updateVisualMoving();
    _sync();
  }

  void beginElasticRow() {
    if (_disposed) return;
    _elasticRows++;
    _updateVisualMoving();
  }

  void endElasticRow() {
    if (_disposed) return;
    if (_elasticRows > 0) _elasticRows--;
    _updateVisualMoving();
  }

  void _updateVisualMoving() =>
      visualMoving.value = moving.value || _elasticRows > 0;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _sync();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _sync();
  }

  void _sync() {
    if (_disposed) return;
    if (moving.value || hasListeners) {
      if (!_ticker.isActive) {
        elapsed = Duration.zero;
        _ticker.start();
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    moving.dispose();
    visualMoving.dispose();
    super.dispose();
  }
}
