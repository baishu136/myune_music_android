import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../models/fluid_background_state.dart';
import 'interaction_performance_controller.dart';

class FluidBackgroundController extends ChangeNotifier {
  FluidBackgroundController({
    required TickerProvider vsync,
    required FluidPalette initialPalette,
    double initialEffectiveTime = 0,
    FluidBackgroundQuality quality = FluidBackgroundQuality.automatic,
  }) : _sourcePalette = initialPalette,
       _targetPalette = initialPalette,
       _effectiveTime = initialEffectiveTime,
       _quality = quality {
    _ticker = vsync.createTicker(_onTick);
  }

  static const _paletteTransition = Duration(milliseconds: 1700);

  late final Ticker _ticker;
  FluidPalette _sourcePalette;
  FluidPalette _targetPalette;
  FluidBackgroundQuality _quality;
  Duration _lastElapsed = Duration.zero;
  Duration _lastPaintElapsed = Duration.zero;
  double _paletteProgress = 1;
  double _motionScale = 0;
  double _rhythmMotionTarget = 1;
  double _rhythmSampleAge = double.infinity;
  double _effectiveTime;
  bool _enabled = false;
  bool _visible = false;
  bool _foreground = true;
  bool _reduceMotion = false;
  bool _routeTransitionActive = true;
  bool _disposed = false;

  FluidPalette get sourcePalette => _sourcePalette;
  FluidPalette get targetPalette => _targetPalette;
  double get paletteProgress => _paletteProgress;
  FluidPalette get currentPalette =>
      FluidPalette.lerp(_sourcePalette, _targetPalette, _paletteProgress);
  double get motionScale => _motionScale;
  double get rhythmMotionTarget => _rhythmMotionTarget;
  double get effectiveTime => _effectiveTime;
  bool get isTicking => _ticker.isActive;

  /// Updates the speed envelope from a lightweight audio-energy estimate.
  /// Values are deliberately bounded here so malformed or unusually hot FFT
  /// frames can never make the full-screen shader unstable.
  void setRhythmMotion(double value) {
    if (_disposed || !value.isFinite) return;
    _rhythmMotionTarget = value.clamp(.68, 1.72);
    _rhythmSampleAge = 0;
  }

  void setPalette(FluidPalette palette) {
    if (_disposed || palette == _targetPalette) return;
    _sourcePalette = FluidPalette.lerp(
      _sourcePalette,
      _targetPalette,
      _paletteProgress,
    );
    _targetPalette = alignFluidPaletteSlots(_sourcePalette, palette);
    _paletteProgress = 0;
    _ensureScheduling();
    notifyListeners();
  }

  void updateOperatingState({
    required bool enabled,
    required bool visible,
    required bool foreground,
    required bool reduceMotion,
    required bool routeTransitionActive,
    required FluidBackgroundQuality quality,
  }) {
    if (_disposed) return;
    final wasRunnable = _canSchedule;
    _enabled = enabled;
    _visible = visible;
    _foreground = foreground;
    _reduceMotion = reduceMotion;
    _routeTransitionActive = routeTransitionActive;
    _quality = quality;
    if (!_canSchedule) {
      _ticker.stop();
      _lastElapsed = Duration.zero;
      if (_reduceMotion) _motionScale = 0;
      return;
    }
    if (!wasRunnable || !_ticker.isActive) _ensureScheduling();
  }

  bool get _canSchedule =>
      _enabled &&
      _visible &&
      _foreground &&
      !_reduceMotion &&
      !_routeTransitionActive;

  void _ensureScheduling() {
    if (!_canSchedule || _ticker.isActive) return;
    _lastElapsed = Duration.zero;
    _lastPaintElapsed = Duration.zero;
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    if (!_canSchedule) {
      _ticker.stop();
      return;
    }
    final previous = _lastElapsed;
    _lastElapsed = elapsed;
    if (previous == Duration.zero) return;
    final frameSeconds = ((elapsed - previous).inMicroseconds / 1000000).clamp(
      0.0,
      .05,
    );

    if (InteractionPerformanceController.instance.blocksFluidAnimation) return;

    // FFT stops while paused. Let stale rhythm energy return to the ambient
    // baseline while keeping the background itself moving.
    _rhythmSampleAge += frameSeconds;
    final targetMotion = _rhythmSampleAge <= .42 ? _rhythmMotionTarget : 1.0;
    final responseSeconds = targetMotion > _motionScale ? .10 : .46;
    final response = 1 - math.exp(-frameSeconds / responseSeconds);
    _motionScale += (targetMotion - _motionScale) * response;
    final config = FluidBackgroundConfig.forQuality(_quality);
    _effectiveTime = wrapFluidPhase(
      _effectiveTime +
          frameSeconds *
              _motionScale *
              (math.pi * 2 / config.motionPeriodSeconds),
    );

    if (_paletteProgress < 1) {
      _paletteProgress =
          (_paletteProgress +
                  frameSeconds / (_paletteTransition.inMilliseconds / 1000))
              .clamp(0.0, 1.0);
    }

    final paintIntervalMicros = 1000000 ~/ config.framesPerSecond;
    if ((elapsed - _lastPaintElapsed).inMicroseconds < paintIntervalMicros) {
      return;
    }
    _lastPaintElapsed = elapsed;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    super.dispose();
  }
}
