import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
  return [
    // 启用模糊背景
    SwitchListTile(
      title: Text('播放页模糊背景', style: Theme.of(context).textTheme.titleMedium),
      value: settings.useBlurBackground,
      onChanged: (value) {
        context.read<SettingsProvider>().setUseBlurBackground(value);
      },
    ),
    // 歌词上下补位设置
    SwitchListTile(
      title: const Text('高亮歌词始终垂直居中显示'),
      value: settings.addLyricPadding,
      onChanged: (value) {
        context.read<SettingsProvider>().setAddLyricPadding(value);
      },
    ),
  ];
}
