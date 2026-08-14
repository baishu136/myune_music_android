import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../page/playlist/playlist_models.dart';

class MobileLyricsListController {
  Object? _owner;
  VoidCallback? _recenterCallback;

  void _attach(Object owner, VoidCallback callback) {
    _owner = owner;
    _recenterCallback = callback;
  }

  void _detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _recenterCallback = null;
  }

  void recenter() => _recenterCallback?.call();
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
  });

  final List<LyricLine> lines;
  final int active;
  final double fontSize;
  final String? fontFamily;
  final MobileLyricsListController? controller;
  final bool edgeFadeEnabled;

  @override
  State<MobileLyricsList> createState() => _MobileLyricsListState();
}

class _MobileLyricsListState extends State<MobileLyricsList> {
  final ItemScrollController _scrollController = ItemScrollController();
  double _viewportHeight = 0;
  int _centerRequestId = 0;
  int _resizeRequestId = 0;
  Timer? _resumeFollowTimer;
  bool _isManuallyBrowsing = false;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this, _recenterActive);
    _scrollToActive(jump: true);
  }

  @override
  void didUpdateWidget(covariant MobileLyricsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this, _recenterActive);
    }
    final linesChanged = oldWidget.lines != widget.lines;
    final fontSizeChanged =
        (oldWidget.fontSize - widget.fontSize).abs() >= 0.01;
    if (linesChanged) {
      _resumeAutomaticFollow();
      _scrollToActive(jump: true, force: true);
    } else if (fontSizeChanged) {
      _scrollToActive(jump: true, force: true);
      if (fontSizeChanged) _keepActiveCenteredDuringResize();
    } else if (oldWidget.active != widget.active) {
      _scrollToActive(jump: false);
    }
  }

  void _scrollToActive({required bool jump, bool force = false}) {
    if (_isManuallyBrowsing && !force) return;
    if (widget.active < 0 || widget.active >= widget.lines.length) return;
    final requestId = ++_centerRequestId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          requestId != _centerRequestId ||
          !_scrollController.isAttached) {
        return;
      }
      final alignment = _activeAlignment;
      if (jump) {
        _scrollController.jumpTo(index: widget.active, alignment: alignment);
      } else {
        _scrollController.scrollTo(
          index: widget.active,
          alignment: alignment,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  void _markManualInteraction() {
    if (!mounted) return;
    _isManuallyBrowsing = true;
    _centerRequestId++;
    _resumeFollowTimer?.cancel();
    _resumeFollowTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      _isManuallyBrowsing = false;
      _scrollToActive(jump: false, force: true);
    });
  }

  void _resumeAutomaticFollow() {
    _resumeFollowTimer?.cancel();
    _resumeFollowTimer = null;
    _isManuallyBrowsing = false;
  }

  void _recenterActive() {
    _resumeAutomaticFollow();
    _scrollToActive(jump: true, force: true);
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _markManualInteraction();
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _markManualInteraction();
    } else if (notification is OverscrollNotification &&
        notification.dragDetails != null) {
      _markManualInteraction();
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
    if (_viewportHeight <= 0 ||
        widget.active < 0 ||
        widget.active >= widget.lines.length) {
      return 0.45;
    }
    final lineCount = widget.lines[widget.active].texts.fold<int>(
      0,
      (count, text) => count + '\n'.allMatches(text).length + 1,
    );
    final estimatedHeight = widget.fontSize * 1.2 * lineCount + 10;
    return (0.5 - estimatedHeight / (_viewportHeight * 2)).clamp(0.08, 0.48);
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _resumeFollowTimer?.cancel();
    _centerRequestId++;
    _resizeRequestId++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.lines.isEmpty
      ? const Center(child: Text('暂无歌词'))
      : LayoutBuilder(
          builder: (context, constraints) {
            final viewportChanged =
                (_viewportHeight - constraints.maxHeight).abs() >= 0.5;
            _viewportHeight = constraints.maxHeight;
            if (viewportChanged) _scrollToActive(jump: true);
            final edgePadding = (_viewportHeight / 2 - widget.fontSize).clamp(
              0.0,
              double.infinity,
            );
            Widget lyrics = NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              child: ScrollablePositionedList.builder(
                itemScrollController: _scrollController,
                padding: EdgeInsets.symmetric(vertical: edgePadding),
                itemCount: widget.lines.length,
                itemBuilder: (itemContext, index) {
                  final style = DefaultTextStyle.of(itemContext).style.copyWith(
                    fontFamily: widget.fontFamily,
                    fontSize: index == widget.active
                        ? widget.fontSize
                        : (widget.fontSize * 0.84).clamp(12.0, 32.0),
                    fontWeight: index == widget.active
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: index == widget.active
                        ? Theme.of(itemContext).colorScheme.primary
                        : null,
                  );
                  return Padding(
                    key: ValueKey('mobile_lyric_$index'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 5,
                    ),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      style: style,
                      textAlign: TextAlign.center,
                      child: Text(widget.lines[index].texts.join('\n')),
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
                    Colors.white,
                    Colors.white,
                    Colors.transparent,
                  ],
                  stops: [0, 0.14, 0.86, 1],
                ).createShader(bounds),
                child: lyrics,
              );
            }
            return lyrics;
          },
        );
}
