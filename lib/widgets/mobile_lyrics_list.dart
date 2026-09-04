import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable, kDebugMode;
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../page/playlist/playlist_models.dart';
import 'interlude_animation_widget.dart';
import 'lyric_seek_guide.dart';
import 'lyric_scroll_motion.dart';

const int mobileLyricsTopEdgeAlpha = 0x00;
const int mobileLyricsTopFadeSoftAlpha = 0x18;
const int mobileLyricsTopFadeMidAlpha = 0x58;
const int mobileLyricsTopFadeNearAlpha = 0xB8;
const int mobileLyricsBottomFadeNearAlpha = 0xC4;
const int mobileLyricsBottomFadeMidAlpha = 0x74;
const int mobileLyricsBottomFadeSoftAlpha = 0x24;
const Color mobileLyricsBrowseMaskColor = Color(0x4DFFFFFF);
const Duration mobileLyricsBrowseMaskRevealDelay = Duration(milliseconds: 300);
const Duration mobileLyricsBrowseMaskRevealDuration = Duration(
  milliseconds: 200,
);
const Color mobileLyricsBrowseGuideColor = Color(0xB3FFFFFF);
const Duration mobileLyricsFocusTransitionDuration = Duration(
  milliseconds: 520,
);
const Curve mobileLyricsFocusTransitionCurve = Cubic(.33, 0, .2, 1);
const double mobileLyricsActiveScale = 1.1;

double mobileLyricScaleSafeExtent(double contentExtent) =>
    contentExtent * mobileLyricsActiveScale;

double mobileLyricScaleSafeContentWidth(double availableWidth) =>
    availableWidth / mobileLyricsActiveScale;

double mobileLyricsHorizontalInset(TextAlign alignment) => switch (alignment) {
  TextAlign.left || TextAlign.right || TextAlign.start || TextAlign.end => 4,
  _ => 24,
};

String formatMobileLyricsBrowseTime(Duration timestamp) {
  final totalSeconds = timestamp.inSeconds.clamp(0, 359999);
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds ~/ 60) % 60;
  final seconds = totalSeconds % 60;
  final secondLabel = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$secondLabel';
  }
  return '${timestamp.inMinutes.clamp(0, 5999)}:$secondLabel';
}

List<double> mobileLyricsEdgeFadeStops(double viewportHeight) {
  final height = viewportHeight <= 0 ? 1.0 : viewportHeight;
  final topBand = (height * .16)
      .clamp(84.0, 112.0)
      .clamp(0.0, height * .38)
      .toDouble();
  final bottomBand = (height * .18)
      .clamp(96.0, 128.0)
      .clamp(0.0, height * .42)
      .toDouble();
  return [
    0,
    topBand * .16 / height,
    topBand * .38 / height,
    topBand * .68 / height,
    topBand / height,
    1 - bottomBand / height,
    1 - bottomBand * .66 / height,
    1 - bottomBand * .34 / height,
    1 - bottomBand * .13 / height,
    1,
  ];
}

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

  bool selectBrowseTargetAtGlobalPosition(Offset position) {
    final owner = _owner;
    if (owner is _MobileLyricsListState) {
      return owner._selectBrowseTargetAtGlobalPosition(position);
    }
    return false;
  }

  bool selectBrowseTarget() {
    final owner = _owner;
    return owner is _MobileLyricsListState && owner._selectBrowseTarget();
  }

  bool isBrowseTargetAtGlobalPosition(Offset position) {
    final owner = _owner;
    return owner is _MobileLyricsListState &&
        owner._isBrowseTargetAtGlobalPosition(position);
  }
}

class _LyricElasticPulse {
  const _LyricElasticPulse({
    this.id = 0,
    this.displacement = 0,
    this.anchorIndex = 0,
    this.lineDurationSeconds = 1.5,
  });

  final int id;
  final double displacement;
  final int anchorIndex;
  final double lineDurationSeconds;
}

double clampLyricElasticDisplacement(
  double displacement,
  double viewportHeight,
) {
  final limit = (viewportHeight * .28).clamp(56.0, 120.0).toDouble();
  return displacement.clamp(-limit, limit).toDouble();
}

double lyricSeekVisibleTravel(double viewportHeight) =>
    (viewportHeight * .42).clamp(72.0, 180.0).toDouble();

double mobileLyricBlurSigmaForDistance(int distance) => switch (distance) {
  <= 0 => 0,
  1 => .9,
  2 => 1.65,
  3 => 2.35,
  4 => 3,
  _ => 3.4,
};

class MobileLyricsList extends StatefulWidget {
  const MobileLyricsList({
    super.key,
    required this.lines,
    required this.active,
    this.contentIdentity,
    this.activeColor,
    this.fontSize = 20,
    this.fontFamily,
    this.fontWeight = FontWeight.w600,
    this.controller,
    this.edgeFadeEnabled = false,
    this.glowEnabled = false,
    this.glowRadius = 8,
    this.brightForeground = false,
    this.textAlign = TextAlign.center,
    this.elasticScrollEnabled = false,
    this.lineBlurEnabled = false,
    this.highlightActiveLine = false,
    this.isPlaying = true,
    this.position = Duration.zero,
    this.positionListenable,
    this.onBrowseTargetChanged,
    this.onBrowseTargetSelected,
  });

  final List<LyricLine> lines;
  final int active;
  final Object? contentIdentity;
  final Color? activeColor;
  final double fontSize;
  final String? fontFamily;
  final FontWeight fontWeight;
  final MobileLyricsListController? controller;
  final bool edgeFadeEnabled;
  final bool glowEnabled;
  final double glowRadius;
  final bool brightForeground;
  final TextAlign textAlign;
  final bool elasticScrollEnabled;
  final bool lineBlurEnabled;
  final bool highlightActiveLine;
  final bool isPlaying;
  final Duration position;
  final ValueListenable<Duration>? positionListenable;
  final ValueChanged<Duration?>? onBrowseTargetChanged;
  final ValueChanged<Duration>? onBrowseTargetSelected;

  @override
  State<MobileLyricsList> createState() => _MobileLyricsListState();
}

