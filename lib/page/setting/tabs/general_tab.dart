import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app_version.dart';
import '../../playlist/playlist_content_notifier.dart';
import '../settings_provider.dart';
import '../update_checker.dart';
import '../about.dart';
import 'info_icon.dart';
import 'other_settings_section.dart';
import 'theme_settings_section.dart';

class GeneralTab extends StatefulWidget {
  const GeneralTab({super.key});

  @override
  State<GeneralTab> createState() => _GeneralTabState();
}

class _GeneralTabState extends State<GeneralTab> {
  bool _isCheckingUpdate = false;
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    AppVersion.current().then((version) {
      if (mounted) setState(() => _appVersion = version);
    });
  }

  // 检查更新
  Future<void> _checkForUpdates() async {
    final notifier = context.read<PlaylistContentNotifier>();

    setState(() {
      _isCheckingUpdate = true;
    });

    try {
      notifier.postInfo('正在检查更新…');

      final currentVersion = _appVersion ?? await AppVersion.current();
      final result = await UpdateChecker.checkForUpdates(currentVersion);

      if (!mounted) return;

      switch (result.type) {
        case UpdateCheckResultType.successUpdateAvailable:
          setState(() {
            _isCheckingUpdate = false;
          });
          notifier.postInfo(
            '发现新版本 ${result.updateInfo!.latestVersion}，正在前往 GitHub',
          );
          final launched = await launchUrl(
            Uri.parse(UpdateChecker.projectUrl),
            mode: LaunchMode.externalApplication,
          );
          if (!launched) {
            notifier.postError('无法连接至GitHub，请检查你的网络环境后重试');
          }
          break;
        case UpdateCheckResultType.successNoUpdate:
          setState(() {
            _isCheckingUpdate = false;
          });
          notifier.postInfo('您使用的版本已是最新');
          break;
        case UpdateCheckResultType.error:
          setState(() {
            _isCheckingUpdate = false;
          });
          notifier.postError('无法连接至GitHub，请检查你的网络环境后重试');
          break;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCheckingUpdate = false;
      });
      notifier.postError('无法连接至GitHub，请检查你的网络环境后重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return ListView(
      key: const ValueKey('general'),
      children: [
        // Android 将主题相关选项归入“个性化”。
        if (!Platform.isAndroid) const ThemeSettingsSection(),
        // 检查更新按钮
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '当前版本: ${_appVersion ?? '读取中…'}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ElevatedButton.icon(
                onPressed: _isCheckingUpdate ? null : _checkForUpdates,
                icon: _isCheckingUpdate
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.update, size: 20),
                label: const Text('检查更新'),
              ),
            ],
          ),
        ),
        // 是否启用从网络获取歌词
        if (!Platform.isAndroid)
          SwitchListTile(
            title: const Row(
              children: [
                Text('从网络获取歌词'),
                SizedBox(width: 4),
                InfoIcon("启用后将在未读取到内嵌及本地lrc歌词时从网络获取歌词"),
              ],
            ),
            value: settings.enableOnlineLyrics,
            onChanged: (value) {
              context.read<SettingsProvider>().setEnableOnlineLyrics(value);
            },
          ),
        // 歌词源选择
        if (!Platform.isAndroid)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      '网络歌词源选择',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(width: 4),
                    const InfoIcon(
                      '先使用所选平台；未获取到歌词时自动尝试其余平台。\n回退优先级：网抑 → 企鹅 → 库狗',
                    ),
                  ],
                ),
                Consumer<SettingsProvider>(
                  builder: (context, settings, child) {
                    return SegmentedButton<String>(
                      style: ButtonStyle(
                        padding: WidgetStateProperty.all(EdgeInsets.zero),
                        visualDensity: VisualDensity.compact,
                        minimumSize: WidgetStateProperty.all(const Size(0, 0)),
                      ),
                      segments: const [
                        ButtonSegment(value: 'netease', label: Text('网抑')),
                        ButtonSegment(value: 'qq', label: Text('企鹅')),
                        ButtonSegment(value: 'kugou', label: Text('库狗')),
                      ],
                      selected: {settings.primaryLyricSource},
                      onSelectionChanged: (newSelection) {
                        if (newSelection.isNotEmpty) {
                          final selected = newSelection.first;
                          final settingsProvider = context
                              .read<SettingsProvider>();

                          settingsProvider.setPrimaryLyricSource(selected);
                          settingsProvider.setSecondaryLyricSource(
                            networkLyricSourceOrder(selected)[1],
                          );
                        }
                      },
                      showSelectedIcon: false,
                    );
                  },
                ),
              ],
            ),
          ),
        // 关于
        const About(),
        // 页面底部的补充信息与项目支持入口。
        const OtherSettingsSection(),
      ],
    );
  }
}
