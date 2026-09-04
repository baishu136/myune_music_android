import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/desktop_lyrics_controller.dart';
import '../../../theme/theme_provider.dart';
import '../settings_provider.dart';
import '../theme_selection_screen.dart';
import 'info_icon.dart';

const desktopLyricPresetColors = <int>[
  0xFFE9143D,
  0xFF00A9D6,
  0xFF00C99A,
  0xFFE5A913,
  0xFF9D42D7,
];

const desktopLyricsPreviewText = '桌面歌词\nZhuo Mian Ge Ci';

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
  return [if (Platform.isAndroid) const _DesktopLyricsSettingsSection()];
}

class _DesktopLyricsSettingsSection extends StatelessWidget {
  const _DesktopLyricsSettingsSection();

  @override
  Widget build(BuildContext context) {
    final value = context.watch<DesktopLyricsController>();
    final settings = context.watch<SettingsProvider>();
    final fontFamily = context.watch<ThemeProvider>().currentFontFamily;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: ExpansionTile(
        key: const PageStorageKey<String>('desktop-lyrics-settings-expansion'),
        initiallyExpanded: false,
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(Icons.lyrics_outlined, color: scheme.primary),
        title: Text('桌面歌词设置', style: Theme.of(context).textTheme.titleLarge),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Row(
              children: [
                Text('启用桌面歌词'),
                SizedBox(width: 4),
                InfoIcon('在桌面和其他应用上方同步显示歌词。'),
              ],
            ),
            value: value.enabled,
            onChanged: (enabled) async {
              final success = await context
                  .read<DesktopLyricsController>()
                  .setEnabled(enabled);
              if (!context.mounted || success || !enabled) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请授予“显示在其他应用上层”权限后返回应用')),
              );
            },
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Row(
              children: [
                Text('锁定桌面歌词'),
                SizedBox(width: 4),
                InfoIcon('锁定后固定歌词位置并关闭触摸操作。'),
              ],
            ),
            value: value.locked,
            onChanged: value.enabled ? value.setLocked : null,
          ),
          const Divider(height: 20),
          Row(
            children: [
              Text('桌面歌词样式', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(
                tooltip: '恢复默认',
                onPressed: () async {
                  await value.setColor(0xFF00A9D6);
                  await value.setFontSize(22);
                  await value.setOutlineEnabled(false);
                  await value.setOutlineWidth(1.15);
                  await value.setOutlineColor(0xFFFFFFFF);
                  await value.setOutlineOpacity(1);
                },
                icon: const Icon(Icons.restart_alt),
              ),
            ],
          ),
          _DesktopLyricsPreview(
            color: Color(value.color),
            fontSize: value.fontSize,
            fontFamily: fontFamily,
            outlineEnabled: value.outlineEnabled,
            outlineWidth: value.outlineWidth,
            outlineColor: Color(
              value.outlineColor,
            ).withValues(alpha: value.outlineOpacity),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('歌词颜色'),
              const Spacer(),
              IconButton.filledTonal(
                tooltip: '自定义取色',
                icon: const Icon(Icons.colorize),
                onPressed: () async {
                  final selected = await showDialog<Color>(
                    context: context,
                    builder: (_) => AdobeColorPickerDialog(
                      initial: Color(value.color),
                      title: '自定义桌面歌词颜色',
                    ),
                  );
                  if (selected == null || !context.mounted) return;
                  final color = selected.toARGB32();
                  await value.setColor(color);
                  await settings.rememberDesktopLyricsCustomColor(color);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              for (final color in desktopLyricPresetColors)
                _DesktopLyricColorDot(
                  color: color,
                  selected: value.color == color,
                  onTap: () => value.setColor(color),
                ),
            ],
          ),
          if (settings.desktopLyricsCustomColors.isNotEmpty) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('自定义颜色', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(width: 4),
                  const InfoIcon('最多保留 5 个自定义颜色。'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 16,
                runSpacing: 10,
                children: [
                  for (final color in settings.desktopLyricsCustomColors)
                    _DesktopLyricColorDot(
                      color: color,
                      selected: value.color == color,
                      onTap: () => value.setColor(color),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('字体大小：${value.fontSize.toStringAsFixed(0)}'),
          ),
          Slider(
            value: value.fontSize,
            min: 16,
            max: 38,
            divisions: 22,
            label: value.fontSize.toStringAsFixed(0),
            onChanged: value.setFontSize,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Row(
              children: [
                Text('歌词描边'),
                SizedBox(width: 4),
                InfoIcon('默认关闭，可独立调整粗细、颜色和透明度。'),
              ],
            ),
            value: value.outlineEnabled,
            onChanged: value.setOutlineEnabled,
          ),
          if (value.outlineEnabled) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text('描边粗细：${value.outlineWidth.toStringAsFixed(2)}'),
            ),
            Slider(
              value: value.outlineWidth,
              min: .5,
              max: 4,
              divisions: 14,
              label: value.outlineWidth.toStringAsFixed(2),
              onChanged: value.setOutlineWidth,
            ),
            const Align(alignment: Alignment.centerLeft, child: Text('描边颜色')),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 14,
                runSpacing: 10,
                children: [
                  for (final color in const [
                    0xFFFFFFFF,
                    0xFFBDBDBD,
                    0xFF303030,
                    0xFFFFD54F,
                    0xFF80DEEA,
                  ])
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => value.setOutlineColor(color),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(color),
                          border: Border.all(
                            width: value.outlineColor == color ? 4 : 1,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('描边透明度：${(value.outlineOpacity * 100).round()}%'),
            ),
            Slider(
              value: value.outlineOpacity,
              min: .1,
              max: 1,
              divisions: 18,
              label: '${(value.outlineOpacity * 100).round()}%',
              onChanged: value.setOutlineOpacity,
            ),
          ],
        ],
      ),
    );
  }
}

class _DesktopLyricColorDot extends StatelessWidget {
  const _DesktopLyricColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final int color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    customBorder: const CircleBorder(),
    onTap: onTap,
    child: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color(color),
        border: Border.all(
          width: selected ? 4 : 1,
          color: selected
              ? Theme.of(context).colorScheme.onSurface
              : Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    ),
  );
}

class _DesktopLyricsPreview extends StatelessWidget {
  const _DesktopLyricsPreview({
    required this.color,
    required this.fontSize,
    required this.fontFamily,
    required this.outlineEnabled,
    required this.outlineWidth,
    required this.outlineColor,
  });

  final Color color;
  final double fontSize;
  final String fontFamily;
  final bool outlineEnabled;
  final double outlineWidth;
  final Color outlineColor;

  @override
  Widget build(BuildContext context) {
    final size = fontSize.clamp(16.0, 38.0);
    const previewText = desktopLyricsPreviewText;
    final fillStyle = TextStyle(
      fontFamily: fontFamily,
      fontSize: size,
      height: 1.15,
      color: color,
    );
    return Container(
      key: const ValueKey('desktop-lyrics-style-preview'),
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x80303030),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (outlineEnabled)
            Text(
              previewText,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: fillStyle.copyWith(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeJoin = StrokeJoin.round
                  ..strokeWidth = outlineWidth
                  ..color = outlineColor,
              ),
            ),
          Text(
            previewText,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: fillStyle,
          ),
        ],
      ),
    );
  }
}
