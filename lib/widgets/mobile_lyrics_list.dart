import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable, kDebugMode;
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/scheduler.dart' show Ticker;

import '../page/playlist/playlist_models.dart';
import 'lyric_scroll_motion.dart';

class MobileLyricsListController {
  Object? _owner;
  VoidCallback? _recenterCallback;
  ValueChanged<Duration>? _settleCallback;
  bool _recenterPending = false;
  Duration? _settlePending;

  void _attach(
    Object owner,
    VoidCallback recenterCallback,
    ValueChanged<Duration> settleCallback,
  ) {
    _owner = owner;
    _recenterCallback = recenterCallback;
    _settleCallback = settleCallback;
    if (_recenterPending) {
      _recenterPending = false;
      recenterCallback();
    }
    final pendingTarget = _settlePending;
    if (pendingTarget != null) {
      _settlePending = null;
      settleCallback(pendingTarget);
    }
  }

  void _detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _recenterCallback = null;
    _settleCallback = null;
  }

  void recenter() {
    final callback = _recenterCallback;
    if (callback == null) {
      _recenterPending = true;
      return;
    }
    callback();
  }

  void settleOn(Duration target) {
    final callback = _settleCallback;
    if (callback == null) {
      _settlePending = target;
      return;
    }
    callback(target);
  }
}

class MobileLyricsList extends StatefulWidget {
  const MobileLyricsList({
    super.key,
    required this.lines,
    required this.active,
    this.fontSize = 20,
    this.fontFamily,
    this.controller,
    this.edgeFadeEnabled = false,
    this.glowEnabled = false,
    this.glowRadius = 8,
    this.brightForeground = false,
    this.position = Duration.zero,
    this.positionListenable,
    this.onBrowseTargetChanged,
  });

  final List<LyricLine> lines;
  final int active;
  final double fontSize;
  final String? fontFamily;
  final MobileLyricsListController? controller;
  final bool edgeFadeEnabled;
  final bool glowEnabled;
  final double glowRadius;
  final bool brightForeground;
  final Duration position;
  final ValueListenable<Duration>? positionListenable;
  final ValueChanged<Duration?>? onBrowseTargetChanged;

  @override
  State<MobileLyricsList> createState() => _MobileLyricsListState();
}

