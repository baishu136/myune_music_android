import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../page/playlist/playlist_models.dart';

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

class _MobileLyricsListState extends State<MobileLyricsList> {
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  double _viewportHeight = 0;
  int _centerRequestId = 0;
  int _resizeRequestId = 0;
  Timer? _resumeFollowTimer;
  Timer? _browseGuideTimer;
  Timer? _seekTargetTimer;
  bool _isManuallyBrowsing = false;
  int? _browseTargetIndex;
  int? _seekTargetIndex;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this, _recenterActive, _settleOnTimestamp);
    _itemPositionsListener.itemPositions.addListener(
      _updateBrowseTargetFromVisibleItems,
    );
    _scrollToActive(jump: true);
  }

  @override
  void didUpdateWidget(covariant MobileLyricsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this, _recenterActive, _settleOnTimestamp);
    }
    final linesChanged = oldWidget.lines != widget.lines;
    final fontSizeChanged =
        (oldWidget.fontSize - widget.fontSize).abs() >= 0.01;
    if (linesChanged) {
      _clearSeekTarget();
      _resumeAutomaticFollow(notifyBrowseTarget: false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onBrowseTargetChanged?.call(null);
      });
      // When an online fallback source returns the first lyric batch, the
      // list is created below with its active line already centered. A second
      // post-frame jump would be visible during the cover -> lyric animation.
      if (oldWidget.lines.isNotEmpty && widget.lines.isNotEmpty) {
        _scrollToActive(jump: true, force: true);
      }
    } else if (fontSizeChanged) {
      _scrollToActive(jump: true, force: true);
      if (fontSizeChanged) _keepActiveCenteredDuringResize();
    } else if (oldWidget.active != widget.active) {
      final seekTarget = _seekTargetIndex;
      if (seekTarget != null) {
        if (widget.active == seekTarget) _clearSeekTarget();
        return;
      }
      _scrollToActive(jump: false);
    }
  }

  void _scrollToActive({required bool jump, bool force = false}) {
    _scrollToIndex(widget.active, jump: jump, force: force);
  }

  void _scrollToIndex(int index, {required bool jump, bool force = false}) {
    if (_isManuallyBrowsing && !force) return;
    if (index < 0 || index >= widget.lines.length) return;
    final requestId = ++_centerRequestId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          requestId != _centerRequestId ||
          !_scrollController.isAttached) {
        return;
      }
      final alignment = _alignmentFor(index);
      if (jump) {
        _scrollController.jumpTo(index: index, alignment: alignment);
      } else {
        _scrollController.scrollTo(
          index: index,
          alignment: alignment,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  void _startManualInteraction() {
    if (!mounted) return;
    _clearSeekTarget();
    _isManuallyBrowsing = true;
    _centerRequestId++;
    _resumeFollowTimer?.cancel();
    _resumeFollowTimer = null;
    _browseGuideTimer?.cancel();
    _browseGuideTimer = null;
    _updateBrowseTargetFromVisibleItems(force: true);
  }

  void _scheduleResumeFollowTimer() {
    if (!mounted || !_isManuallyBrowsing) return;
    _scheduleBrowseGuideHideTimer();
    _resumeFollowTimer?.cancel();
    _resumeFollowTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      _resumeFollowTimer = null;
      _resumeAutomaticFollow();
      _scrollToActive(jump: false, force: true);
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

  void _updateBrowseTargetFromVisibleItems({bool force = false}) {
    if (!_isManuallyBrowsing || widget.lines.isEmpty) return;
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    const viewportCenter = .5;
    ItemPosition? target;
    var nearestDistance = double.infinity;
    for (final position in positions) {
      if (position.index < 0 || position.index >= widget.lines.length) continue;
      if (position.itemLeadingEdge <= viewportCenter &&
          position.itemTrailingEdge >= viewportCenter) {
        target = position;
        break;
      }
      final itemCenter =
          (position.itemLeadingEdge + position.itemTrailingEdge) / 2;
      final distance = (itemCenter - viewportCenter).abs();
      if (distance < nearestDistance) {
        nearestDistance = distance;
        target = position;
      }
    }

    final index = target?.index;
    if (index == null || (!force && index == _browseTargetIndex)) return;
    _browseTargetIndex = index;
    widget.onBrowseTargetChanged?.call(widget.lines[index].timestamp);
  }

  void _recenterActive() {
    _clearSeekTarget();
    _resumeAutomaticFollow();
    _scrollToActive(jump: true, force: true);
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
    _scrollToIndex(targetIndex, jump: false, force: true);
    _seekTargetTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || _seekTargetIndex != targetIndex) return;
      _clearSeekTarget();
      _scrollToActive(jump: false, force: true);
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
    } else if (notification is ScrollEndNotification && _isManuallyBrowsing) {
      _scheduleResumeFollowTimer();
    }
    return false;
  }

  void _keepActiveCenteredDuringResize() {
    final resizeRequestId = ++_resizeRequestId;
    for (final delay in const [80, 160, 240]) {
      Future<void>.delayed(Duration(milliseconds: delay), () {
        if (!mounted || resizeRequestId != _resizeRequestId) return;
        _scrollToActive(jump: true, force: true);
      });
    }
  }

  double get _activeAlignment {
    return _alignmentFor(widget.active);
  }

  double _alignmentFor(int index) {
    if (_viewportHeight <= 0 || index < 0 || index >= widget.lines.length) {
      return 0.45;
    }
    final lineCount = widget.lines[index].texts.fold<int>(
      0,
      (count, text) => count + '\n'.allMatches(text).length + 1,
    );
    final estimatedHeight = widget.fontSize * 1.2 * lineCount + 10;
    return (0.5 - estimatedHeight / (_viewportHeight * 2)).clamp(0.08, 0.48);
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _itemPositionsListener.itemPositions.removeListener(
      _updateBrowseTargetFromVisibleItems,
    );
    _resumeFollowTimer?.cancel();
    _browseGuideTimer?.cancel();
    _seekTargetTimer?.cancel();
    _centerRequestId++;
    _resizeRequestId++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.lines.isEmpty
      ? const Center(child: Text('暂无歌词'))
      : LayoutBuilder(
          builder: (context, constraints) {
            final hadViewport = _viewportHeight > 0;
            final viewportChanged =
                (_viewportHeight - constraints.maxHeight).abs() >= 0.5;
            _viewportHeight = constraints.maxHeight;
            if (hadViewport && viewportChanged) {
              _scrollToActive(jump: true);
            }
            final edgePadding = (_viewportHeight / 2 - widget.fontSize).clamp(
              0.0,
              double.infinity,
            );
            final hasActiveLine =
                widget.active >= 0 && widget.active < widget.lines.length;
            Widget lyrics = NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              child: ScrollablePositionedList.builder(
                itemScrollController: _scrollController,
                itemPositionsListener: _itemPositionsListener,
                initialScrollIndex: hasActiveLine ? widget.active : 0,
                // Index zero is already centered by the symmetric edge
                // padding. Applying an additional alignment there can keep
                // the following line outside the lazily built viewport.
                initialAlignment: hasActiveLine && widget.active > 0
                    ? _activeAlignment
                    : 0,
                padding: EdgeInsets.symmetric(vertical: edgePadding),
                itemCount: widget.lines.length,
                itemBuilder: (itemContext, index) {
                  final isActive = index == widget.active;
                  final style = DefaultTextStyle.of(itemContext).style.copyWith(
                    fontFamily: widget.fontFamily,
                    fontSize: isActive
                        ? widget.fontSize
                        : (widget.fontSize * 0.84).clamp(12.0, 32.0),
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                    color: isActive
                        ? Theme.of(itemContext).colorScheme.primary
                        : _unplayedColor(itemContext),
                    shadows: widget.glowEnabled
                        ? [
                            Shadow(
                              color: _glowColor(itemContext),
                              blurRadius: widget.glowRadius,
                            ),
                          ]
                        : null,
                  );
                  final unplayedColor = _unplayedColor(itemContext);
                  final lyric = isActive
                      ? widget.positionListenable == null
                            ? _KaraokeLyricText(
                                line: widget.lines[index],
                                position: widget.position,
                                playedColor: style.color!,
                                unplayedColor: unplayedColor,
                              )
                            : ValueListenableBuilder<Duration>(
                                valueListenable: widget.positionListenable!,
                                builder: (context, position, _) =>
                                    _KaraokeLyricText(
                                      line: widget.lines[index],
                                      position: position,
                                      playedColor: style.color!,
                                      unplayedColor: unplayedColor,
                                    ),
                              )
                      : Text(widget.lines[index].texts.join('\n'));
                  return Padding(
                    key: ValueKey('mobile_lyric_$index'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 5,
                    ),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      style: style,
                      textAlign: TextAlign.center,
                      child: lyric,
                    ),
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
            return lyrics;
          },
        );

  Color _unplayedColor(BuildContext context) =>
      widget.brightForeground || Theme.of(context).brightness == Brightness.dark
      ? Colors.white.withValues(alpha: .50)
      : const Color(0xFF757575).withValues(alpha: .80);

  Color _glowColor(BuildContext context) =>
      widget.brightForeground || Theme.of(context).brightness == Brightness.dark
      ? Colors.white.withValues(alpha: .30)
      : const Color(0xFFBDBDBD).withValues(alpha: .30);
}

class _KaraokeLyricText extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final tokenRows = line.tokens;
    if (tokenRows == null || tokenRows.isEmpty) {
      return Text(line.texts.join('\n'));
    }
    final spans = <InlineSpan>[];
    for (var row = 0; row < line.texts.length; row++) {
      if (row > 0) spans.add(const TextSpan(text: '\n'));
      final tokens = row < tokenRows.length ? tokenRows[row] : null;
      if (tokens == null || tokens.isEmpty) {
        spans.add(
          TextSpan(
            text: line.texts[row],
            style: TextStyle(color: unplayedColor),
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
    final elapsedMs = position.inMilliseconds - token.start.inMilliseconds;
    if (elapsedMs <= 0) {
      spans.add(
        TextSpan(
          text: token.text,
          style: TextStyle(color: unplayedColor),
        ),
      );
      return;
    }
    if (durationMs <= 0 || elapsedMs >= durationMs) {
      spans.add(
        TextSpan(
          text: token.text,
          style: TextStyle(color: playedColor),
        ),
      );
      return;
    }
    final runes = token.text.runes.toList(growable: false);
    if (runes.isEmpty) return;
    final completed = (runes.length * elapsedMs / durationMs).floor().clamp(
      0,
      runes.length,
    );
    if (completed > 0) {
      spans.add(
        TextSpan(
          text: String.fromCharCodes(runes.take(completed)),
          style: TextStyle(color: playedColor),
        ),
      );
    }
    if (completed < runes.length) {
      spans.add(
        TextSpan(
          text: String.fromCharCodes(runes.skip(completed)),
          style: TextStyle(color: unplayedColor),
        ),
      );
    }
  }
}
