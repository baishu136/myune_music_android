import 'package:flutter/material.dart';

enum PlaybackMenuAction { queue, effects, lyrics, preset, analysis, plugins }

class PlaybackActionsMenu extends StatelessWidget {
  const PlaybackActionsMenu({
    super.key,
    required this.onSelected,
    this.showAnalysis = false,
    this.showQueue = true,
    this.compact = false,
    this.showPlugins = false,
  });
  final ValueChanged<PlaybackMenuAction> onSelected;
  final bool showAnalysis;
  final bool showQueue, compact;
  final bool showPlugins;
  @override
  Widget build(BuildContext context) => PopupMenuButton<PlaybackMenuAction>(
    tooltip: '播放功能',
    onSelected: onSelected,
    itemBuilder: (_) => [
      if (showPlugins)
        const PopupMenuItem(
          value: PlaybackMenuAction.plugins,
          child: ListTile(
            leading: Icon(Icons.extension_outlined),
            title: Text('插件'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      if (showQueue)
        const PopupMenuItem(
          value: PlaybackMenuAction.queue,
          child: ListTile(
            leading: Icon(Icons.queue_music),
            title: Text('队列'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      const PopupMenuItem(
        value: PlaybackMenuAction.effects,
        child: ListTile(
          leading: Icon(Icons.tune),
          title: Text('音效'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      const PopupMenuItem(
        value: PlaybackMenuAction.lyrics,
        child: ListTile(
          leading: Icon(Icons.lyrics_outlined),
          title: Text('歌词'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      const PopupMenuItem(
        value: PlaybackMenuAction.preset,
        child: ListTile(
          leading: Icon(Icons.equalizer),
          title: Text('均衡器预设'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      if (showAnalysis)
        const PopupMenuItem(
          value: PlaybackMenuAction.analysis,
          child: ListTile(
            leading: Icon(Icons.graphic_eq),
            title: Text('音频分析'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
    ],
    child: compact
        ? const Padding(
            padding: EdgeInsets.all(12),
            child: Icon(Icons.more_horiz),
          )
        : const Chip(
            avatar: Icon(Icons.more_horiz, size: 20),
            label: Text('播放功能'),
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
  );
}
