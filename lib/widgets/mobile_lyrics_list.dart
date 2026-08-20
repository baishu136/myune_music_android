import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../page/playlist/playlist_models.dart';

class MobileLyricsListController {
  Object? _owner;
  VoidCallback? _recenterCallback;
  bool _recenterPending = false;

  void _attach(Object owner, VoidCallback callback) {
    _owner = owner;
    _recenterCallback = callback;
    if (_recenterPending) {
      _recenterPending = false;
      callback();
    }
  }

  void _detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _recenterCallback = null;
  }

  void recenter() {
    final callback = _recenterCallback;
    if (callback == null) {
      _recenterPending = true;
      return;
    }
    callback();
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
    this.position = Duration.zero,
  });

  final List<LyricLine> lines;
  final int active;
  final double fontSize;
  final String? fontFamily;
  final MobileLyricsListController? controller;
  final bool edgeFadeEnabled;
  final Duration position;

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

  void _startManualInteraction() {
    if (!mounted) return;
    _isManuallyBrowsing = true;
    _centerRequestId++;
    _resumeFollowTimer?.cancel();
    _resumeFollowTimer = null;
  }

  void _scheduleResumeFollowTimer() {
    if (!mounted || !_isManuallyBrowsing) return;
    _resumeFollowTimer?.cancel();
    _resumeFollowTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      _resumeFollowTimer = null;
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
                  );
                  final lyric = isActive
                      ? _KaraokeLyricText(
                          line: widget.lines[index],
                          position: widget.position,
                          playedColor: style.color!,
                          unplayedColor: _unplayedColor(itemContext),
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
      Theme.of(context).brightness == Brightness.dark
      ? Colors.white.withValues(alpha: .50)
      : const Color(0xFF757575).withValues(alpha: .50);
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