class _MobileLyricsListState extends State<MobileLyricsList>
    with SingleTickerProviderStateMixin {
  static const _focusAnchor = .42;
  static const _predictionWindow = Duration(milliseconds: 160);

  ScrollController? _scrollControllerState;
  final LyricScrollMotion _motion = LyricScrollMotion();
  final ValueNotifier<_LyricDebugSnapshot> _debugSnapshot = ValueNotifier(
    const _LyricDebugSnapshot(),
  );
  late final Ticker _motionTicker;
  Duration? _lastTick;
  Duration _lastDebugUpdate = Duration.zero;
  Timer? _resumeFollowTimer;
  Timer? _browseGuideTimer;
  Timer? _seekTargetTimer;
  bool _isManuallyBrowsing = false;
  bool _hasInitialPosition = false;
  bool _layoutInvalid = true;
  bool _debugOverlayEnabled = false;
  int _layoutRequestId = 0;
  int _recompositionCount = 0;
  int? _browseTargetIndex;
  int? _seekTargetIndex;
  double _viewportHeight = 0;
  double _layoutWidth = 0;
  double _topPadding = 0;
  double _bottomPadding = 0;
  List<double> _itemHeights = const [];
  List<double> _itemOffsets = const [];
  List<LyricLine>? _layoutLines;
  double _layoutFontSize = -1;
  String? _layoutFontFamily;
  TextDirection? _layoutDirection;
  double _layoutTextScale = -1;
  ValueListenable<Duration>? _positionSource;

  ScrollController get _scrollController => _scrollControllerState!;

  @override
  void initState() {
    super.initState();
    _motionTicker = createTicker(_onMotionTick);
    widget.controller?._attach(this, _recenterActive, _settleOnTimestamp);
    _attachPositionSource(widget.positionListenable);
  }

  @override
  void didUpdateWidget(covariant MobileLyricsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this, _recenterActive, _settleOnTimestamp);
    }
    if (oldWidget.positionListenable != widget.positionListenable) {
      _attachPositionSource(widget.positionListenable);
    }

    final linesChanged = oldWidget.lines != widget.lines;
    final fontChanged =
        (oldWidget.fontSize - widget.fontSize).abs() >= .01 ||
        oldWidget.fontFamily != widget.fontFamily;
    if (linesChanged || fontChanged) {
      _layoutInvalid = true;
      _clearSeekTarget();
      _resumeAutomaticFollow(notifyBrowseTarget: false);
      if (oldWidget.lines.isEmpty) _hasInitialPosition = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onBrowseTargetChanged?.call(null);
      });
      _scheduleLayoutRetarget(jump: oldWidget.lines.isEmpty);
      return;
    }

    if (oldWidget.active == widget.active) return;
    final seekTarget = _seekTargetIndex;
    if (seekTarget != null) {
      if (widget.active == seekTarget) _clearSeekTarget();
      return;
    }
    _retargetIndex(widget.active);
  }

  void _attachPositionSource(ValueListenable<Duration>? source) {
    _positionSource?.removeListener(_handlePositionTick);
    _positionSource = source;
    source?.addListener(_handlePositionTick);
  }

  void _handlePositionTick() {
    if (_isManuallyBrowsing || _seekTargetIndex != null) return;
    final active = widget.active;
    if (active < 0 || active + 1 >= widget.lines.length) return;
    final source = _positionSource;
    if (source == null || _itemOffsets.length != widget.lines.length) return;

    final remaining =
        widget.lines[active + 1].timestamp.inMicroseconds -
        source.value.inMicroseconds;
    final window = _predictionWindow.inMicroseconds;
    if (remaining <= 0 || remaining > window) return;
    final progress = 1 - remaining / window;
    final preview = Curves.easeIn.transform(progress.clamp(0.0, 1.0)) * .18;
    final target = _itemOffsets[active] +
        (_itemOffsets[active + 1] - _itemOffsets[active]) * preview;
    _retargetOffset(target);
  }

  void _onMotionTick(Duration elapsed) {
    if (!_scrollController.hasClients) {
      _stopMotion();
      return;
    }
    final previousTick = _lastTick;
    _lastTick = elapsed;
    if (previousTick == null) return;
    final frameSeconds =
        (elapsed - previousTick).inMicroseconds / Duration.microsecondsPerSecond;
    final maxOffset = _scrollController.position.maxScrollExtent;
    _motion.retarget(
      _motion.target.clamp(0.0, maxOffset),
      viewportExtent: _viewportHeight,
    );
    final nextOffset = _motion.advance(frameSeconds).clamp(0.0, maxOffset);
    if ((_scrollController.offset - nextOffset).abs() >= .05) {
      _scrollController.jumpTo(nextOffset);
    }
    _updateDebugSnapshot(elapsed, frameSeconds);
    if (_motion.isSettled) _stopMotion();
  }

  void _startMotion() {
    if (_motionTicker.isActive) return;
    _lastTick = null;
    _motionTicker.start();
  }

  void _stopMotion() {
    if (_motionTicker.isActive) _motionTicker.stop();
    _lastTick = null;
  }

  void _retargetIndex(int index, {bool force = false}) {
    if ((_isManuallyBrowsing && !force) ||
        index < 0 ||
        index >= _itemOffsets.length) {
      return;
    }
    _retargetOffset(_itemOffsets[index]);
  }

  void _retargetOffset(double target) {
    if (!_scrollController.hasClients) {
      _scheduleLayoutRetarget();
      return;
    }
    _motion.offset = _scrollController.offset;
    _motion.retarget(target, viewportExtent: _viewportHeight);
    _startMotion();
  }

  void _jumpToIndex(int index) {
    if (!_scrollController.hasClients ||
        index < 0 ||
        index >= _itemOffsets.length) {
      return;
    }
    final target = _itemOffsets[index].clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _stopMotion();
    _scrollController.jumpTo(target);
    _motion.sync(target, viewportExtent: _viewportHeight);
    _hasInitialPosition = true;
  }

  void _scheduleLayoutRetarget({bool jump = false}) {
    final requestId = ++_layoutRequestId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || requestId != _layoutRequestId) return;
      if (!_scrollController.hasClients || _itemOffsets.isEmpty) return;
      if (jump || !_hasInitialPosition) {
        _jumpToIndex(widget.active.clamp(0, _itemOffsets.length - 1));
      } else {
        _retargetIndex(widget.active, force: true);
      }
    });
  }

  void _startManualInteraction() {
    if (!mounted) return;
    _clearSeekTarget();
    _isManuallyBrowsing = true;
    _stopMotion();
    _motion.sync(
      _scrollController.hasClients ? _scrollController.offset : 0,
      viewportExtent: _viewportHeight,
    );
    _resumeFollowTimer?.cancel();
    _resumeFollowTimer = null;
    _browseGuideTimer?.cancel();
    _browseGuideTimer = null;
    _updateBrowseTargetFromOffset(force: true);
  }

  void _scheduleResumeFollowTimer() {
    if (!mounted || !_isManuallyBrowsing) return;
    _scheduleBrowseGuideHideTimer();
    _resumeFollowTimer?.cancel();
    _resumeFollowTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      _resumeFollowTimer = null;
      _resumeAutomaticFollow();
      _retargetIndex(widget.active, force: true);
    });
  }

  void _scheduleBrowseGuideHideTimer() {
    _browseGuideTimer?.cancel();
    _browseGuideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || !_isManuallyBrowsing) return;
      _browseGuideTimer = null;
      _browseTargetIndex = null;
      widget.onBrowseTargetChanged?.call(null);
    });
  }

  void _resumeAutomaticFollow({bool notifyBrowseTarget = true}) {
    _resumeFollowTimer?.cancel();
    _resumeFollowTimer = null;
    _browseGuideTimer?.cancel();
    _browseGuideTimer = null;
    _isManuallyBrowsing = false;
    _browseTargetIndex = null;
    if (notifyBrowseTarget) widget.onBrowseTargetChanged?.call(null);
  }

  void _updateBrowseTargetFromOffset({bool force = false}) {
    if (!_isManuallyBrowsing ||
        widget.lines.isEmpty ||
        !_scrollController.hasClients ||
        _itemOffsets.isEmpty) {
      return;
    }
    final contentCenter = _scrollController.offset + _viewportHeight * .5;
    var low = 0;
    var high = _itemOffsets.length - 1;
    while (low < high) {
      final mid = (low + high) >> 1;
      final itemCenter = _itemOffsets[mid] + _viewportHeight * _focusAnchor;
      if (itemCenter < contentCenter) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    var index = low;
    if (index > 0) {
      final currentCenter =
          _itemOffsets[index] + _viewportHeight * _focusAnchor;
      final previousCenter =
          _itemOffsets[index - 1] + _viewportHeight * _focusAnchor;
      if ((contentCenter - previousCenter).abs() <
          (contentCenter - currentCenter).abs()) {
        index--;
      }
    }
    if (!force && index == _browseTargetIndex) return;
    _browseTargetIndex = index;
    widget.onBrowseTargetChanged?.call(widget.lines[index].timestamp);
  }

  void _recenterActive() {
    _clearSeekTarget();
    _resumeAutomaticFollow();
    _scheduleLayoutRetarget(jump: true);
  }

  void _settleOnTimestamp(Duration timestamp) {
    if (widget.lines.isEmpty) return;
    _resumeAutomaticFollow();

    var targetIndex = 0;
    var nearestDistance = (widget.lines.first.timestamp - timestamp)
        .inMilliseconds
        .abs();
    for (var index = 1; index < widget.lines.length; index++) {
      final distance = (widget.lines[index].timestamp - timestamp)
          .inMilliseconds
          .abs();
      if (distance >= nearestDistance) continue;
      nearestDistance = distance;
      targetIndex = index;
    }

    _seekTargetTimer?.cancel();
    _seekTargetIndex = targetIndex;
    _retargetIndex(targetIndex, force: true);
    _seekTargetTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || _seekTargetIndex != targetIndex) return;
      _clearSeekTarget();
      _retargetIndex(widget.active, force: true);
    });
  }

  void _clearSeekTarget() {
    _seekTargetTimer?.cancel();
    _seekTargetTimer = null;
    _seekTargetIndex = null;
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _startManualInteraction();
    } else if (notification is ScrollUpdateNotification &&
        _isManuallyBrowsing) {
      _motion.sync(
        notification.metrics.pixels,
        viewportExtent: _viewportHeight,
      );
      _updateBrowseTargetFromOffset();
    } else if (notification is ScrollEndNotification && _isManuallyBrowsing) {
      _scheduleResumeFollowTimer();
    }
    return false;
  }

  bool _ensureLayoutMetrics(BuildContext context, BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final viewport = constraints.maxHeight;
    final direction = Directionality.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final unchanged =
        !_layoutInvalid &&
        identical(_layoutLines, widget.lines) &&
        (_layoutWidth - width).abs() < .5 &&
        (_viewportHeight - viewport).abs() < .5 &&
        (_layoutFontSize - widget.fontSize).abs() < .01 &&
        _layoutFontFamily == widget.fontFamily &&
        _layoutDirection == direction &&
        (_layoutTextScale - textScale).abs() < .001;
    if (unchanged) return false;

    _layoutInvalid = false;
    _layoutLines = widget.lines;
    _layoutWidth = width;
    _viewportHeight = viewport;
    _layoutFontSize = widget.fontSize;
    _layoutFontFamily = widget.fontFamily;
    _layoutDirection = direction;
    _layoutTextScale = textScale;

    final availableWidth = (width - 48).clamp(1.0, double.infinity);
    final textStyle = DefaultTextStyle.of(context).style.copyWith(
      fontFamily: widget.fontFamily,
      fontSize: widget.fontSize,
      fontWeight: FontWeight.w700,
      height: 1.2,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final heights = List<double>.filled(widget.lines.length, 0);
    final offsets = List<double>.filled(widget.lines.length, 0);
    var runningOffset = 0.0;
    for (var index = 0; index < widget.lines.length; index++) {
      final painter = TextPainter(
        text: TextSpan(
          text: widget.lines[index].texts.join('\n'),
          style: textStyle,
        ),
        textAlign: TextAlign.center,
        textDirection: direction,
        textScaler: scaler,
      )..layout(maxWidth: availableWidth);
      final height = (painter.height + 10).clamp(
        widget.fontSize * 1.2 + 10,
        double.infinity,
      );
      heights[index] = height;
      offsets[index] = runningOffset;
      runningOffset += height;
    }
    _itemHeights = heights;
    _topPadding = widget.lines.isEmpty
        ? 0
        : (viewport * _focusAnchor - heights.first / 2).clamp(
            0.0,
            double.infinity,
          );
    _bottomPadding = widget.lines.isEmpty
        ? 0
        : (viewport * (1 - _focusAnchor) - heights.last / 2).clamp(
            0.0,
            double.infinity,
          );
    _itemOffsets = List<double>.generate(
      offsets.length,
      (index) =>
          _topPadding +
          offsets[index] +
          heights[index] / 2 -
          viewport * _focusAnchor,
      growable: false,
    );
    _scheduleLayoutRetarget(jump: !_hasInitialPosition);
    return true;
  }

  void _updateDebugSnapshot(Duration elapsed, double frameSeconds) {
    if (!_debugOverlayEnabled || elapsed - _lastDebugUpdate < const Duration(milliseconds: 160)) {
      return;
    }
    _lastDebugUpdate = elapsed;
    _debugSnapshot.value = _LyricDebugSnapshot(
      currentIndex: widget.active,
      targetOffset: _motion.target,
      currentOffset: _motion.offset,
      velocity: _motion.velocity,
      userScrolling: _isManuallyBrowsing,
      fps: frameSeconds <= 0 ? 0 : 1 / frameSeconds,
      frameTimeMs: frameSeconds * 1000,
      recompositionCount: _recompositionCount,
    );
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _positionSource?.removeListener(_handlePositionTick);
    _motionTicker.dispose();
    _scrollControllerState?.dispose();
    _debugSnapshot.dispose();
    _resumeFollowTimer?.cancel();
    _browseGuideTimer?.cancel();
    _seekTargetTimer?.cancel();
    _layoutRequestId++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.lines.isEmpty
      ? const Center(child: Text('暂无歌词'))
      : LayoutBuilder(
          builder: (context, constraints) {
            _ensureLayoutMetrics(context, constraints);
            if (_scrollControllerState == null) {
              final initialIndex = widget.active.clamp(
                0,
                _itemOffsets.length - 1,
              );
              final initialOffset = _itemOffsets[initialIndex];
              _scrollControllerState = ScrollController(
                initialScrollOffset: initialOffset,
              );
              _motion.sync(initialOffset, viewportExtent: _viewportHeight);
              _hasInitialPosition = true;
            }
            Widget lyrics = NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              child: ListView.builder(
                key: const ValueKey('mobile_lyrics_scroll_view'),
                controller: _scrollController,
                padding: EdgeInsets.only(
                  top: _topPadding,
                  bottom: _bottomPadding,
                ),
                scrollCacheExtent: const ScrollCacheExtent.viewport(1),
                itemCount: widget.lines.length,
                itemExtentBuilder: (index, dimensions) => _itemHeights[index],
                itemBuilder: (itemContext, index) {
                  _recompositionCount++;
                  final distance = (index - widget.active).abs();
                  return _LyricLineItem(
                    key: ValueKey('mobile_lyric_$index'),
                    line: widget.lines[index],
                    active: index == widget.active,
                    distance: distance,
                    height: _itemHeights[index],
                    fontSize: widget.fontSize,
                    fontFamily: widget.fontFamily,
                    glowEnabled: widget.glowEnabled,
                    glowRadius: widget.glowRadius,
                    brightForeground: widget.brightForeground,
                    position: widget.position,
                    positionListenable: index == widget.active
                        ? widget.positionListenable
                        : null,
                  );
                },
              ),
            );
            if (widget.edgeFadeEnabled) {
              lyrics = ShaderMask(
                key: const ValueKey('mobile_lyrics_edge_fade'),
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black,
                    Colors.black,
                    Colors.transparent,
                  ],
                  stops: [0, 0.10, 0.90, 1],
                ).createShader(bounds),
                child: lyrics,
              );
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                lyrics,
                if (kDebugMode)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton.filledTonal(
                      visualDensity: VisualDensity.compact,
                      tooltip: '歌词滚动调试信息',
                      icon: Icon(
                        _debugOverlayEnabled
                            ? Icons.bug_report
                            : Icons.bug_report_outlined,
                        size: 18,
                      ),
                      onPressed: () => setState(() {
                        _debugOverlayEnabled = !_debugOverlayEnabled;
                      }),
                    ),
                  ),
                if (kDebugMode && _debugOverlayEnabled)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: IgnorePointer(
                      child: ValueListenableBuilder<_LyricDebugSnapshot>(
                        valueListenable: _debugSnapshot,
                        builder: (context, snapshot, _) => _LyricDebugPanel(
                          snapshot: snapshot,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );

}

class _LyricLineItem extends StatelessWidget {
  const _LyricLineItem({
    super.key,
    required this.line,
    required this.active,
    required this.distance,
    required this.height,
    required this.fontSize,
    required this.fontFamily,
    required this.glowEnabled,
    required this.glowRadius,
    required this.brightForeground,
    required this.position,
    required this.positionListenable,
  });

  final LyricLine line;
  final bool active;
  final int distance;
  final double height;
  final double fontSize;
  final String? fontFamily;
  final bool glowEnabled;
  final double glowRadius;
  final bool brightForeground;
  final Duration position;
  final ValueListenable<Duration>? positionListenable;

  double get _opacity => switch (distance) {
    0 => 1,
    1 => .72,
    2 => .58,
    3 => .46,
    _ => .36,
  };

  double get _scale => switch (distance) {
    0 => 1,
    1 => .975,
    _ => .95,
  };

  @override
  Widget build(BuildContext context) {
    final darkForeground =
        brightForeground || Theme.of(context).brightness == Brightness.dark;
    final inactiveBase = darkForeground ? Colors.white : const Color(0xFF757575);
    final inactiveColor = inactiveBase.withValues(alpha: _opacity);
    final karaokeUnplayedColor = darkForeground
        ? Colors.white.withValues(alpha: .50)
        : const Color(0xFF757575).withValues(alpha: .80);
    final glowColor = darkForeground
        ? Colors.white.withValues(alpha: .30)
        : const Color(0xFFBDBDBD).withValues(alpha: .30);
    final style = DefaultTextStyle.of(context).style.copyWith(
      fontFamily: fontFamily,
      fontSize: fontSize,
      height: 1.2,
      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
      color: active ? Theme.of(context).colorScheme.primary : inactiveColor,
      shadows: glowEnabled
          ? [Shadow(color: glowColor, blurRadius: glowRadius)]
          : null,
    );
    final lyric = active
        ? positionListenable == null
              ? _KaraokeLyricText(
                  line: line,
                  position: position,
                  playedColor: style.color!,
                  unplayedColor: karaokeUnplayedColor,
                )
              : ValueListenableBuilder<Duration>(
                  valueListenable: positionListenable!,
                  builder: (context, position, _) => _KaraokeLyricText(
                    line: line,
                    position: position,
                    playedColor: style.color!,
                    unplayedColor: karaokeUnplayedColor,
                  ),
                )
        : Text(line.texts.join('\n'));
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 5),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              style: style,
              textAlign: TextAlign.center,
              child: Center(child: lyric),
            ),
          ),
        ),
      ),
    );
  }
}

