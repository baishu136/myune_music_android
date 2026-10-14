import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../models/fluid_background_state.dart';
import 'interaction_performance_controller.dart';
import '../widgets/playback_background/fluid_colour_motion.dart';

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

  static const paletteTransition = Duration(milliseconds: 650);
  Duration _paletteTransitionDuration = paletteTransition;
  Duration get paletteTransitionDuration => _paletteTransitionDuration;

  late final Ticker _ticker;
  FluidPalette _sourcePalette;
  FluidPalette _targetPalette;
  FluidBackgroundQuality _quality;
  Duration _lastElapsed = Duration.zero;
  double _vsyncPeriodMicros = 1000000 / 60;
  double _candidatePeriodMicros = 0;
  int _stablePeriodSamples = 0;
  int _paintVsyncs = 0;
  Duration _lastPaintElapsed = Duration.zero;
  double _paletteProgress = 1;
  List<bool> _stagedFields = const [false, false, false, false];
  List<bool> get stagedFields => _stagedFields;
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
  double _displayRefreshRate = 60;

  FluidPalette get sourcePalette => _sourcePalette;
  FluidPalette get targetPalette => _targetPalette;
  double get paletteProgress => _paletteProgress;
  FluidPalette get currentPalette => FluidPalette.lerp(
    _sourcePalette,
    _targetPalette,
    fluidPaletteBlend(_paletteProgress),
    transitionProgress: _paletteProgress,
    stagedFields: _stagedFields,
  );
  double get motionScale => _motionScale;
  double get rhythmMotionTarget => _rhythmMotionTarget;
  double get effectiveTime => _effectiveTime;
  bool get isTicking => _ticker.isActive;

  /// Updates the warp-amplitude envelope from lightweight audio energy.
  /// Orbit speed stays fixed: rhythm and quality never accelerate the clock.
  /// Values are deliberately bounded here so malformed or unusually hot FFT
  /// frames can never make the full-screen shader unstable.
  void setRhythmMotion(double value) {
    if (_disposed || !value.isFinite) return;
    _rhythmMotionTarget = value.clamp(.68, 1.72);
    _rhythmSampleAge = 0;
  }

  void setPalette(FluidPalette palette) {
    if (_disposed || palette == _targetPalette) return;
    _sourcePalette = currentPalette;
    _targetPalette = alignFluidPaletteSlots(_sourcePalette, palette);
    _stagedFields = List<bool>.unmodifiable(
      List.generate(
        4,
        (field) =>
            _targetPalette.motionColors.isNotEmpty &&
            fluidNeedsIntermediateColour(
              fluidFieldColourAtTime(_sourcePalette, _effectiveTime, field),
              fluidFieldColourAtTime(_targetPalette, _effectiveTime, field),
            ),
      ),
    );
    _paletteTransitionDuration = fluidPaletteTransitionDuration(
      _sourcePalette,
      _targetPalette,
    );
    _paletteProgress = 0;
    if (_stagedFields.contains(true) &&
        _paletteTransitionDuration.inMilliseconds < 1200) {
      _paletteTransitionDuration = const Duration(milliseconds: 1200);
    }
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
    double displayRefreshRate = 60,
  }) {
    if (_disposed) return;
    final wasRunnable = _canSchedule;
    final previousQuality = _quality;
    final previousRefreshRate = _displayRefreshRate;
    _enabled = enabled;
    _visible = visible;
    _foreground = foreground;
    _reduceMotion = reduceMotion;
    _routeTransitionActive = routeTransitionActive;
    _quality = quality;
    _displayRefreshRate = displayRefreshRate.isFinite && displayRefreshRate > 0
        ? displayRefreshRate.clamp(24.0, 120.0)
        : 60;
    if (previousQuality != quality ||
        previousRefreshRate != _displayRefreshRate) {
      _resetCadence();
    }
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
    _resetCadence();
    _ticker.start();
  }

  void _resetCadence() {
    _vsyncPeriodMicros = 1000000 / _displayRefreshRate;
    _candidatePeriodMicros = 0;
    _stablePeriodSamples = 0;
    _paintVsyncs = 0;
    _lastPaintElapsed = Duration.zero;
  }

  void _observeVsync(int micros) {
    // Learn actual callback pacing, including a 60Hz surface on a 120Hz panel.
    // One delayed frame cannot change the divisor: require eight stable samples.
    if (micros < 7500 || micros > 45000) return;
    if (_candidatePeriodMicros == 0 ||
        (micros - _candidatePeriodMicros).abs() >
            _candidatePeriodMicros * .08) {
      _candidatePeriodMicros = micros.toDouble();
      _stablePeriodSamples = 1;
    } else {
      _candidatePeriodMicros += (micros - _candidatePeriodMicros) * .2;
      _stablePeriodSamples++;
    }
    if (_stablePeriodSamples >= 8) _vsyncPeriodMicros = _candidatePeriodMicros;
  }

  void _onTick(Duration elapsed) {
    if (!_canSchedule) {
      _ticker.stop();
      return;
    }
    final previous = _lastElapsed;
    _lastElapsed = elapsed;
    if (previous == Duration.zero) return;
    _observeVsync((elapsed - previous).inMicroseconds);
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
    _effectiveTime = wrapFluidPhase(_effectiveTime + frameSeconds);

    if (_paletteProgress < 1) {
      _paletteProgress =
          (_paletteProgress +
                  frameSeconds /
                      (_paletteTransitionDuration.inMilliseconds / 1000))
              .clamp(0.0, 1.0);
    }

    // Choose uniform whole-vsync intervals within the quality budget. The
    // tolerance accepts 59.94/119.88Hz without alternating frame intervals.
    final divisor =
        (1000000 / _vsyncPeriodMicros / config.framesPerSecond - .05)
            .ceil()
            .clamp(1, 6);
    if (++_paintVsyncs < divisor) return;
    // A surface can change pacing before the stable-sample estimator catches
    // up. Keep the quality budget during that short relearning interval too.
    if ((elapsed - _lastPaintElapsed).inMicroseconds <
        1000000 / config.framesPerSecond * .95) {
      return;
    }
    _paintVsyncs = 0;
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
