import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../theme/theme_provider.dart';
import '../../playlist/playlist_content_notifier.dart';
import '../settings_provider.dart';
import '../theme_selection_screen.dart';
import 'info_icon.dart';

/// Theme-related controls shared by desktop's general page and Android's
/// personalization page.
class ThemeSettingsSection extends StatelessWidget {
  const ThemeSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ThemeSelectionScreen(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('主题模式', style: Theme.of(context).textTheme.titleMedium),
              Consumer<ThemeProvider>(
                builder: (context, themeProvider, child) {
                  return SegmentedButton<ThemeMode>(
                    style: ButtonStyle(
                      padding: WidgetStateProperty.all(EdgeInsets.zero),
                      visualDensity: VisualDensity.compact,
                      minimumSize: WidgetStateProperty.all(const Size(0, 0)),
                    ),
                    segments: const [
                      ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                      ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                      ButtonSegment(value: ThemeMode.system, label: Text('自动')),
                    ],
                    selected: {themeProvider.themeMode},
                    onSelectionChanged: (selection) {
                      if (selection.isNotEmpty) {
                        context.read<ThemeProvider>().setThemeMode(
                          selection.first,
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
        SwitchListTile(
          title: Row(
            children: [
              Text('动态主题配色', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 4),
              const InfoIcon('启用后将使用当前播放歌曲的封面颜色作为主题配色'),
            ],
          ),
          value: settings.useDynamicColor,
          onChanged: (value) {
            context.read<SettingsProvider>().setUseDynamicColor(value);
            if (value) {
              final notifier = context.read<PlaylistContentNotifier>();
              final song = notifier.currentSong;
              if (song != null) {
                notifier.extractAndApplyDynamicColor(song.albumArt);
              }
            } else {
              context.read<ThemeProvider>().restoreLastManualColor();
            }
          },
        ),
      ],
    );
  }
}
