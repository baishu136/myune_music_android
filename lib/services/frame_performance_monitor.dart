import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Debug/profile-only frame timing summary. Release builds pay no callback or
/// allocation cost, while development builds expose regressions in build and
/// raster time without changing production behaviour.
class FramePerformanceMonitor {
  FramePerformanceMonitor._();

  static const int _sampleSize = 240;
  static bool _started = false;
  static final List<double> _frameTimesMs = <double>[];
  static double _buildTotalMs = 0;
  static double _rasterTotalMs = 0;

  static void start() {
    if (_started || !(kDebugMode || kProfileMode)) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_record);
  }

  static void _record(List<FrameTiming> timings) {
    for (final timing in timings) {
      _frameTimesMs.add(timing.totalSpan.inMicroseconds / 1000);
      _buildTotalMs += timing.buildDuration.inMicroseconds / 1000;
      _rasterTotalMs += timing.rasterDuration.inMicroseconds / 1000;
    }
    if (_frameTimesMs.length < _sampleSize) return;

    final sorted = List<double>.of(_frameTimesMs)..sort();
    final count = _frameTimesMs.length;
    final total = _frameTimesMs.fold<double>(0, (sum, value) => sum + value);
    final p95 = sorted[((count - 1) * .95).round()];
    final jankFrames = _frameTimesMs.where((value) => value > 16.67).length;
    debugPrint(
      '[FramePerf] frames=$count avg=${(total / count).toStringAsFixed(2)}ms '
      'p95=${p95.toStringAsFixed(2)}ms max=${sorted.last.toStringAsFixed(2)}ms '
      'build=${(_buildTotalMs / count).toStringAsFixed(2)}ms '
      'raster=${(_rasterTotalMs / count).toStringAsFixed(2)}ms '
      'over16.67ms=$jankFrames',
    );
    _frameTimesMs.clear();
    _buildTotalMs = 0;
    _rasterTotalMs = 0;
  }
}
