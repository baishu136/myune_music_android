import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/desktop_lyrics_controller.dart';
import '../settings_provider.dart';

class PlaybackPageTab extends StatelessWidget {
  const PlaybackPageTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('playback'),
      children: playbackPageSettingTiles(context),
    );
  }
}

List<Widget> playbackPageSettingTiles(BuildContext context) {
  final settings = context.watch<SettingsProvider>();
  final desktopLyrics = context.watch<DesktopLyricsController>();
  return [
    SwitchListTile(
      title: Text('播放页模糊背景', style: Theme.of(context).textTheme.titleMedium),
      value: settings.useBlurBackground,
      onChanged: settings.setUseBlurBackground,
    ),
    SwitchListTile(
      title: const Text('高亮歌词始终垂直居中显示'),
      value: settings.addLyricPadding,
      onChanged: settings.setAddLyricPadding,
    ),
    SwitchListTile.adaptive(
      secondary: const Icon(Icons.flare_outlined),
      title: const Text('歌词外发光'),
      subtitle: const Text('为播放页歌词添加柔和外发光，默认关闭'),
      value: settings.playbackLyricGlowEnabled,
      onChanged: settings.setPlaybackLyricGlowEnabled,
    ),
    if (settings.playbackLyricGlowEnabled)
      ListTile(
        leading: const SizedBox(width: 24),
        title: Text(
          '发光范围：${settings.playbackLyricGlowRadius.toStringAsFixed(0)}',
        ),
        subtitle: Slider(
          value: settings.playbackLyricGlowRadius,
          min: 2,
          max: 20,
          divisions: 18,
          label: settings.playbackLyricGlowRadius.toStringAsFixed(0),
          onChanged: settings.setPlaybackLyricGlowRadius,
        ),
      ),
    if (Platform.isAndroid) ...[
      const Divider(),
      SwitchListTile(
        secondary: const Icon(Icons.lyrics_outlined),
        title: const Text('桌面歌词'),
        subtitle: Text(
          desktopLyrics.locked
              ? '已锁定；可在此解锁后移动'
              : desktopLyrics.enabled
              ? '已显示在其他应用上层'
              : '在桌面和其他应用上方同步显示歌词',
        ),
        value: desktopLyrics.enabled,
        onChanged: (value) async {
          final success = await context
              .read<DesktopLyricsController>()
              .setEnabled(value);
          if (!context.mounted || success || !value) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请授予“显示在其他应用上层”权限后返回应用')),
          );
        },
      ),
      if (desktopLyrics.enabled)
        SwitchListTile(
          secondary: Icon(
            desktopLyrics.locked ? Icons.lock_outline : Icons.lock_open,
          ),
          title: const Text('锁定桌面歌词'),
          subtitle: const Text('锁定后固定歌词位置并关闭触摸操作'),
          value: desktopLyrics.locked,
          onChanged: desktopLyrics.setLocked,
        ),
      if (desktopLyrics.enabled)
        ListTile(
          leading: const Icon(Icons.format_color_text),
          title: const Text('桌面歌词样式'),
          subtitle: const Text('独立颜色与字体大小，不跟随动态主题配色'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showDesktopLyricsStyle(context),
        ),
    ],
  ];
}

Future<void> _showDesktopLyricsStyle(BuildContext context) async {
  final controller = context.read<DesktopLyricsController>();
  const colors = [0xFFE9143D, 0xFF00A9D6, 0xFF00C99A, 0xFFE5A913, 0xFF9D42D7];
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => ChangeNotifierProvider.value(
      value: controller,
      child: Consumer<DesktopLyricsController>(
        builder: (context, value, _) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '桌面歌词样式',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '恢复默认',
                      onPressed: () async {
                        await value.setColor(0xFF00A9D6);
                        await value.setFontSize(22);
                      },
                      icon: const Icon(Icons.restart_alt),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 16,
                  children: [
                    for (final color in colors)
                      InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => value.setColor(color),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(color),
                            border: Border.all(
                              width: value.color == color ? 4 : 1,
                              color: value.color == color
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Theme.of(
                                      context,
                                    ).colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('字体大小：${value.fontSize.toStringAsFixed(0)}'),
                Slider(
                  value: value.fontSize,
                  min: 16,
                  max: 38,
                  divisions: 22,
                  label: value.fontSize.toStringAsFixed(0),
                  onChanged: value.setFontSize,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
