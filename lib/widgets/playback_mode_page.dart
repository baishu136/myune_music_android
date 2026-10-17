import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../page/playlist/playlist_content_notifier.dart';
import 'playback_mode_glyph.dart';

String playbackModeLabel(PlayMode mode) => switch (mode) {
  PlayMode.sequence => '列表循环',
  PlayMode.shuffle => '随机播放',
  PlayMode.repeatOne => '单曲循环',
  PlayMode.repeatShuffle => '循环播放后随机播放',
};

class PlaybackModePage extends StatefulWidget {
  const PlaybackModePage({super.key, this.asSheet = false});
  final bool asSheet;

  @override
  State<PlaybackModePage> createState() => _PlaybackModePageState();
}

class _PlaybackModePageState extends State<PlaybackModePage> {
  late final TextEditingController _minimum;

  @override
  void initState() {
    super.initState();
    _minimum = TextEditingController(
      text:
          '${context.read<PlaylistContentNotifier>().skipRules.minimumPlayCount}',
    );
  }

  @override
  void dispose() {
    _minimum.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = context.select<PlaylistContentNotifier, PlayMode>(
      (n) => n.playMode,
    );
    final rules = context.select<PlaylistContentNotifier, PlaybackSkipRules>(
      (n) => n.skipRules,
    );
    final notifier = context.read<PlaylistContentNotifier>();
    final content = ListView(
      children: [
        for (final value in PlayMode.values)
          ListTile(
            leading: PlaybackModeGlyph(mode: value),
            title: Text(playbackModeLabel(value)),
            trailing: mode == value ? const Icon(Icons.check) : null,
            selected: mode == value,
            onTap: () => notifier.setPlayMode(value),
          ),
        const Divider(),
        SwitchListTile(
          title: const Text('切歌时跳过收听次数不足的歌曲'),
          value: rules.lowPlayCount,
          onChanged: (value) =>
              notifier.setSkipRules(rules.copyWith(lowPlayCount: value)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: TextField(
            controller: _minimum,
            decoration: InputDecoration(
              labelText: '最低收听次数',
              errorText: _minimum.text.isEmpty ? '请输入次数' : null,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(9),
            ],
            onChanged: (value) {
              setState(() {});
              final count = int.tryParse(value);
              if (count != null) {
                notifier.setSkipRules(
                  notifier.skipRules.copyWith(minimumPlayCount: count),
                );
              }
            },
          ),
        ),
        SwitchListTile(
          title: const Text('切歌时跳过英文标题歌曲'),
          value: rules.english,
          onChanged: (value) =>
              notifier.setSkipRules(rules.copyWith(english: value)),
        ),
        SwitchListTile(
          title: const Text('切歌时跳过日文标题歌曲'),
          value: rules.japanese,
          onChanged: (value) =>
              notifier.setSkipRules(rules.copyWith(japanese: value)),
        ),
        SwitchListTile(
          title: const Text('切歌时跳过中文标题歌曲'),
          value: rules.chinese,
          onChanged: (value) =>
              notifier.setSkipRules(rules.copyWith(chinese: value)),
        ),
      ],
    );
    if (widget.asSheet) {
      return SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '播放模式',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(child: content),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('播放模式')),
      body: content,
    );
  }
}
