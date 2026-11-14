import 'package:flutter/material.dart';
import 'playback_actions_menu.dart';

/// One category rail, one content header. Visited pages retain their controls.
class LandscapeToolsPanel extends StatefulWidget {
  const LandscapeToolsPanel({
    super.key,
    required this.initial,
    required this.builder,
  });
  final PlaybackMenuAction initial;
  final Widget Function(BuildContext, PlaybackMenuAction) builder;
  @override
  State<LandscapeToolsPanel> createState() => _LandscapeToolsPanelState();
}

class _LandscapeToolsPanelState extends State<LandscapeToolsPanel> {
  static const entries = [
    (PlaybackMenuAction.queue, Icons.queue_music, '歌曲'),
    (PlaybackMenuAction.effects, Icons.tune, '音效'),
    (PlaybackMenuAction.lyrics, Icons.lyrics_outlined, '歌词'),
    (PlaybackMenuAction.preset, Icons.equalizer, '预设'),
  ];
  late var selected = widget.initial;
  late final visited = <PlaybackMenuAction>{selected};
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MediaQuery.removePadding(
      context: context,
      removeLeft: true,
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 64,
              child: ColoredBox(
                color: scheme.onSurface.withValues(alpha: .035),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  children: [
                    for (final entry in entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: IconButton(
                          key: ValueKey('landscape-category-${entry.$1.name}'),
                          tooltip: entry.$3,
                          isSelected: selected == entry.$1,
                          style: IconButton.styleFrom(
                            backgroundColor: selected == entry.$1
                                ? scheme.primary.withValues(alpha: .18)
                                : Colors.transparent,
                            foregroundColor: selected == entry.$1
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                            minimumSize: const Size(48, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: Icon(entry.$2, size: 23),
                          onPressed: () {
                            FocusScope.of(context).unfocus();
                            setState(() {
                              selected = entry.$1;
                              visited.add(selected);
                            });
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 52,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 20, right: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              entries.firstWhere((e) => e.$1 == selected).$3,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          IconButton(
                            tooltip: '关闭菜单',
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        for (final entry in entries)
                          if (visited.contains(entry.$1))
                            Offstage(
                              key: ValueKey(entry.$1),
                              offstage: selected != entry.$1,
                              child: ExcludeFocus(
                                excluding: selected != entry.$1,
                                child: FocusScope(
                                  child: TickerMode(
                                    enabled: selected == entry.$1,
                                    child: widget.builder(context, entry.$1),
                                  ),
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