class _LyricDebugSnapshot {
  const _LyricDebugSnapshot({
    this.currentIndex = -1,
    this.targetOffset = 0,
    this.currentOffset = 0,
    this.velocity = 0,
    this.userScrolling = false,
    this.fps = 0,
    this.frameTimeMs = 0,
    this.recompositionCount = 0,
  });

  final int currentIndex;
  final double targetOffset;
  final double currentOffset;
  final double velocity;
  final bool userScrolling;
  final double fps;
  final double frameTimeMs;
  final int recompositionCount;
}

class _LyricDebugPanel extends StatelessWidget {
  const _LyricDebugPanel({required this.snapshot});

  final _LyricDebugSnapshot snapshot;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .78),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        child: Text(
          'Index ${snapshot.currentIndex}\n'
          'Target ${snapshot.targetOffset.toStringAsFixed(1)}\n'
          'Offset ${snapshot.currentOffset.toStringAsFixed(1)}\n'
          'Velocity ${snapshot.velocity.toStringAsFixed(1)} px/s\n'
          'User ${snapshot.userScrolling}\n'
          'FPS ${snapshot.fps.toStringAsFixed(1)}\n'
          'Frame ${snapshot.frameTimeMs.toStringAsFixed(2)} ms\n'
          'Builds ${snapshot.recompositionCount}',
        ),
      ),
    ),
  );
}

