import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'lyric_frame_clock.dart';

/// Fixed-layout waiting dots. Entry and normal exit have independent clocks;
/// seeks snap, rather than replaying an exit at an unrelated media position.
class InterludeAnimationWidget extends StatefulWidget {
  const InterludeAnimationWidget({
    super.key,
    required this.isCurrent,
    required this.baseColor,
    required this.highlightColor,
    required this.startTime,
    required this.interludeDuration,
    required this.currentTime,
    required this.isPlaying,
    this.normalExit = true,
    this.presentationPreparing = false,
    this.positionListenable,
    this.seekIntentListenable,
    this.seekPositionListenable,
    this.playbackRate = 1,
    this.playbackRateListenable,
    this.actualPlaybackListenable,
    this.frameClock,
  });

  static const exitDuration = Duration(milliseconds: 240);
  // Media-time lead; the exit itself lasts 240ms of wall time at every rate.
  static const exitLead = Duration(milliseconds: 500);
  final bool isCurrent;
  final Color baseColor;
  final Color highlightColor;
  final Duration startTime;
  final Duration interludeDuration;
  final Duration currentTime;
  final bool isPlaying;
  final bool normalExit;
  // Cover-to-lyrics preparation resolves retained controllers while invisible.
  final bool presentationPreparing;
  final ValueListenable<Duration>? positionListenable;
  final Listenable? seekIntentListenable;
  final ValueListenable<Duration?>? seekPositionListenable;
  final double playbackRate;
  final ValueListenable<double>? playbackRateListenable;
  final ValueListenable<bool>? actualPlaybackListenable;
  final LyricFrameClock? frameClock;

  @override
  State<InterludeAnimationWidget> createState() =>
      _InterludeAnimationWidgetState();
}

