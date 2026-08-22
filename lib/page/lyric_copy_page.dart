import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'playlist/playlist_models.dart';

String lyricsClipboardText(Iterable<LyricLine> lines) => lines
    .where((line) => !line.isInterlude)
    .expand((line) => line.texts)
    .map((text) => text.trim())
    .where((text) => text.isNotEmpty)
    .join('\n');

class LyricCopyPage extends StatefulWidget {
  const LyricCopyPage({
    super.key,
    required this.lines,
    required this.activeLineIndex,
    this.fontFamily,
  });

  final List<LyricLine> lines;
  final int activeLineIndex;
  final String? fontFamily;

  @override
  State<LyricCopyPage> createState() => _LyricCopyPageState();
}

class _LyricCopyPageState extends State<LyricCopyPage> {
  final ItemScrollController _scrollController = ItemScrollController();
  final Set<int> _selectedIndexes = {};
  late final List<int> _copyableIndexes;
  late final int _initialItemIndex;

  @override
  void initState() {
    super.initState();
    _copyableIndexes = [
      for (var index = 0; index < widget.lines.length; index++)
        if (_isCopyable(widget.lines[index])) index,
    ];
    _initialItemIndex = _nearestInitialItemIndex();
  }

  bool _isCopyable(LyricLine line) =>
      !line.isInterlude && line.texts.any((text) => text.trim().isNotEmpty);

  int _nearestInitialItemIndex() {
    if (_copyableIndexes.isEmpty) return 0;
    var nearest = 0;
    var nearestDistance = (_copyableIndexes.first - widget.activeLineIndex)
        .abs();
    for (var item = 1; item < _copyableIndexes.length; item++) {
      final distance = (_copyableIndexes[item] - widget.activeLineIndex).abs();
      if (distance >= nearestDistance) continue;
      nearest = item;
      nearestDistance = distance;
    }
    return nearest;
  }

  void _toggleLine(int originalIndex) {
    setState(() {
      if (!_selectedIndexes.add(originalIndex)) {
        _selectedIndexes.remove(originalIndex);
      }
    });
    if (_selectedIndexes.isNotEmpty) {
      unawaited(
        Clipboard.setData(
          ClipboardData(
            text: lyricsClipboardText(
              _copyableIndexes
                  .where(_selectedIndexes.contains)
                  .map((index) => widget.lines[index]),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('复制部分歌词'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _copyableIndexes.isEmpty
          ? const Center(child: Text('暂无可复制的歌词'))
          : ScrollablePositionedList.builder(
              itemScrollController: _scrollController,
              initialScrollIndex: _initialItemIndex,
              initialAlignment: .46,
              padding: const EdgeInsets.symmetric(vertical: 24),
              itemCount: _copyableIndexes.length,
              itemBuilder: (context, itemIndex) {
                final originalIndex = _copyableIndexes[itemIndex];
                final line = widget.lines[originalIndex];
                final selected = _selectedIndexes.contains(originalIndex);
                final isInitiallyActive =
                    originalIndex == widget.activeLineIndex;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Material(
                    color: selected
                        ? scheme.primaryContainer.withValues(alpha: .62)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      key: ValueKey('lyric_copy_line_$originalIndex'),
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _toggleLine(originalIndex),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                line.texts.join('\n'),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontFamily: widget.fontFamily,
                                      fontWeight: isInitiallyActive
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 140),
                              child: selected
                                  ? Icon(
                                      Icons.check_circle,
                                      key: const ValueKey('selected'),
                                      color: scheme.primary,
                                    )
                                  : const SizedBox(
                                      key: ValueKey('unselected'),
                                      width: 24,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Icon(
                _selectedIndexes.isEmpty
                    ? Icons.touch_app_outlined
                    : Icons.content_copy,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _selectedIndexes.isEmpty
                      ? '点选歌词行即可复制，可继续点选多行'
                      : '已按原顺序复制 ${_selectedIndexes.length} 行歌词',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