class _KaraokeLyricText extends StatefulWidget {
  const _KaraokeLyricText({
    required this.line,
    required this.position,
    required this.playedColor,
    required this.unplayedColor,
  });

  final LyricLine line;
  final Duration position;
  final Color playedColor;
  final Color unplayedColor;

  @override
  State<_KaraokeLyricText> createState() => _KaraokeLyricTextState();
}

class _KaraokeLyricTextState extends State<_KaraokeLyricText> {
  final Map<LyricToken, List<int>> _tokenRunes = Map.identity();
  final Map<LyricToken, TextSpan> _playedTokens = Map.identity();
  final Map<LyricToken, TextSpan> _unplayedTokens = Map.identity();
  late TextStyle _playedStyle;
  late TextStyle _unplayedStyle;

  @override
  void initState() {
    super.initState();
    _rebuildCache();
  }

  @override
  void didUpdateWidget(covariant _KaraokeLyricText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.line, widget.line) ||
        oldWidget.playedColor != widget.playedColor ||
        oldWidget.unplayedColor != widget.unplayedColor) {
      _rebuildCache();
    }
  }

  void _rebuildCache() {
    _tokenRunes.clear();
    _playedTokens.clear();
    _unplayedTokens.clear();
    _playedStyle = TextStyle(color: widget.playedColor);
    _unplayedStyle = TextStyle(color: widget.unplayedColor);
    for (final row in widget.line.tokens ?? const <List<LyricToken>>[]) {
      for (final token in row) {
        _tokenRunes[token] = token.text.runes.toList(growable: false);
        _playedTokens[token] = TextSpan(
          text: token.text,
          style: _playedStyle,
        );
        _unplayedTokens[token] = TextSpan(
          text: token.text,
          style: _unplayedStyle,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokenRows = widget.line.tokens;
    if (tokenRows == null || tokenRows.isEmpty) {
      return Text(widget.line.texts.join('\n'));
    }
    final spans = <InlineSpan>[];
    for (var row = 0; row < widget.line.texts.length; row++) {
      if (row > 0) spans.add(const TextSpan(text: '\n'));
      final tokens = row < tokenRows.length ? tokenRows[row] : null;
      if (tokens == null || tokens.isEmpty) {
        spans.add(
          TextSpan(
            text: widget.line.texts[row],
            style: _unplayedStyle,
          ),
        );
        continue;
      }
      for (final token in tokens) {
        _appendTokenSpans(spans, token);
      }
    }
    return Text.rich(TextSpan(children: spans), textAlign: TextAlign.center);
  }

  void _appendTokenSpans(List<InlineSpan> spans, LyricToken token) {
    final durationMs = token.end.inMilliseconds - token.start.inMilliseconds;
    final elapsedMs =
        widget.position.inMilliseconds - token.start.inMilliseconds;
    if (elapsedMs <= 0) {
      spans.add(_unplayedTokens[token]!);
      return;
    }
    if (durationMs <= 0 || elapsedMs >= durationMs) {
      spans.add(_playedTokens[token]!);
      return;
    }
    final runes = _tokenRunes[token]!;
    if (runes.isEmpty) return;
    final completed = (runes.length * elapsedMs / durationMs).floor().clamp(
      0,
      runes.length,
    );
    if (completed > 0) {
      spans.add(
        TextSpan(
          text: String.fromCharCodes(runes, 0, completed),
          style: _playedStyle,
        ),
      );
    }
    if (completed < runes.length) {
      spans.add(
        TextSpan(
          text: String.fromCharCodes(runes, completed),
          style: _unplayedStyle,
        ),
      );
    }
  }
}
