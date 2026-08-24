import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../settings_provider.dart';
import '../../playlist/playlist_content_notifier.dart';
import '../audio_device_selector.dart';
import 'info_icon.dart';

class PlaybackSettingsTab extends StatelessWidget {
  const PlaybackSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return ListView(
      key: const ValueKey('playback_settings'),
      children: [
        const ListTile(
          leading: Icon(Icons.slideshow_outlined),
          title: Text('进入播放页时展示'),
          subtitle: Text('退出播放页后重置；播放页内切歌保持当前封面或歌词页'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(56, 0, 16, 12),
          child: SegmentedButton<PlaybackInitialView>(
            expandedInsets: EdgeInsets.zero,
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: PlaybackInitialView.cover,
                label: Text('封面'),
                icon: Icon(Icons.album_outlined),
              ),
              ButtonSegment(
                value: PlaybackInitialView.lyrics,
                label: Text('歌词'),
                icon: Icon(Icons.lyrics_outlined),
              ),
            ],
            selected: {settings.playbackInitialView},
            onSelectionChanged: (selection) =>
                settings.setPlaybackInitialView(selection.first),
          ),
        ),
        if (Platform.isAndroid)
          SwitchListTile(
            title: const Row(
              children: [
                Text('优先读取外置LRC歌词'),
                SizedBox(width: 4),
                InfoIcon('启用后会优先读取同名 .lrc 歌词，其次读取内嵌歌词；关闭时顺序相反'),
              ],
            ),
            value: settings.preferExternalLyrics,
            onChanged: settings.setPreferExternalLyrics,
          ),
        SwitchListTile(
          title: const Row(
            children: [
              Text('显示音频分析入口'),
              SizedBox(width: 4),
              InfoIcon('启用后在播放页底部显示实时音频分析按钮\n默认关闭以保持操作栏简洁'),
            ],
          ),
          value: settings.showAudioAnalysis,
          onChanged: settings.setShowAudioAnalysis,
        ),
        // 音频设备选择
        if (!Platform.isAndroid)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '更改音频输出设备',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return const DeviceSelector();
                      },
                    );
                  },
                  icon: const Icon(Icons.headphones, size: 20),
                  label: const Text('选择设备'),
                ),
              ],
            ),
          ),
        // 独占模式设置
        if (!Platform.isAndroid)
          Consumer<PlaylistContentNotifier>(
            builder: (context, playlistNotifier, child) {
              return SwitchListTile(
                title: const Row(
                  children: [
                    Text('启用独占模式'),
                    SizedBox(width: 4),
                    InfoIcon('启用后将使用独占模式播放音频，提供更低的延迟以及更好的音质\n这会导致其他应用无法播放音频'),
                  ],
                ),
                value: playlistNotifier.isExclusiveModeEnabled,
                onChanged: playlistNotifier.toggleExclusiveMode,
              );
            },
          ),
        // 平衡歌曲音量设置
        SwitchListTile(
          title: const Row(
            children: [
              Text('平衡歌曲音量'),
              SizedBox(width: 4),
              InfoIcon('启用后将平衡为-16 LUFS\n这可能会损失部分音质'),
            ],
          ),
          value: settings.enableLoudness,
          onChanged: (value) {
            final playlistNotifier = context.read<PlaylistContentNotifier>();
            if (value && settings.enableReplayGain) {
              playlistNotifier.postInfo('与 "重放增益" 冲突');
              return;
            }
            context.read<SettingsProvider>().setEnableLoudness(value);
            playlistNotifier.updateLoudnessSettings();
          },
        ),
        // 重放增益设置
        SwitchListTile(
          title: const Row(
            children: [
              Text('重放增益'),
              SizedBox(width: 4),
              InfoIcon('需要歌曲包含 ReplayGain 标签\n可在 歌单-多选 中批量扫描写入'),
            ],
          ),
          value: settings.enableReplayGain,
          onChanged: (value) {
            final playlistNotifier = context.read<PlaylistContentNotifier>();
            if (value && settings.enableLoudness) {
              playlistNotifier.postInfo('与 "平衡歌曲音量" 冲突');
              return;
            }
            context.read<SettingsProvider>().setEnableReplayGain(value);
            playlistNotifier.updateReplayGainSettings();
          },
        ),
        // 无缝播放设置
        SwitchListTile(
          title: const Row(
            children: [
              Text('无缝队列'),
              SizedBox(width: 4),
              InfoIcon('实验性功能。启用后将会消除切歌时的短暂间隔'),
            ],
          ),
          value: settings.enableGaplessPlayback,
          onChanged: (value) {
            context.read<SettingsProvider>().setEnableGaplessPlayback(value);
            context.read<PlaylistContentNotifier>().updateGaplessMode(value);
          },
        ),
      ],
    );
  }
}