class _InterludeAnimationWidgetState extends State<InterludeAnimationWidget>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final AnimationController _breatheController;
  late final AnimationController _visibilityController;
  late final AnimationController _exitController;
  late final CurvedAnimation _visibility;
  late final CurvedAnimation _exitProgress;
  late final Animation<double> _exitOpacity;
  late final Animation<Offset> _entryOffset;
  late final InterludeDotsPainter _painter;
  final _paintSignal = _InterludePaintSignal();
  Ticker? _progressTicker;
  bool _followingFrames = false;
  bool _exiting = false;
  bool _earlyExit = false;
  bool _visualCurrent = false;
  bool _seekAwaitingRow = false;
  int _elapsedUs = 0;
  int _sourceElapsedUs = 0;
  int _lastAudioUs = 0;
  int _uiUs = 0;
  Duration _frameOrigin = Duration.zero;

  @override
  bool get wantKeepAlive => _exiting;

  Duration get _source =>
      widget.positionListenable?.value ?? widget.currentTime;
  double get _rate =>
      widget.playbackRateListenable?.value ?? widget.playbackRate;
  bool get _running =>
      widget.isPlaying && (widget.actualPlaybackListenable?.value ?? true);

  @override
  void initState() {
    super.initState();
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _visibilityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _exitController = AnimationController(
      vsync: this,
      duration: InterludeAnimationWidget.exitDuration,
    )..addStatusListener(_onExitStatus);
    _visibility = CurvedAnimation(
      parent: _visibilityController,
      curve: Curves.easeOutCubic,
    );
    _entryOffset = Tween<Offset>(
      begin: const Offset(0, .22),
      end: Offset.zero,
    ).animate(_visibility);
    _exitProgress = CurvedAnimation(
      parent: _exitController,
      curve: Curves.easeOutCubic,
    );
    _exitOpacity = Tween<double>(begin: 1, end: 0).animate(_exitProgress);
    _painter = InterludeDotsPainter(
      _breatheController,
      _exitProgress,
      _paintSignal,
    );
    _attachSources();
    _visualCurrent = widget.isCurrent;
    _anchor(_source);
    _updateProgress();
    if (widget.presentationPreparing) {
      _snap(widget.isCurrent, _source);
    } else if (_visualCurrent && !_exiting) {
      _visibilityController.forward();
    } else {
      _exitController.value = 1;
    }
    _syncPlayback();
  }

  void _attachSources() {
    widget.positionListenable?.addListener(_readSource);
    widget.seekIntentListenable?.addListener(_readSeekIntent);
    widget.seekPositionListenable?.addListener(_readSeek);
    widget.playbackRateListenable?.addListener(_readRate);
    widget.actualPlaybackListenable?.addListener(_syncPlayback);
  }

  void _detachSources(InterludeAnimationWidget source) {
    source.positionListenable?.removeListener(_readSource);
    source.seekIntentListenable?.removeListener(_readSeekIntent);
    source.seekPositionListenable?.removeListener(_readSeek);
    source.playbackRateListenable?.removeListener(_readRate);
    source.actualPlaybackListenable?.removeListener(_syncPlayback);
  }

  @override
  void didUpdateWidget(InterludeAnimationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _detachSources(oldWidget);
    _attachSources();
    if (oldWidget.frameClock != widget.frameClock) {
      _stopTicker(clock: oldWidget.frameClock);
    }
    final timingChanged =
        oldWidget.startTime != widget.startTime ||
        oldWidget.interludeDuration != widget.interludeDuration;
    if (timingChanged || widget.presentationPreparing) {
      _snap(widget.isCurrent, _source);
      return;
    }
    if (oldWidget.isCurrent != widget.isCurrent) {
      if (_seekAwaitingRow) {
        _seekAwaitingRow = false;
        _snap(widget.isCurrent, _source);
      } else if (widget.isCurrent) {
        _cancelExit();
        _visualCurrent = true;
        _anchor(_source);
        _updateProgress();
        _visibilityController.forward();
        _syncPlayback();
      } else if (widget.normalExit && _earlyExit) {
        // The 500ms lead already started/completed this exit. Do not restart
        // it at the actual row boundary or accept the inactive preview clock.
      } else if (widget.normalExit && _visualCurrent) {
        // Freeze BEFORE accepting the inactive row's preview time/colour.
        // Never reverse the entrance's downward displacement.
        _beginExit();
      } else {
        _snap(false, _source);
      }
      return;
    }
    if (_exiting) {
      if (!widget.normalExit && !widget.isCurrent) {
        _snap(widget.isCurrent, _source);
      }
      return; // Lost stream or another normal line cannot rewind an exit.
    }
    if (oldWidget.currentTime != widget.currentTime ||
        oldWidget.positionListenable != widget.positionListenable) {
      _readSource();
    }
    if (oldWidget.playbackRate != widget.playbackRate ||
        oldWidget.playbackRateListenable != widget.playbackRateListenable) {
      _readRate();
    }
    _updateProgress();
    _syncPlayback();
  }

  void _anchor(Duration source) {
    _lastAudioUs = _uiUs = source.inMicroseconds;
    _sourceElapsedUs = _elapsedUs;
  }

  bool _contains(Duration value) =>
      value >= widget.startTime &&
      value < widget.startTime + widget.interludeDuration;

  void _readSeekIntent() {
    _seekAwaitingRow = true;
    _snap(false, _source); // Unknown destination: no interrupted-exit ghost.
  }

  void _readSeek() {
    final target = widget.seekPositionListenable?.value;
    if (target == null) return;
    _seekAwaitingRow = _contains(target) != widget.isCurrent;
    _snap(_contains(target), target);
  }

  void _readSource() {
    if (!_visualCurrent || _exiting) return;
    final source = _source;
    final expected = _running
        ? ((_elapsedUs - _sourceElapsedUs) * _rate).round()
        : 0;
    final correction = source.inMicroseconds - _lastAudioUs - expected;
    if (correction.abs() > 160000) {
      _seekAwaitingRow = _contains(source) != widget.isCurrent;
      _snap(_contains(source), source);
      return;
    }
    // Position is authoritative; small decoder corrections stay monotone.
    _lastAudioUs = source.inMicroseconds;
    _sourceElapsedUs = _elapsedUs;
    if (!_running && _lastAudioUs > _uiUs) _uiUs = _lastAudioUs;
    _updateProgress();
  }

  void _readRate() {
    _lastAudioUs = _uiUs;
    _sourceElapsedUs = _elapsedUs;
  }

  void _updateProgress() {
    if (_exiting) return;
    final durationUs = widget.interludeDuration.inMicroseconds;
    final progress = _visualCurrent && durationUs > 0
        ? ((_uiUs - widget.startTime.inMicroseconds) / durationUs).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    if (_painter.update(progress, widget.baseColor, widget.highlightColor)) {
      _paintSignal.pulse();
    }
    if (_visualCurrent &&
        _running &&
        durationUs > 0 &&
        _uiUs >=
            widget.startTime.inMicroseconds +
                durationUs -
                InterludeAnimationWidget.exitLead.inMicroseconds) {
      _earlyExit = true;
      _beginExit();
    }
  }

  void _beginExit() {
    _visualCurrent = false;
    _stopTicker();
    _breatheController.stop();
    _visibilityController.stop();
    _exiting = true;
    updateKeepAlive();
    _exitController.forward(from: 0);
  }

  void _cancelExit() {
    _exitController.stop();
    _exiting = false;
    _earlyExit = false;
    _exitController.value = 0;
    updateKeepAlive();
  }

  void _snap(bool visible, Duration source) {
    _cancelExit();
    _visualCurrent = visible;
    _visibilityController.stop();
    _visibilityController.value = visible ? 1 : 0;
    _exitController.value = visible ? 0 : 1;
    _anchor(source);
    _updateProgress();
    _syncPlayback();
  }

  void _onExitStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_exiting) return;
    _exiting = false;
    // Invisible canvas resets without rebuilding the row.
    _painter.update(0, widget.baseColor, widget.highlightColor);
    _breatheController.value = 0;
    _visibilityController.value = 0;
    updateKeepAlive();
  }

  void _syncPlayback() {
    if (!_visualCurrent || _exiting || !_running) {
      _stopTicker();
      _breatheController.stop();
      _lastAudioUs = _uiUs;
      _sourceElapsedUs = _elapsedUs;
      return;
    }
    if (!_breatheController.isAnimating) {
      _breatheController.repeat(reverse: true);
    }
    if (_followingFrames) return;
    _followingFrames = true;
    _elapsedUs = _sourceElapsedUs = 0;
    _lastAudioUs = _uiUs;
    if (widget.frameClock case final clock?) {
      clock.addListener(_onSharedFrame);
      _frameOrigin = clock.elapsed;
    } else {
      _progressTicker ??= createTicker(_tick);
      _progressTicker!.start();
    }
  }

  void _onSharedFrame() => _tick(widget.frameClock!.elapsed - _frameOrigin);

  void _tick(Duration elapsed) {
    _elapsedUs = elapsed.inMicroseconds;
    final candidate =
        _lastAudioUs + ((_elapsedUs - _sourceElapsedUs) * _rate).round();
    if (candidate > _uiUs) _uiUs = candidate;
    _updateProgress();
  }

  void _stopTicker({LyricFrameClock? clock}) {
    if (_followingFrames) {
      (clock ?? widget.frameClock)?.removeListener(_onSharedFrame);
    }
    _followingFrames = false;
    _progressTicker?.stop();
  }

  @override
  void dispose() {
    _detachSources(widget);
    _stopTicker();
    _progressTicker?.dispose();
    _visibility.dispose();
    _exitProgress.dispose();
    _breatheController.dispose();
    _visibilityController.dispose();
    _exitController.dispose();
    _paintSignal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return IgnorePointer(
      child: FadeTransition(
        key: const ValueKey('interlude_exit_visibility'),
        opacity: _exitOpacity,
        child: FadeTransition(
          key: const ValueKey('interlude_visibility'),
          opacity: _visibility,
          child: SlideTransition(
            position: _entryOffset,
            child: _InterludePaintBoundary(
              child: CustomPaint(
                key: const ValueKey('interlude_dots'),
                size: const Size(60, 8),
                willChange: true,
                painter: _painter,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Scalar-only drawing with cached Paints. The fixed 60×8 layout matches the
/// old three 8px dots with 6px side padding. Gather moves drawn centres, never
/// Padding, Row width, item extent or layout constraints.
class InterludeDotsPainter extends CustomPainter {
  InterludeDotsPainter(this._breathe, this._exit, Listenable progress)
    : super(repaint: Listenable.merge([_breathe, _exit, progress]));

  final Animation<double> _breathe;
  final Animation<double> _exit;
  final _paints = List<Paint>.generate(3, (_) => Paint());
  final _dotProgress = Float64List(3);
  double _progress = -1;
  Color? _baseColor;
  Color? _highlightColor;

  @visibleForTesting
  double get progress => _progress;
  @visibleForTesting
  double get exitProgress => _exit.value;
  @visibleForTesting
  double get scale => 1 - .85 * exitProgress;
  @visibleForTesting
  double get dy => -8 * exitProgress;
  @visibleForTesting
  double get spacing => 6 - 5 * exitProgress;
  @visibleForTesting
  Color dotColor(int index) => _paints[index].color;

  bool update(double progress, Color baseColor, Color highlightColor) {
    if (_progress == progress &&
        _baseColor == baseColor &&
        _highlightColor == highlightColor) {
      return false;
    }
    _progress = progress;
    _baseColor = baseColor;
    _highlightColor = highlightColor;
    for (var index = 0; index < 3; index++) {
      final dot = (progress * 3 - index).clamp(0.0, 1.0);
      _dotProgress[index] = dot;
      _paints[index].color = Color.lerp(
        baseColor,
        highlightColor,
        Curves.easeInOut.transform(dot),
      )!;
    }
    return true;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (exitProgress >= 1) return;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2 + dy);
    canvas.scale(scale);
    final separation = 8 + 2 * spacing;
    for (var index = 0; index < 3; index++) {
      final dot = _dotProgress[index];
      final amplitude = dot < 1 ? lerpDouble(.25, .45, dot)! : .15;
      final radius = 4 * (lerpDouble(.8, 1, dot)! + amplitude * _breathe.value);
      canvas.save();
      canvas.translate((index - 1) * separation, 0);
      canvas.drawCircle(Offset.zero, radius, _paints[index]);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(InterludeDotsPainter oldDelegate) =>
      !identical(this, oldDelegate);
}

class _InterludePaintSignal extends ChangeNotifier {
  void pulse() => notifyListeners();
}

// Reserve paint overflow, not layout space: shrinking dots float above their
// original 8px box. The fixed cull bounds also avoid a first-frame raster-cache
// crop while keeping every row/item constraint unchanged.
class _InterludePaintBoundary extends SingleChildRenderObjectWidget {
  const _InterludePaintBoundary({required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _InterludeBoundaryRender();
}

class _InterludeBoundaryRender extends RenderRepaintBoundary {
  @override
  Rect get paintBounds => const Rect.fromLTWH(-8, -16, 76, 40);
}
