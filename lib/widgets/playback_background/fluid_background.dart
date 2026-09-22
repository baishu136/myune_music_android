import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../models/fluid_background_state.dart';
import '../../services/artwork_palette_cache.dart';
import '../../services/fluid_background_controller.dart';
import '../../services/interaction_performance_controller.dart';
import 'fluid_background_painter.dart';

class FluidPlaybackBackground extends StatefulWidget {
  const FluidPlaybackBackground({
    super.key,
    required this.artworkBytes,
    required this.artworkIdentity,
    required this.artworkCacheGeneration,
    required this.fallbackSeed,
    required this.dim,
    required this.quality,
    required this.routeTransitionActive,
    this.routeTransitionListenable,
    this.rhythmFrames,
    required this.child,
  });

  final Uint8List? artworkBytes;
  final String artworkIdentity;
  final int artworkCacheGeneration;
  final Color fallbackSeed;
  final double dim;
  final FluidBackgroundQuality quality;
  final bool routeTransitionActive;
  final ValueListenable<bool>? routeTransitionListenable;
  final Stream<FftFrame>? rhythmFrames;
  final Widget child;

  @override
  State<FluidPlaybackBackground> createState() =>
      _FluidPlaybackBackgroundState();
}

class _FluidPlaybackBackgroundState extends State<FluidPlaybackBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _surfaceResumeMotionDelay = Duration(milliseconds: 900);
  static final LinkedHashMap<String, ({FluidPalette palette, double phase})>
  _visualSnapshots = LinkedHashMap();
  static Future<ui.FragmentProgram>? _programRequest;
  static ui.FragmentProgram? _program;
  static bool _shaderUnavailable = false;

  late final FluidBackgroundController _controller;
  late FluidPalette _entryPalette;
  late String _visualSnapshotKey;
  ui.FragmentShader? _shader;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  bool _reduceMotion = false;
  bool _routeIsCurrent = true;
  bool _foregroundMotionReady = true;
  int _foregroundResumeGeneration = 0;
  int _preparationGeneration = 0;
  StreamSubscription<FftFrame>? _rhythmSubscription;
  double _previousBassEnergy = 0;

  bool get _routeTransitionActive =>
      widget.routeTransitionActive ||
      (widget.routeTransitionListenable?.value ?? false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.routeTransitionListenable?.addListener(_handleRouteTransition);
    _visualSnapshotKey = _paletteKeyFor(widget);
    final snapshot = _visualSnapshots.remove(_visualSnapshotKey);
    if (snapshot != null) _visualSnapshots[_visualSnapshotKey] = snapshot;
    _entryPalette =
        snapshot?.palette ??
        fluidArtworkPaletteCache.peek(_visualSnapshotKey) ??
        FluidPalette.fallback(widget.fallbackSeed);
    _controller = FluidBackgroundController(
      vsync: this,
      initialPalette: _entryPalette,
      initialEffectiveTime: snapshot?.phase ?? 0,
      quality: widget.quality,
    );
    final loadedProgram = _program;
    if (loadedProgram != null) _shader = loadedProgram.fragmentShader();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareIfNeeded());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    // ModalRoute is an inherited dependency. Re-evaluate when a dialog or
    // bottom sheet covers the playback route so the shader does no hidden work.
    _routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    _syncController();
  }

  @override
  void didUpdateWidget(covariant FluidPlaybackBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      oldWidget.routeTransitionListenable,
      widget.routeTransitionListenable,
    )) {
      oldWidget.routeTransitionListenable?.removeListener(
        _handleRouteTransition,
      );
      widget.routeTransitionListenable?.addListener(_handleRouteTransition);
    }
    if (!identical(oldWidget.rhythmFrames, widget.rhythmFrames)) {
      unawaited(_rhythmSubscription?.cancel());
      _rhythmSubscription = null;
      _previousBassEnergy = 0;
    }
    final nextSnapshotKey = _paletteKeyFor(widget);
    if (nextSnapshotKey != _visualSnapshotKey) {
      _saveVisualSnapshot();
      _visualSnapshotKey = nextSnapshotKey;
      final snapshot = _visualSnapshots.remove(nextSnapshotKey);
      if (snapshot != null) _visualSnapshots[nextSnapshotKey] = snapshot;
      _entryPalette =
          snapshot?.palette ??
          fluidArtworkPaletteCache.peek(nextSnapshotKey) ??
          FluidPalette.fallback(widget.fallbackSeed);
      _controller.setPalette(_entryPalette);
    }
    _syncController();
    if (oldWidget.artworkIdentity != widget.artworkIdentity ||
        oldWidget.artworkCacheGeneration != widget.artworkCacheGeneration ||
        !identical(oldWidget.artworkBytes, widget.artworkBytes) ||
        oldWidget.fallbackSeed != widget.fallbackSeed ||
        (oldWidget.routeTransitionActive && !widget.routeTransitionActive)) {
      _prepareIfNeeded();
    }
  }

  void _handleRouteTransition() {
    _preparationGeneration++;
    _syncController();
  }

  String _paletteKeyFor(FluidPlaybackBackground source) {
    final bytes = source.artworkBytes;
    return bytes == null || bytes.isEmpty
        ? '${source.artworkIdentity}@${source.artworkCacheGeneration}:empty'
        : fluidArtworkPaletteKey(
            source.artworkIdentity,
            source.artworkCacheGeneration,
            bytes,
          );
  }

  void _saveVisualSnapshot() {
    _visualSnapshots.remove(_visualSnapshotKey);
    _visualSnapshots[_visualSnapshotKey] = (
      palette: _controller.currentPalette,
      phase: _controller.effectiveTime,
    );
    while (_visualSnapshots.length > 32) {
      _visualSnapshots.remove(_visualSnapshots.keys.first);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state != AppLifecycleState.resumed) {
      _foregroundResumeGeneration++;
      _foregroundMotionReady = false;
      _syncController();
      return;
    }
    _foregroundMotionReady = false;
    _syncController();
    unawaited(_restoreMotionAfterSurfaceResume());
  }

  Future<void> _restoreMotionAfterSurfaceResume() async {
    final generation = ++_foregroundResumeGeneration;
    // Android may report resumed before the Flutter surface and GPU queue have
    // settled. Starting the full-screen shader in that window can leave raster
    // work paced at roughly 20 ms until its ticker is restarted. Keep the last
    // static shader frame visible while foreground widgets paint normally.
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(_surfaceResumeMotionDelay);
    final lease = await InteractionPerformanceController.instance
        .acquireIdleWork(
          priority: InteractionWorkPriority.background,
          isStillNeeded: () =>
              mounted &&
              generation == _foregroundResumeGeneration &&
              _lifecycle == AppLifecycleState.resumed,
        );
    try {
      if (!lease.isGranted ||
          !mounted ||
          generation != _foregroundResumeGeneration ||
          _lifecycle != AppLifecycleState.resumed) {
        return;
      }
      _foregroundMotionReady = true;
      _syncController();
    } finally {
      lease.release();
    }
  }

  void _syncController() {
    final rhythmActive =
        TickerMode.valuesOf(context).enabled &&
        _routeIsCurrent &&
        _lifecycle == AppLifecycleState.resumed &&
        _foregroundMotionReady &&
        !_reduceMotion &&
        !_routeTransitionActive;
    _controller.updateOperatingState(
      enabled: true,
      visible: TickerMode.valuesOf(context).enabled && _routeIsCurrent,
      foreground:
          _lifecycle == AppLifecycleState.resumed && _foregroundMotionReady,
      reduceMotion: _reduceMotion,
      routeTransitionActive: _routeTransitionActive,
      quality: widget.quality,
    );
    _syncRhythmSubscription(rhythmActive);
  }

  void _syncRhythmSubscription(bool active) {
    final frames = widget.rhythmFrames;
    if (!active || frames == null) {
      if (_rhythmSubscription != null) {
        unawaited(_rhythmSubscription!.cancel());
        _rhythmSubscription = null;
      }
      return;
    }
    _rhythmSubscription ??= frames.listen(_handleRhythmFrame);
  }

  void _handleRhythmFrame(FftFrame frame) {
    final bands = frame.bands;
    if (bands.isEmpty) return;
    final bassCount = (bands.length * .22).round().clamp(2, bands.length);
    var bassSquares = 0.0;
    var allSquares = 0.0;
    for (var index = 0; index < bands.length; index++) {
      final value = bands[index].clamp(0.0, 1.0);
      allSquares += value * value;
      if (index < bassCount) bassSquares += value * value;
    }
    final bass = math.sqrt(bassSquares / bassCount);
    final overall = math.sqrt(allSquares / bands.length);
    final onset = (bass - _previousBassEnergy).clamp(0.0, 1.0);
    _previousBassEnergy += (bass - _previousBassEnergy) * .42;
    _controller.setRhythmMotion(
      (.72 + bass * .48 + overall * .18 + onset * 1.15).clamp(.68, 1.72),
    );
  }

  Future<void> _prepareIfNeeded() async {
    if (!mounted || _routeTransitionActive || _shaderUnavailable) return;
    final generation = ++_preparationGeneration;
    final bytes = widget.artworkBytes;
    final identity = widget.artworkIdentity;
    final cacheGeneration = widget.artworkCacheGeneration;
    final fallbackSeed = widget.fallbackSeed;
    final lease = await InteractionPerformanceController.instance
        .acquireIdleWork(
          priority: InteractionWorkPriority.background,
          isStillNeeded: () =>
              mounted &&
              generation == _preparationGeneration &&
              !_routeTransitionActive,
        );
    try {
      if (!lease.isGranted ||
          !mounted ||
          generation != _preparationGeneration ||
          _routeTransitionActive) {
        return;
      }
      if (_shader == null) {
        try {
          final program = await (_programRequest ??=
              ui.FragmentProgram.fromAsset(
                'shaders/fluid_background.frag',
              ).then((program) {
                _program = program;
                return program;
              }));
          if (!mounted || generation != _preparationGeneration) return;
          _shader = program.fragmentShader();
        } catch (_) {
          _shaderUnavailable = true;
          if (mounted) setState(() {});
          return;
        }
      }
      final palette = bytes == null || bytes.isEmpty
          ? FluidPalette.fallback(fallbackSeed)
          : await fluidArtworkPaletteCache.resolve(
              key: fluidArtworkPaletteKey(identity, cacheGeneration, bytes),
              bytes: bytes,
              fallbackSeed: fallbackSeed,
            );
      if (!mounted || generation != _preparationGeneration) return;
      _controller.setPalette(palette);
      setState(() {});
    } finally {
      lease.release();
    }
  }

  @override
  void dispose() {
    _preparationGeneration++;
    _foregroundResumeGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    widget.routeTransitionListenable?.removeListener(_handleRouteTransition);
    unawaited(_rhythmSubscription?.cancel());
    _saveVisualSnapshot();
    _controller.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = _entryPalette;
    final shader = _shader;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: shader == null || _reduceMotion
              ? DecoratedBox(
                  key: const ValueKey('fluid-background-static-fallback'),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: fallback.colors,
                    ),
                  ),
                )
              : CustomPaint(
                  key: const ValueKey('fluid-background-shader'),
                  painter: FluidBackgroundPainter(
                    shader: shader,
                    controller: _controller,
                    dim: widget.dim,
                  ),
                ),
        ),
        widget.child,
      ],
    );
  }
}