class _MobileLyricsListState extends State<MobileLyricsList>
    with SingleTickerProviderStateMixin {
  static const _focusAnchor = .4;

  ScrollController? _scrollControllerState;
  // A slightly under-damped profile gives the opt-in mode a visible spring
  // return while retaining the existing velocity-continuous retargeting.
  final LyricScrollMotion _motion = LyricScrollMotion(
    dampingRatio: .78,
    frequency: 11,
  );
  final ValueNotifier<_LyricDebugSnapshot> _debugSnapshot = ValueNotifier(
    const _LyricDebugSnapshot(),
  );
  final ValueNotifier<_LyricElasticPulse> _elasticPulse = ValueNotifier(
    const _LyricElasticPulse(),
  );
  final ValueNotifier<_LyricBrowseHighlightFrame> _browseHighlight =
      ValueNotifier(const _LyricBrowseHighlightFrame());
  final GlobalKey _browseTapTargetRenderKey = GlobalKey();
  late final Ticker _motionTicker;
  Duration? _lastTick;
  Duration _lastDebugUpdate = Duration.zero;
  Timer? _resumeFollowTimer;
  Timer? _browseHighlightRevealTimer;
  Timer? _browseChromeExitTimer;
  Timer? _seekTargetTimer;
  Timer? _seekTargetConfirmationTimer;
  bool _isManuallyBrowsing = false;
  bool _browseHighlightVisible = false;
  bool _lyricsPointerDown = false;
  bool _browseSelectionDispatching = false;
  bool _hasInitialPosition = false;
  bool _layoutInvalid = true;
  bool _debugOverlayEnabled = false;
  int _layoutRequestId = 0;
  int _standardScrollGeneration = 0;
  int _seekElasticReplayId = 0;
  int _lyricContentRevision = 0;
  bool _awaitingNextSongLyrics = false;
  int _recompositionCount = 0;
  int? _browseTargetIndex;
  int? _seekTargetIndex;
  Duration? _seekTargetTimestamp;
  double _viewportHeight = 0;
  double _layoutWidth = 0;
  double _topPadding = 0;
  double _bottomPadding = 0;
  double _browseMinimumHitHeight = 0;
  List<double> _itemHeights = const [];
  List<double> _itemOffsets = const [];
  List<LyricLine>? _layoutLines;
  double _layoutFontSize = -1;
  String? _layoutFontFamily;
  TextAlign _layoutTextAlign = TextAlign.center;
  TextDirection? _layoutDirection;
  double _layoutTextScale = -1;

  ScrollController get _scrollController => _scrollControllerState!;

  @override
  void initState() {
    super.initState();
    _motionTicker = createTicker(_onMotionTick);
    widget.controller?._attach(this, _recenterActive, _settleOnTimestamp);
  }

  @override
  void didUpdateWidget(covariant MobileLyricsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this, _recenterActive, _settleOnTimestamp);
    }
    final linesChanged = oldWidget.lines != widget.lines;
    final contentChanged = oldWidget.contentIdentity != widget.contentIdentity;
    if (contentChanged) {
      _awaitingNextSongLyrics = true;
      _resetScrollPositionForNewContent();
    }
    final fontChanged =
        (oldWidget.fontSize - widget.fontSize).abs() >= .01 ||
        oldWidget.fontFamily != widget.fontFamily ||
        oldWidget.fontWeight != widget.fontWeight ||
        oldWidget.textAlign != widget.textAlign;
    if (linesChanged) {
      _lyricContentRevision++;
      _seekElasticReplayId++;
    }
    if (linesChanged || fontChanged || contentChanged) {
      _layoutInvalid = true;
      final replacingNextSongLyrics =
          linesChanged && _awaitingNextSongLyrics && !contentChanged;
      final preserveManualInteraction =
          !contentChanged &&
          !replacingNextSongLyrics &&
          (_lyricsPointerDown || _isManuallyBrowsing);
      final pendingSeekTimestamp = contentChanged ? null : _seekTargetTimestamp;
      if (pendingSeekTimestamp != null && widget.lines.isNotEmpty) {
        final remappedTarget = _nearestLyricIndex(pendingSeekTimestamp);
        _seekTargetTimer?.cancel();
        _seekTargetConfirmationTimer?.cancel();
        _seekTargetIndex = remappedTarget;
        _seekTargetTimestamp = pendingSeekTimestamp;
        _armSeekTargetTimeout(pendingSeekTimestamp, remappedTarget);
        if (widget.active == remappedTarget) {
          _armSeekTargetConfirmation(remappedTarget);
        }
      } else {
        _clearSeekTarget();
      }
      if (!preserveManualInteraction) {
        _resumeAutomaticFollow(notifyBrowseTarget: false);
      }
      if (replacingNextSongLyrics) _resetScrollPositionForNewContent();
      if (oldWidget.lines.isEmpty) _hasInitialPosition = false;
      if (linesChanged && widget.lines.isNotEmpty) {
        _awaitingNextSongLyrics = false;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onBrowseTargetChanged?.call(null);
      });
      if (!preserveManualInteraction) {
        _scheduleLayoutRetarget(
          jump:
              contentChanged ||
              replacingNextSongLyrics ||
              oldWidget.lines.isEmpty,
        );
      }
      return;
    }

    if (oldWidget.elasticScrollEnabled != widget.elasticScrollEnabled) {
      _standardScrollGeneration++;
      _stopMotion();
      if (_scrollControllerState?.hasClients ?? false) {
        _motion.sync(_scrollController.offset, viewportExtent: _viewportHeight);
      }
      _retargetIndex(widget.active, force: true, springLines: false);
    }

    if (oldWidget.active == widget.active) return;
    final seekTarget = _seekTargetIndex;
    if (seekTarget != null) {
      if (widget.active == seekTarget) {
        _armSeekTargetConfirmation(seekTarget);
      } else {
        _seekTargetConfirmationTimer?.cancel();
        _seekTargetConfirmationTimer = null;
      }
      return;
    }
    _retargetIndex(widget.active);
  }

  void _resetScrollPositionForNewContent() {
    _layoutRequestId++;
    _standardScrollGeneration++;
    _seekElasticReplayId++;
    _stopMotion();
    final previousController = _scrollControllerState;
    _scrollControllerState = null;
    _hasInitialPosition = false;
    _motion.sync(0, viewportExtent: _viewportHeight);
    if (previousController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previousController.dispose();
      });
    }
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
        (elapsed - previousTick).inMicroseconds /
        Duration.microsecondsPerSecond;
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

  bool _retargetIndex(
    int index, {
    bool force = false,
    bool springLines = true,
    bool boundedTravel = false,
  }) {
    if (((_lyricsPointerDown || _isManuallyBrowsing) && !force) ||
        index < 0 ||
        index >= _itemOffsets.length) {
      return false;
    }
    return _retargetOffset(
      _itemOffsets[index],
      springLines: springLines,
      anchorIndex: index,
      boundedTravel: boundedTravel,
    );
  }

  bool _retargetOffset(
    double target, {
    bool springLines = false,
    int? anchorIndex,
    bool boundedTravel = false,
  }) {
    if (!_scrollController.hasClients) {
      _scheduleLayoutRetarget();
      return false;
    }
    final clampedTarget = target.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    if (widget.elasticScrollEnabled && springLines) {
      _standardScrollGeneration++;
      final displacement = clampedTarget - _scrollController.offset;
      _stopMotion();
      if (displacement.abs() >= .35) {
        final previous = _elasticPulse.value;
        final visualDisplacement = clampLyricElasticDisplacement(
          displacement,
          _viewportHeight,
        );
        final isLongJump = visualDisplacement.abs() + .5 < displacement.abs();
        final lineDuration = _lineDurationSeconds(anchorIndex ?? widget.active);
        _elasticPulse.value = _LyricElasticPulse(
          id: previous.id + 1,
          displacement: visualDisplacement,
          anchorIndex: anchorIndex ?? widget.active,
          lineDurationSeconds: isLongJump
              ? lineDuration.clamp(.35, .75).toDouble()
              : lineDuration,
        );
        _scrollController.jumpTo(clampedTarget);
      }
      _motion.sync(clampedTarget, viewportExtent: _viewportHeight);
      return true;
    }

    if (widget.elasticScrollEnabled) {
      _standardScrollGeneration++;
      _motion.offset = _scrollController.offset;
      _motion.retarget(clampedTarget, viewportExtent: _viewportHeight);
      _startMotion();
      return true;
    }

    _stopMotion();
    final generation = ++_standardScrollGeneration;
    var animationStart = _scrollController.offset;
    if (boundedTravel) {
      final displacement = clampedTarget - animationStart;
      final visibleTravel = lyricSeekVisibleTravel(_viewportHeight);
      if (displacement.abs() > visibleTravel) {
        animationStart = clampedTarget - displacement.sign * visibleTravel;
        _scrollController.jumpTo(animationStart);
      }
    }
    _motion.sync(animationStart, viewportExtent: _viewportHeight);
    unawaited(
      _scrollController
          .animateTo(
            clampedTarget,
            duration: mobileLyricsFocusTransitionDuration,
            curve: mobileLyricsFocusTransitionCurve,
          )
          .then((_) {
            if (!mounted || generation != _standardScrollGeneration) return;
            _motion.sync(
              _scrollController.offset,
              viewportExtent: _viewportHeight,
            );
          }),
    );
    return true;
  }

  double _lineDurationSeconds(int index) {
    if (index < 0 || index + 1 >= widget.lines.length) return 1.5;
    final duration =
        widget.lines[index + 1].timestamp.inMicroseconds -
        widget.lines[index].timestamp.inMicroseconds;
    return duration <= 0 ? 1.5 : duration / Duration.microsecondsPerSecond;
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
    _standardScrollGeneration++;
    _scrollController.jumpTo(target);
    _motion.sync(target, viewportExtent: _viewportHeight);
    _hasInitialPosition = true;
  }

  void _scheduleLayoutRetarget({bool jump = false}) {
    final requestId = ++_layoutRequestId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          requestId != _layoutRequestId ||
          _lyricsPointerDown ||
          _isManuallyBrowsing) {
        return;
      }
      final controller = _scrollControllerState;
      if (controller == null ||
          !controller.hasClients ||
          _itemOffsets.isEmpty) {
        return;
      }
      final seekTarget = _seekTargetIndex;
      if (seekTarget != null) {
        _retargetIndex(seekTarget, force: true, boundedTravel: true);
        return;
      }
      if (jump || !_hasInitialPosition) {
        _jumpToIndex(widget.active.clamp(0, _itemOffsets.length - 1));
      } else {
        _retargetIndex(widget.active, force: true, springLines: false);
      }
    });
  }

  void _startManualInteraction() {
    if (!mounted) return;
    _layoutRequestId++;
    _seekElasticReplayId++;
    _clearSeekTarget(rebuild: true);
    _browseHighlightRevealTimer?.cancel();
    _browseHighlightRevealTimer = null;
    _browseChromeExitTimer?.cancel();
    _browseChromeExitTimer = null;
    if (!_isManuallyBrowsing || _browseHighlightVisible) {
      setState(() {
        _isManuallyBrowsing = true;
        _browseHighlightVisible = false;
      });
    }
    _standardScrollGeneration++;
    _stopMotion();
    final previousPulse = _elasticPulse.value;
    _elasticPulse.value = _LyricElasticPulse(id: previousPulse.id + 1);
    _motion.sync(
      _scrollController.hasClients ? _scrollController.offset : 0,
      viewportExtent: _viewportHeight,
    );
    _resumeFollowTimer?.cancel();
    _resumeFollowTimer = null;
    _updateBrowseTargetFromOffset(force: true);
  }

  void _scheduleResumeFollowTimer() {
    if (!mounted || !_isManuallyBrowsing) return;
    _scheduleBrowseHighlightReveal();
    _resumeFollowTimer?.cancel();
    _resumeFollowTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _resumeFollowTimer = null;
      if (_lyricsPointerDown) return;
      if (_scrollController.hasClients &&
          _scrollController.position.isScrollingNotifier.value) {
        return;
      }
      _resumeAutomaticFollow();
      _retargetIndex(widget.active, force: true);
    });
  }

  void _scheduleBrowseHighlightReveal() {
    _browseHighlightRevealTimer?.cancel();
    _browseHighlightRevealTimer = Timer(mobileLyricsBrowseMaskRevealDelay, () {
      if (!mounted || !_isManuallyBrowsing || _browseTargetIndex == null) {
        return;
      }
      _browseHighlightRevealTimer = null;
      setState(() => _browseHighlightVisible = true);
    });
  }

  void _resumeAutomaticFollow({bool notifyBrowseTarget = true}) {
    _resumeFollowTimer?.cancel();
    _resumeFollowTimer = null;
    _browseHighlightRevealTimer?.cancel();
    _browseHighlightRevealTimer = null;
    _browseChromeExitTimer?.cancel();
    _browseChromeExitTimer = null;
    final wasManuallyBrowsing = _isManuallyBrowsing;
    final animateExit =
        _browseHighlightVisible && _browseHighlight.value.entry != null;
    _isManuallyBrowsing = false;
    _browseHighlightVisible = false;
    if (animateExit) {
      _browseChromeExitTimer = Timer(mobileLyricsBrowseMaskRevealDuration, () {
        if (!mounted || _isManuallyBrowsing || _browseHighlightVisible) return;
        _browseChromeExitTimer = null;
        setState(() => _browseTargetIndex = null);
        _clearBrowseHighlight();
      });
    } else {
      _browseTargetIndex = null;
      _clearBrowseHighlight();
    }
    if (notifyBrowseTarget) widget.onBrowseTargetChanged?.call(null);
    if ((wasManuallyBrowsing || animateExit) && mounted) setState(() {});
  }

  bool _selectBrowseTarget({bool requireVisible = true}) {
    final target = _browseTargetIndex;
    if (!_isManuallyBrowsing ||
        (requireVisible && !_browseHighlightVisible) ||
        target == null ||
        target < 0 ||
        target >= widget.lines.length) {
      return false;
    }
    _browseSelectionDispatching = true;
    try {
      widget.onBrowseTargetSelected?.call(widget.lines[target].timestamp);
    } finally {
      _browseSelectionDispatching = false;
    }
    return true;
  }

  double _browseHitHeight(_LyricBrowseHighlightEntry entry) =>
      entry.height < _browseMinimumHitHeight
      ? _browseMinimumHitHeight
      : entry.height;

  bool _browseTargetContainsGlobalPosition(Offset position) {
    final renderObject = _browseTapTargetRenderKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;
    final localPosition = renderObject.globalToLocal(position);
    return (Offset.zero & renderObject.size).contains(localPosition);
  }

  bool _isBrowseTargetAtGlobalPosition(Offset position) =>
      _isManuallyBrowsing &&
      _browseHighlightVisible &&
      _browseTargetIndex != null &&
      widget.onBrowseTargetSelected != null &&
      _browseTargetContainsGlobalPosition(position);

  bool _selectBrowseTargetAtGlobalPosition(Offset position) {
    if (!_isBrowseTargetAtGlobalPosition(position)) {
      return false;
    }
    _selectBrowseTarget();
    return true;
  }

  void _handleLyricsPointerDown(PointerDownEvent event) {
    _lyricsPointerDown = true;
    _layoutRequestId++;
    _standardScrollGeneration++;
    _stopMotion();
    if (!_isManuallyBrowsing && _scrollController.hasClients) {
      final frozenOffset = _scrollController.offset;
      _scrollController.jumpTo(frozenOffset);
      _motion.sync(frozenOffset, viewportExtent: _viewportHeight);
    }
    _resumeFollowTimer?.cancel();
    _resumeFollowTimer = null;
  }

  void _handleLyricsPointerMove(PointerMoveEvent event) {
    // Scrolling is owned by the list. The jump target has its own tap
    // recognizer, so a drag automatically rejects the jump in the gesture
    // arena instead of relying on a second, timing-sensitive pointer latch.
  }

  void _handleLyricsPointerEnd(PointerEvent event) {
    if (!_lyricsPointerDown) return;
    _lyricsPointerDown = false;
    final scrollStillActive =
        _scrollController.hasClients &&
        _scrollController.position.isScrollingNotifier.value;
    if (!_isManuallyBrowsing) {
      if (!scrollStillActive) {
        _scheduleLayoutRetarget(jump: !_hasInitialPosition);
      }
      return;
    }
    if (_isManuallyBrowsing &&
        _resumeFollowTimer == null &&
        !scrollStillActive) {
      _scheduleResumeFollowTimer();
    }
  }

  void _clearBrowseHighlight() {
    if (_browseHighlight.value.entry == null) return;
    _browseHighlight.value = const _LyricBrowseHighlightFrame();
  }

  void _updateBrowseHighlightForOffset(double offset) {
    final target = _browseTargetIndex;
    if (!_isManuallyBrowsing ||
        target == null ||
        _itemOffsets.isEmpty ||
        _itemHeights.isEmpty ||
        _viewportHeight <= 0) {
      _clearBrowseHighlight();
      return;
    }
    final anchorY = _viewportHeight * _focusAnchor;
    final centerY = anchorY + _itemOffsets[target] - offset;
    _browseHighlight.value = _LyricBrowseHighlightFrame(
      entry: _LyricBrowseHighlightEntry(
        top: centerY - _itemHeights[target] / 2,
        height: _itemHeights[target],
      ),
    );
  }

  void _updateBrowseTargetFromOffset({bool force = false}) {
    if (!_isManuallyBrowsing ||
        widget.lines.isEmpty ||
        !_scrollController.hasClients ||
        _itemOffsets.isEmpty) {
      return;
    }
    final contentAnchor =
        _scrollController.offset + _viewportHeight * _focusAnchor;
    var low = 0;
    var high = _itemOffsets.length - 1;
    while (low < high) {
      final mid = (low + high) >> 1;
      final itemCenter = _itemOffsets[mid] + _viewportHeight * _focusAnchor;
      if (itemCenter < contentAnchor) {
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
      if ((contentAnchor - previousCenter).abs() <
          (contentAnchor - currentCenter).abs()) {
        index--;
      }
    }
    final changed = index != _browseTargetIndex;
    if (changed) {
      setState(() => _browseTargetIndex = index);
      widget.onBrowseTargetChanged?.call(widget.lines[index].timestamp);
    } else if (force) {
      widget.onBrowseTargetChanged?.call(widget.lines[index].timestamp);
    }
    _updateBrowseHighlightForOffset(_scrollController.offset);
  }

  void _recenterActive() {
    _clearSeekTarget();
    _resumeAutomaticFollow();
    _scheduleLayoutRetarget(jump: true);
  }

  void _settleOnTimestamp(Duration timestamp) {
    if (widget.lines.isEmpty) return;
    final fromBrowseSelection = _browseSelectionDispatching;
    _resumeAutomaticFollow();

    final targetIndex = _nearestLyricIndex(timestamp);

    _seekTargetTimer?.cancel();
    _seekTargetTimestamp = timestamp;
    final previousPulseId = _elasticPulse.value.id;
    final elasticReplayId = ++_seekElasticReplayId;
    final seekLines = widget.lines;
    setState(() {
      _seekTargetIndex = targetIndex;
    });
    final retargeted = _retargetIndex(
      targetIndex,
      force: true,
      boundedTravel: true,
    );
    if (!retargeted) _scheduleLayoutRetarget();
    if (fromBrowseSelection) {
      final pulse = _elasticPulse.value;
      _elasticPulse.value = _LyricElasticPulse(
        id: pulse.id + 1,
        anchorIndex: targetIndex,
      );
    }
    if (!fromBrowseSelection &&
        widget.elasticScrollEnabled &&
        _elasticPulse.value.id == previousPulseId) {
      final currentPosition =
          widget.positionListenable?.value ?? widget.position;
      final direction = timestamp >= currentPosition ? 1.0 : -1.0;
      _elasticPulse.value = _LyricElasticPulse(
        id: previousPulseId + 1,
        displacement: direction * 14,
        anchorIndex: targetIndex,
        lineDurationSeconds: .45,
      );
    }
    if (!fromBrowseSelection && widget.elasticScrollEnabled) {
      final currentPosition =
          widget.positionListenable?.value ?? widget.position;
      final direction = timestamp >= currentPosition ? 1.0 : -1.0;
      final pulse = _elasticPulse.value;
      final displacement = pulse.displacement.abs() >= .35
          ? pulse.displacement
          : direction * 14;
      final lineDuration = pulse.lineDurationSeconds.clamp(.35, .75).toDouble();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            elasticReplayId != _seekElasticReplayId ||
            !identical(widget.lines, seekLines) ||
            !widget.elasticScrollEnabled ||
            targetIndex >= widget.lines.length) {
          return;
        }
        final latest = _elasticPulse.value;
        _elasticPulse.value = _LyricElasticPulse(
          id: latest.id + 1,
          displacement: displacement,
          anchorIndex: targetIndex,
          lineDurationSeconds: lineDuration,
        );
      });
      WidgetsBinding.instance.scheduleFrame();
    }
    _armSeekTargetTimeout(timestamp, targetIndex);
    if (widget.active == targetIndex) {
      _armSeekTargetConfirmation(targetIndex);
    }
  }

  int _nearestLyricIndex(Duration timestamp) {
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
    return targetIndex;
  }

  void _armSeekTargetTimeout(Duration timestamp, int targetIndex) {
    _seekTargetTimer?.cancel();
    _seekTargetTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted ||
          _seekTargetTimestamp != timestamp ||
          _seekTargetIndex != targetIndex) {
        return;
      }
      _clearSeekTarget(rebuild: true);
      _retargetIndex(widget.active, force: true);
    });
  }

  void _armSeekTargetConfirmation(int targetIndex) {
    final timestamp = _seekTargetTimestamp;
    if (timestamp == null || _seekTargetIndex != targetIndex) return;
    _seekTargetConfirmationTimer?.cancel();
    _seekTargetConfirmationTimer = Timer(const Duration(milliseconds: 750), () {
      if (!mounted ||
          _seekTargetTimestamp != timestamp ||
          _seekTargetIndex != targetIndex ||
          widget.active != targetIndex) {
        return;
      }
      _clearSeekTarget(rebuild: true);
    });
  }

  void _clearSeekTarget({bool rebuild = false}) {
    final hadTarget = _seekTargetIndex != null;
    _seekTargetTimer?.cancel();
    _seekTargetTimer = null;
    _seekTargetConfirmationTimer?.cancel();
    _seekTargetConfirmationTimer = null;
    _seekTargetIndex = null;
    _seekTargetTimestamp = null;
    if (rebuild && hadTarget && mounted) setState(() {});
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
        widget.textAlign == _layoutTextAlign &&
        _layoutDirection == direction &&
        (_layoutTextScale - textScale).abs() < .001;
    if (unchanged) return false;

    _layoutInvalid = false;
    _layoutLines = widget.lines;
    _layoutWidth = width;
    _viewportHeight = viewport;
    _layoutFontSize = widget.fontSize;
    _layoutFontFamily = widget.fontFamily;
    _layoutTextAlign = widget.textAlign;
    _layoutDirection = direction;
    _layoutTextScale = textScale;

    final horizontalInset = mobileLyricsHorizontalInset(widget.textAlign);
    final availableWidth = mobileLyricScaleSafeContentWidth(
      (width - horizontalInset * 2).clamp(1.0, double.infinity),
    );
    final textStyle = DefaultTextStyle.of(context).style.copyWith(
      fontFamily: widget.fontFamily,
      fontSize: widget.fontSize,
      fontWeight: widget.fontWeight,
      height: 1.2,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final lineMetricPainter = TextPainter(
      text: TextSpan(text: 'M', style: textStyle),
      textDirection: direction,
      textScaler: scaler,
    )..layout(maxWidth: availableWidth);
    _browseMinimumHitHeight = lineMetricPainter.height * 3 + 10;
    final heights = List<double>.filled(widget.lines.length, 0);
    final offsets = List<double>.filled(widget.lines.length, 0);
    var runningOffset = 0.0;
    for (var index = 0; index < widget.lines.length; index++) {
      final painter = TextPainter(
        text: TextSpan(
          text: widget.lines[index].texts.join('\n'),
          style: textStyle,
        ),
        textAlign: widget.textAlign,
        textDirection: direction,
        textScaler: scaler,
      )..layout(maxWidth: availableWidth);
      final contentHeight = (painter.height + 10).clamp(
        widget.fontSize * 1.2 + 10,
        double.infinity,
      );
      // AnimatedScale changes paint bounds without changing sliver geometry.
      // Reserve the maximum painted extent so a departing active line stays
      // mounted until its enlarged pixels have actually left the viewport.
      final height = mobileLyricScaleSafeExtent(contentHeight);
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
    if (!_debugOverlayEnabled ||
        elapsed - _lastDebugUpdate < const Duration(milliseconds: 160)) {
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
    _motionTicker.dispose();
    _scrollControllerState?.dispose();
    _debugSnapshot.dispose();
    _elasticPulse.dispose();
    _browseHighlight.dispose();
    _resumeFollowTimer?.cancel();
    _browseHighlightRevealTimer?.cancel();
    _browseChromeExitTimer?.cancel();
    _seekTargetTimer?.cancel();
    _seekTargetConfirmationTimer?.cancel();
    _layoutRequestId++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.lines.isEmpty
      ? const Center(child: Text('暂无歌词'))
      : LayoutBuilder(
          builder: (context, constraints) {
            _ensureLayoutMetrics(context, constraints);
            final displayedActive = (_seekTargetIndex ?? widget.active).clamp(
              0,
              widget.lines.length - 1,
            );
            final displayedPosition = _seekTargetIndex == null
                ? widget.position
                : widget.lines[displayedActive].timestamp;
            if (_scrollControllerState == null) {
              final initialIndex = displayedActive.clamp(
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
              child: KeyedSubtree(
                key: ValueKey((
                  'mobile_lyrics_content',
                  widget.contentIdentity,
                )),
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
                    final distance = (index - displayedActive).abs();
                    final browseTarget =
                        _isManuallyBrowsing && index == _browseTargetIndex;
                    final browseHighlighted =
                        browseTarget && _browseHighlightVisible;
                    Widget item = _LyricLineItem(
                      key: ValueKey('mobile_lyric_$index'),
                      line: widget.lines[index],
                      active: index == displayedActive,
                      distance: distance,
                      height: _itemHeights[index],
                      fontSize: widget.fontSize,
                      fontFamily: widget.fontFamily,
                      activeColor: widget.activeColor,
                      styleIdentity: (
                        widget.contentIdentity,
                        widget.activeColor?.toARGB32(),
                      ),
                      fontWeight: widget.fontWeight,
                      glowEnabled: widget.glowEnabled,
                      glowRadius: widget.glowRadius,
                      brightForeground: widget.brightForeground,
                      textAlign: widget.textAlign,
                      lineBlurEnabled: widget.lineBlurEnabled,
                      highlightActiveLine: widget.highlightActiveLine,
                      browseHighlighted: browseHighlighted,
                      lineBlurSuppressed: _isManuallyBrowsing,
                      isPlaying: widget.isPlaying,
                      position: displayedPosition,
                      positionListenable:
                          _seekTargetIndex == null && index == displayedActive
                          ? widget.positionListenable
                          : null,
                    );
                    if (widget.elasticScrollEnabled) {
                      item = _ElasticLyricLine(
                        key: ValueKey(
                          'mobile_lyric_elastic_${_lyricContentRevision}_$index',
                        ),
                        index: index,
                        pulse: _elasticPulse,
                        child: item,
                      );
                    }
                    return item;
                  },
                ),
              ),
            );
            lyrics = Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: AnimatedOpacity(
                    key: const ValueKey('mobile_lyrics_browse_highlight'),
                    opacity: _browseHighlightVisible ? 1 : 0,
                    duration: mobileLyricsBrowseMaskRevealDuration,
                    curve: Curves.easeOutCubic,
                    child: IgnorePointer(
                      child: ValueListenableBuilder<_LyricBrowseHighlightFrame>(
                        valueListenable: _browseHighlight,
                        builder: (context, frame, _) =>
                            TweenAnimationBuilder<double>(
                              key: const ValueKey(
                                'mobile_lyrics_browse_highlight_scale',
                              ),
                              tween: Tween<double>(
                                begin: .86,
                                end: _browseHighlightVisible ? 1 : .86,
                              ),
                              duration: mobileLyricsBrowseMaskRevealDuration,
                              curve: Curves.easeOutCubic,
                              builder: (context, scale, _) => CustomPaint(
                                painter: _LyricBrowseHighlightPainter(
                                  frame: frame,
                                  scale: scale,
                                ),
                              ),
                            ),
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: AnimatedSwitcher(
                    duration: mobileLyricsBrowseMaskRevealDuration,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: _isManuallyBrowsing && _browseTargetIndex != null
                        ? KeyedSubtree(
                            key: const ValueKey(
                              'mobile_lyrics_browse_time_visible',
                            ),
                            child:
                                ValueListenableBuilder<
                                  _LyricBrowseHighlightFrame
                                >(
                                  valueListenable: _browseHighlight,
                                  builder: (context, frame, _) {
                                    final entry = frame.entry;
                                    if (entry == null) {
                                      return const SizedBox.shrink();
                                    }
                                    return LyricSeekGuide(
                                      timeLabel: formatMobileLyricsBrowseTime(
                                        widget
                                            .lines[_browseTargetIndex!]
                                            .timestamp,
                                      ),
                                      contentColor:
                                          mobileLyricsBrowseGuideColor,
                                      centerY: entry.top + entry.height / 2,
                                      timeOnLeft:
                                          widget.textAlign == TextAlign.right ||
                                          widget.textAlign == TextAlign.end,
                                    );
                                  },
                                ),
                          )
                        : const SizedBox.expand(
                            key: ValueKey('mobile_lyrics_browse_time_hidden'),
                          ),
                  ),
                ),
                lyrics,
                if (_isManuallyBrowsing &&
                    _browseHighlightVisible &&
                    _browseTargetIndex != null &&
                    widget.onBrowseTargetSelected != null)
                  Positioned.fill(
                    child: ValueListenableBuilder<_LyricBrowseHighlightFrame>(
                      valueListenable: _browseHighlight,
                      builder: (context, frame, _) {
                        final entry = frame.entry;
                        if (entry == null) return const SizedBox.shrink();
                        final hitHeight = _browseHitHeight(entry);
                        final centerY = entry.top + entry.height / 2;
                        return Align(
                          alignment: Alignment.topCenter,
                          child: Transform.translate(
                            offset: Offset(0, centerY - hitHeight / 2),
                            child: SizedBox(
                              key: const ValueKey(
                                'mobile_lyrics_browse_tap_target',
                              ),
                              width: double.infinity,
                              height: hitHeight,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _selectBrowseTarget,
                                child: SizedBox(key: _browseTapTargetRenderKey),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
            lyrics = Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _handleLyricsPointerDown,
              onPointerMove: _handleLyricsPointerMove,
              onPointerUp: _handleLyricsPointerEnd,
              onPointerCancel: _handleLyricsPointerEnd,
              child: lyrics,
            );
            if (widget.edgeFadeEnabled) {
              lyrics = ShaderMask(
                key: const ValueKey('mobile_lyrics_edge_fade'),
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: const [
                    // Use several low-contrast steps over a wider band so a
                    // line remains perceptible until it actually reaches the
                    // viewport edge instead of crossing a visible cutoff.
                    Color(mobileLyricsTopEdgeAlpha << 24),
                    Color(mobileLyricsTopFadeSoftAlpha << 24),
                    Color(mobileLyricsTopFadeMidAlpha << 24),
                    Color(mobileLyricsTopFadeNearAlpha << 24),
                    Colors.black,
                    Colors.black,
                    Color(mobileLyricsBottomFadeNearAlpha << 24),
                    Color(mobileLyricsBottomFadeMidAlpha << 24),
                    Color(mobileLyricsBottomFadeSoftAlpha << 24),
                    Colors.transparent,
                  ],
                  stops: mobileLyricsEdgeFadeStops(bounds.height),
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
                        builder: (context, snapshot, _) =>
                            _LyricDebugPanel(snapshot: snapshot),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
}

class _ElasticLyricLine extends StatefulWidget {
  const _ElasticLyricLine({
    super.key,
    required this.index,
    required this.pulse,
    required this.child,
  });

  final int index;
  final ValueListenable<_LyricElasticPulse> pulse;
  final Widget child;

  @override
  State<_ElasticLyricLine> createState() => _ElasticLyricLineState();
}

class _ElasticLyricLineState extends State<_ElasticLyricLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
  );
  Timer? _delayTimer;
  int _lastPulseId = 0;
  double _pendingDurationSeconds = 1.5;

  @override
  void initState() {
    super.initState();
    widget.pulse.addListener(_handlePulse);
  }

  @override
  void didUpdateWidget(covariant _ElasticLyricLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pulse == widget.pulse) return;
    oldWidget.pulse.removeListener(_handlePulse);
    widget.pulse.addListener(_handlePulse);
  }

  void _handlePulse() {
    final pulse = widget.pulse.value;
    if (pulse.id == _lastPulseId) return;
    _lastPulseId = pulse.id;
    _delayTimer?.cancel();
    _controller.stop();

    if (pulse.displacement.abs() < .35) {
      _controller.value = 0;
      return;
    }

    _controller.value = pulse.displacement;
    _pendingDurationSeconds = pulse.lineDurationSeconds;
    final distance = (widget.index - pulse.anchorIndex).abs();
    if (distance > 6) {
      // Cached rows outside the visible elastic wave must not keep their own
      // spring ticker alive. They cannot be seen, but collectively add raster
      // and scheduling pressure when glow is enabled.
      _controller.value = 0;
      return;
    }
    final delayStep = (_pendingDurationSeconds * 50).clamp(12.0, 60.0);
    final delay = Duration(milliseconds: ((distance + 1) * delayStep).round());
    _delayTimer = Timer(delay, _startSpring);
  }

  void _startSpring() {
    if (!mounted) return;
    final durationSquared = _pendingDurationSeconds * _pendingDurationSeconds;
    final stiffness = (200 / (durationSquared > 0 ? durationSquared : 1))
        .clamp(100.0, 200.0)
        .toDouble();
    final durationProgress = (_pendingDurationSeconds / 1.5)
        .clamp(0.0, 1.0)
        .toDouble();
    final spring = SpringDescription.withDampingRatio(
      mass: 1,
      stiffness: stiffness,
      ratio: 1 - .3 * durationProgress,
    );
    _controller.animateWith(
      SpringSimulation(
        spring,
        _controller.value,
        0,
        0,
        tolerance: const Tolerance(distance: .5, velocity: .1),
      ),
    );
  }

  @override
  void dispose() {
    widget.pulse.removeListener(_handlePulse);
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) => Transform.translate(
      key: ValueKey('mobile_lyric_elastic_transform_${widget.index}'),
      offset: Offset(0, _controller.value),
      child: child,
    ),
  );
}

class _LyricBrowseHighlightFrame {
  const _LyricBrowseHighlightFrame({this.entry});

  final _LyricBrowseHighlightEntry? entry;
}

class _LyricBrowseHighlightEntry {
  const _LyricBrowseHighlightEntry({required this.top, required this.height});

  final double top;
  final double height;
}

class _LyricBrowseHighlightPainter extends CustomPainter {
  const _LyricBrowseHighlightPainter({
    required this.frame,
    required this.scale,
  });

  final _LyricBrowseHighlightFrame frame;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final entry = frame.entry;
    if (entry == null || size.width <= 0) return;
    final targetRect = Rect.fromLTWH(
      0,
      entry.top + 2,
      size.width,
      (entry.height - 4).clamp(1.0, double.infinity),
    );
    final rect = Rect.fromCenter(
      center: targetRect.center,
      width: targetRect.width * scale,
      height: targetRect.height * scale,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      Paint()
        ..style = PaintingStyle.fill
        ..color = mobileLyricsBrowseMaskColor,
    );
  }

  @override
  bool shouldRepaint(covariant _LyricBrowseHighlightPainter oldDelegate) =>
      !identical(frame, oldDelegate.frame) || oldDelegate.scale != scale;
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
    required this.activeColor,
    required this.styleIdentity,
    required this.fontWeight,
    required this.glowEnabled,
    required this.glowRadius,
    required this.brightForeground,
    required this.textAlign,
    required this.lineBlurEnabled,
    required this.highlightActiveLine,
    required this.browseHighlighted,
    required this.lineBlurSuppressed,
    required this.isPlaying,
    required this.position,
    required this.positionListenable,
  });

  final LyricLine line;
  final bool active;
  final int distance;
  final double height;
  final double fontSize;
  final String? fontFamily;
  final Color? activeColor;
  final Object? styleIdentity;
  final FontWeight fontWeight;
  final bool glowEnabled;
  final double glowRadius;
  final bool brightForeground;
  final TextAlign textAlign;
  final bool lineBlurEnabled;
  final bool highlightActiveLine;
  final bool browseHighlighted;
  final bool lineBlurSuppressed;
  final bool isPlaying;
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
    0 => mobileLyricsActiveScale,
    _ => 1,
  };

  Alignment get _alignment => switch (textAlign) {
    TextAlign.left || TextAlign.start => Alignment.centerLeft,
    TextAlign.right || TextAlign.end => Alignment.centerRight,
    _ => Alignment.center,
  };

  double get _blurSigma {
    if (!lineBlurEnabled || lineBlurSuppressed || active || distance <= 0) {
      return 0;
    }
    return mobileLyricBlurSigmaForDistance(distance);
  }

  @override
  Widget build(BuildContext context) {
    final darkForeground =
        brightForeground || Theme.of(context).brightness == Brightness.dark;
    final inactiveBase = darkForeground
        ? Colors.white
        : const Color(0xFF757575);
    final inactiveColor = inactiveBase.withValues(alpha: _opacity);
    final karaokeUnplayedColor = darkForeground
        ? Colors.white.withValues(alpha: .50)
        : const Color(0xFF757575).withValues(alpha: .80);
    final resolvedActiveColor = highlightActiveLine
        ? Colors.white
        : activeColor ?? Theme.of(context).colorScheme.primary;
    final browseHighlightColor = highlightActiveLine
        ? Colors.white
        : resolvedActiveColor;
    final lineColor = browseHighlighted
        ? browseHighlightColor
        : active
        ? resolvedActiveColor
        : inactiveColor;
    final style = DefaultTextStyle.of(context).style.copyWith(
      fontFamily: fontFamily,
      fontSize: fontSize,
      height: 1.2,
      fontWeight: fontWeight,
      color: lineColor,
      shadows: null,
    );
    // Keep the expensive blurred glyph raster independent from the line's
    // distance opacity. As the active line advances, most visible lyrics only
    // change alpha; applying that with a composited Opacity layer lets their
    // cached glow textures survive instead of repainting every blur.
    final glowStyle = style.copyWith(color: Colors.transparent);
    final glowColor = lineColor.withValues(alpha: .30);
    Widget buildLyric(Duration currentPosition) {
      if (line.isInterlude) {
        if (!active) return const SizedBox.shrink();
        return Align(
          alignment: _alignment,
          child: InterludeAnimationWidget(
            isCurrent: true,
            baseColor: inactiveColor,
            highlightColor: resolvedActiveColor.withValues(alpha: .9),
            startTime: line.timestamp,
            interludeDuration: line.interludeDuration ?? Duration.zero,
            currentTime: currentPosition,
            isPlaying: isPlaying,
          ),
        );
      }
      // Highlight mode renders the entire active line with one color. Building
      // token-by-token karaoke spans here adds layout and paint work without
      // changing the result, especially when active lines change while the
      // list is scrolling. Keep that hot path to a single lightweight Text.
      if (!active || highlightActiveLine) {
        return Text(line.texts.join('\n'), textAlign: textAlign);
      }
      return _KaraokeLyricText(
        line: line,
        position: currentPosition,
        playedColor: style.color!,
        unplayedColor: browseHighlighted
            ? browseHighlightColor
            : highlightActiveLine
            ? Colors.white
            : karaokeUnplayedColor,
        textAlign: textAlign,
      );
    }

    final followsPlaybackPosition =
        active &&
        positionListenable != null &&
        (line.isInterlude || !highlightActiveLine);
    final lyric = followsPlaybackPosition
        ? ValueListenableBuilder<Duration>(
            valueListenable: positionListenable!,
            builder: (context, currentPosition, _) =>
                buildLyric(currentPosition),
          )
        : buildLyric(position);
    final lyricWithGlow = glowEnabled && !line.isInterlude
        ? Stack(
            fit: StackFit.passthrough,
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Opacity(
                  key: const ValueKey('mobile_lyric_glow_opacity'),
                  opacity: lineColor.a,
                  child: RepaintBoundary(
                    child: IgnorePointer(
                      child: CustomPaint(
                        key: const ValueKey('mobile_lyric_glow_layer'),
                        isComplex: true,
                        willChange: false,
                        painter: MobileLyricGlowPainter(
                          text: line.texts.join('\n'),
                          style: glowStyle,
                          color: glowColor,
                          blurRadius: glowRadius,
                          textAlign: textAlign,
                          textDirection: Directionality.of(context),
                          textScaler: MediaQuery.textScalerOf(context),
                          locale: Localizations.maybeLocaleOf(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              lyric,
            ],
          )
        : lyric;
    final sigma = _blurSigma;
    final lyricPaintLayer = Padding(
      key: const ValueKey('mobile_lyric_filter_safe_area'),
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: lyricWithGlow,
    );
    final effectiveLyric = lineBlurEnabled
        ? _AnimatedLyricBlur(
            sigma: sigma,
            child: RepaintBoundary(child: lyricPaintLayer),
          )
        : lyricPaintLayer;
    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: mobileLyricsHorizontalInset(textAlign),
        ),
        child: FractionallySizedBox(
          key: const ValueKey('mobile_lyric_scale_safe_content'),
          widthFactor: 1 / mobileLyricsActiveScale,
          heightFactor: 1 / mobileLyricsActiveScale,
          alignment: _alignment,
          child: AnimatedScale(
            scale: _scale,
            duration: active
                ? const Duration(milliseconds: 220)
                : const Duration(milliseconds: 280),
            curve: active ? Curves.easeOutCubic : const Cubic(.16, 1, .3, 1),
            alignment: _alignment,
            // Keep the expensive glyph and glow raster below the transform.
            // The scale-safe parent reserves the transformed paint bounds, so
            // sliver culling cannot remove a still-visible departing line.
            child: RepaintBoundary(
              key: const ValueKey('mobile_lyric_scaled_paint'),
              child: AnimatedDefaultTextStyle(
                key: ValueKey(styleIdentity),
                duration: active
                    ? const Duration(milliseconds: 210)
                    : const Duration(milliseconds: 280),
                curve: active
                    ? Curves.easeOutCubic
                    : const Cubic(.16, 1, .3, 1),
                style: style,
                textAlign: textAlign,
                child: Align(
                  alignment: _alignment,
                  child: SizedBox(
                    width: double.infinity,
                    child: effectiveLyric,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedLyricBlur extends ImplicitlyAnimatedWidget {
  const _AnimatedLyricBlur({required this.sigma, required this.child})
    : super(
        duration: mobileLyricsFocusTransitionDuration,
        curve: mobileLyricsFocusTransitionCurve,
      );

  final double sigma;
  final Widget child;

  @override
  ImplicitlyAnimatedWidgetState<_AnimatedLyricBlur> createState() =>
      _AnimatedLyricBlurState();
}

class _AnimatedLyricBlurState
    extends AnimatedWidgetBaseState<_AnimatedLyricBlur> {
  Tween<double>? _sigma;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _sigma =
        visitor(
              _sigma,
              widget.sigma,
              (value) => Tween<double>(begin: value as double),
            )
            as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) {
    final sigma = _sigma?.evaluate(animation) ?? widget.sigma;
    return ImageFiltered(
      key: const ValueKey('mobile_lyric_blur_filter'),
      enabled: sigma > .01,
      imageFilter: _cachedLyricBlur(sigma),
      child: widget.child,
    );
  }
}

/// Paints a line's glow independently from its animated foreground text.
///
/// Keeping this painter below its own repaint boundary lets scrolling and
/// elastic transforms reuse the rasterized blur instead of rebuilding a text
/// shadow on every foreground color or karaoke-progress frame.
class MobileLyricGlowPainter extends CustomPainter {
  const MobileLyricGlowPainter({
    required this.text,
    required this.style,
    required this.color,
    required this.blurRadius,
    required this.textAlign,
    required this.textDirection,
    required this.textScaler,
    required this.locale,
  });

  final String text;
  final TextStyle style;
  final Color color;
  final double blurRadius;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final Locale? locale;

  @override
  void paint(Canvas canvas, Size size) {
    if (text.isEmpty || size.isEmpty || color.a <= 0 || blurRadius <= 0) {
      return;
    }
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(
          color: Colors.transparent,
          shadows: [Shadow(color: color, blurRadius: blurRadius)],
        ),
      ),
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
    )..layout(maxWidth: size.width);
    painter.paint(canvas, Offset(0, (size.height - painter.height) / 2));
  }

  @override
  bool shouldRepaint(covariant MobileLyricGlowPainter oldDelegate) =>
      oldDelegate.text != text ||
      oldDelegate.style != style ||
      oldDelegate.color != color ||
      oldDelegate.blurRadius != blurRadius ||
      oldDelegate.textAlign != textAlign ||
      oldDelegate.textDirection != textDirection ||
      oldDelegate.textScaler != textScaler ||
      oldDelegate.locale != locale;
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
    required this.textAlign,
  });

  final LyricLine line;
  final Duration position;
  final Color playedColor;
  final Color unplayedColor;
  final TextAlign textAlign;

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
        _playedTokens[token] = TextSpan(text: token.text, style: _playedStyle);
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
      return Text(widget.line.texts.join('\n'), textAlign: widget.textAlign);
    }
    final spans = <InlineSpan>[];
    for (var row = 0; row < widget.line.texts.length; row++) {
      if (row > 0) spans.add(const TextSpan(text: '\n'));
      final tokens = row < tokenRows.length ? tokenRows[row] : null;
      if (tokens == null || tokens.isEmpty) {
        spans.add(
          TextSpan(text: widget.line.texts[row], style: _unplayedStyle),
        );
        continue;
      }
      for (final token in tokens) {
        _appendTokenSpans(spans, token);
      }
    }
    return Text.rich(TextSpan(children: spans), textAlign: widget.textAlign);
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

final Map<double, ui.ImageFilter> _lyricBlurFilters = {};

ui.ImageFilter _cachedLyricBlur(double sigma) {
  final cacheKey = (sigma * 4).round() / 4;
  return _lyricBlurFilters.putIfAbsent(
    cacheKey,
    () => ui.ImageFilter.blur(
      sigmaX: cacheKey,
      sigmaY: cacheKey,
      tileMode: TileMode.decal,
    ),
  );
}
