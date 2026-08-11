import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../page/playlist/playlist_models.dart';

class MobileLyricsList extends StatefulWidget {
  const MobileLyricsList({
    super.key,
    required this.lines,
    required this.active,
    this.fontSize = 20,
    this.fontFamily,
  });

  final List<LyricLine> lines;
  final int active;
  final double fontSize;
  final String? fontFamily;

  @override
  State<MobileLyricsList> createState() => _MobileLyricsListState();
}

class _MobileLyricsListState extends State<MobileLyricsList> {
  final ItemScrollController _scrollController = ItemScrollController();
  double _viewportHeight = 0;

  @override
  void initState() {
    super.initState();
    _scrollToActive(jump: true);
  }

  @override
  void didUpdateWidget(covariant MobileLyricsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active || oldWidget.lines != widget.lines) {
      _scrollToActive(jump: oldWidget.lines != widget.lines);
    }
  }

  void _scrollToActive({required bool jump}) {
    if (widget.active < 0 || widget.active >= widget.lines.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.isAttached) return;
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
  Widget build(BuildContext context) => widget.lines.isEmpty
      ? const Center(child: Text('暂无歌词'))
      : LayoutBuilder(
          builder: (context, constraints) {
            _viewportHeight = constraints.maxHeight;
            final edgePadding = (_viewportHeight / 2 - widget.fontSize).clamp(
              0.0,
              double.infinity,
            );
            return ScrollablePositionedList.builder(
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
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    style: style,
                    textAlign: TextAlign.center,
                    child: Text(widget.lines[index].texts.join('\n')),
                  ),
                );
              },
            );
          },
        );
}
