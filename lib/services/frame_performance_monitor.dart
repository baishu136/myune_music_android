import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Debug/profile-only frame timing summary. Release builds pay no callback or
/// allocation cost, while development builds expose regressions in build and
/// raster time without changing production behaviour.
class FramePerformanceMonitor {
  FramePerformanceMonitor._();

  static const int _sampleSize = 240;
  static bool _started = false;
  static final List<double> _buildTimesMs = <double>[];
  static final List<double> _rasterTimesMs = <double>[];

  static void start() {
    if (_started || !(kDebugMode || kProfileMode)) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_record);
  }

  static void _record(List<FrameTiming> timings) {
    for (final timing in timings) {
      _buildTimesMs.add(timing.buildDuration.inMicroseconds / 1000);
      _rasterTimesMs.add(timing.rasterDuration.inMicroseconds / 1000);
    }
    if (_buildTimesMs.length < _sampleSize) return;

    final build = List<double>.of(_buildTimesMs)..sort();
    final raster = List<double>.of(_rasterTimesMs)..sort();
    final count = build.length;
    final p95Index = ((count - 1) * .95).round();
    final buildOverBudget = build.where((value) => value > 16.67).length;
    final rasterOverBudget = raster.where((value) => value > 16.67).length;
    debugPrint(
      '[FramePerf] frames=$count '
      'buildP95=${build[p95Index].toStringAsFixed(2)}ms '
      'buildMax=${build.last.toStringAsFixed(2)}ms '
      'buildOver16.67=$buildOverBudget '
      'rasterP95=${raster[p95Index].toStringAsFixed(2)}ms '
      'rasterMax=${raster.last.toStringAsFixed(2)}ms '
      'rasterOver16.67=$rasterOverBudget',
    );
    _buildTimesMs.clear();
    _rasterTimesMs.clear();
  }
}
