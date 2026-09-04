import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../settings_provider.dart';
import '../../../widgets/font_selector_row.dart';
import '../../../theme/theme_provider.dart';
import '../page_visibility_settings.dart';
import 'info_icon.dart';
import 'playback_page_tab.dart';
import 'theme_settings_section.dart';
import 'custom_theme_settings_section.dart';

class PersonalizationTab extends StatelessWidget {
  const PersonalizationTab({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return ListView(
      key: const ValueKey('personalization'),
      children: [
        if (Platform.isAndroid) ...[
          const _PersonalizationSectionHeader(
            icon: Icons.palette_outlined,
            title: '主题与配色',
          ),
          const ThemeSettingsSection(),
          const _PersonalizationSectionHeader(
            icon: Icons.wallpaper_outlined,
            title: '背景',
          ),
          const CustomThemeSettingsSection(),
        ],
        const _PersonalizationSectionHeader(
          icon: Icons.text_fields_outlined,
          title: '字体与排版',
        ),
        // 系统字体选择器
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: FontSelectorRow(),
        ),
        SwitchListTile(
          title: const Text('自定义字体仅歌词'),
          subtitle: const Text('界面保持默认字体，仅将所选字体应用到歌词'),
          value: context.watch<ThemeProvider>().fontOnlyLyrics,
          onChanged: (value) {
            context.read<ThemeProvider>().setFontOnlyLyrics(value);
          },
        ),

        // 页面可见性设置
        if (!Platform.isAndroid)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: PageVisibilitySettings(),
          ),

        if (Platform.isWindows)
          SwitchListTile(
            title: const Text('在任务栏显示播放进度'),
            value: settings.showTaskbarProgress,
            onChanged: (value) {
              context.read<SettingsProvider>().setShowTaskbarProgress(value);
            },
          ),
        // 始终保持单行歌词显示
        if (!Platform.isAndroid)
          SwitchListTile(
            title: Text(
              '始终单行显示顶部歌词',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            value: settings.forceSingleLineLyric,
            onChanged: (value) {
              context.read<SettingsProvider>().setForceSingleLineLyric(value);
            },
          ),
        // Android 将歌词来源归入“播放”。
        if (!Platform.isAndroid)
          SwitchListTile(
            title: const Row(
              children: [
                Text('优先读取外置LRC歌词'),
                SizedBox(width: 4),
                InfoIcon(
                  '启用后会优先读取同名.lrc作为歌词，其次内嵌歌词，否则相反\n该选项适用于同时拥有内嵌以及外置歌词的情况',
                ),
              ],
            ),
            value: settings.preferExternalLyrics,
            onChanged: (value) {
              context.read<SettingsProvider>().setPreferExternalLyrics(value);
            },
          ),
        if (Platform.isAndroid) ...[
          const _PersonalizationSectionHeader(
            icon: Icons.play_circle_outline,
            title: '播放页',
          ),
          ...playbackPageSettingTiles(context),
        ],
      ],
    );
  }
}

class _PersonalizationSectionHeader extends StatelessWidget {
  const _PersonalizationSectionHeader({
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
