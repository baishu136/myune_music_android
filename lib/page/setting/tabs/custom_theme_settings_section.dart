import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/custom_theme_image_service.dart';
import '../custom_theme_background_page.dart';
import '../settings_provider.dart';

class CustomThemeSettingsSection extends StatelessWidget {
  const CustomThemeSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.wallpaper,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Text('自定义图片主题', style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '导入图片后可双指缩放、拖动裁剪。主界面与播放页使用独立背景。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          const _AlbumArtFollowCard(),
          const SizedBox(height: 10),
          const _ThemeImageCard(surface: CustomThemeSurface.home),
          const SizedBox(height: 10),
          const _ThemeImageCard(surface: CustomThemeSurface.playback),
        ],
      ),
    );
  }
}

class _AlbumArtFollowCard extends StatelessWidget {
  const _AlbumArtFollowCard();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.album_outlined, color: scheme.primary),
            title: const Text('背景风格跟随音乐封面'),
            subtitle: const Text(
              '播放歌曲且存在封面时，将封面铺满屏幕并模糊处理；无封面或未选择歌曲时自动使用自定义或默认背景。',
            ),
          ),
          const Divider(height: 1),
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.home_outlined),
            title: const Text('应用到主界面'),
            subtitle: const Text('同步作用于音乐库、歌单、歌手、专辑和设置页'),
            value: settings.followAlbumArtOnHome,
            onChanged: settings.setFollowAlbumArtOnHome,
          ),
          if (settings.followAlbumArtOnHome)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _BackgroundTuningControls(
                dim: settings.homeAlbumArtBackgroundDim,
                blur: settings.homeAlbumArtBackgroundBlur,
                onDimChanged: settings.setHomeAlbumArtBackgroundDim,
                onBlurChanged: settings.setHomeAlbumArtBackgroundBlur,
              ),
            ),
          const Divider(height: 1),
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.play_circle_outline),
            title: const Text('应用到播放页'),
            subtitle: const Text('作用于封面、歌词和播放控制页面'),
            value: settings.followAlbumArtOnPlayback,
            onChanged: settings.setFollowAlbumArtOnPlayback,
          ),
          if (settings.followAlbumArtOnPlayback)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _BackgroundTuningControls(
                dim: settings.playbackAlbumArtBackgroundDim,
                blur: settings.playbackAlbumArtBackgroundBlur,
                onDimChanged: settings.setPlaybackAlbumArtBackgroundDim,
                onBlurChanged: settings.setPlaybackAlbumArtBackgroundBlur,
              ),
            ),
        ],
      ),
    );
  }
}

class _BackgroundTuningControls extends StatelessWidget {
  const _BackgroundTuningControls({
    required this.dim,
    required this.blur,
    required this.onDimChanged,
    required this.onBlurChanged,
  });

  final double dim;
  final double blur;
  final ValueChanged<double> onDimChanged;
  final ValueChanged<double> onBlurChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Icon(Icons.contrast, size: 20),
            const SizedBox(width: 8),
            const Text('遮罩强度'),
            Expanded(
              child: Slider(
                value: dim,
                min: 0.2,
                max: 0.9,
                divisions: 14,
                label: '${(dim * 100).round()}%',
                onChanged: onDimChanged,
              ),
            ),
            SizedBox(
              width: 40,
              child: Text('${(dim * 100).round()}%', textAlign: TextAlign.end),
            ),
          ],
        ),
        Row(
          children: [
            const Icon(Icons.blur_on_outlined, size: 20),
            const SizedBox(width: 8),
            const Text('模糊程度'),
            Expanded(
              child: Slider(
                value: blur,
                min: 0,
                max: 40,
                divisions: 20,
                label: blur == 0 ? '关闭' : blur.toStringAsFixed(0),
                onChanged: onBlurChanged,
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                blur == 0 ? '关闭' : blur.toStringAsFixed(0),
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ThemeImageCard extends StatelessWidget {
  const _ThemeImageCard({required this.surface});

  final CustomThemeSurface surface;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final path = switch (surface) {
      CustomThemeSurface.home => settings.homeThemeImagePath,
      CustomThemeSurface.playback => settings.playbackThemeImagePath,
    };
    final enabled = switch (surface) {
      CustomThemeSurface.home => settings.homeThemeImageEnabled,
      CustomThemeSurface.playback => settings.playbackThemeImageEnabled,
    };
    final exists = path != null && path.isNotEmpty && File(path).existsSync();
    final title = switch (surface) {
      CustomThemeSurface.home => '主界面背景',
      CustomThemeSurface.playback => '播放页背景',
    };
    final subtitle = switch (surface) {
      CustomThemeSurface.home => '同步应用于音乐库、歌单、歌手、专辑和设置页',
      CustomThemeSurface.playback => '覆盖封面、歌词和播放控制所在页面',
    };
    final dim = switch (surface) {
      CustomThemeSurface.home => settings.homeThemeImageDim,
      CustomThemeSurface.playback => settings.playbackThemeImageDim,
    };
    final blur = switch (surface) {
      CustomThemeSurface.home => settings.homeThemeImageBlur,
      CustomThemeSurface.playback => settings.playbackThemeImageBlur,
    };
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  ),
                  child: exists
                      ? Image.file(
                          File(path),
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        )
                      : const Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 34,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: enabled && exists,
                  onChanged: exists
                      ? (value) => _setEnabled(context, value)
                      : null,
                ),
              ],
            ),
            if (exists) ...[
              const SizedBox(height: 8),
              _BackgroundTuningControls(
                dim: dim,
                blur: blur,
                onDimChanged: (value) => surface == CustomThemeSurface.home
                    ? settings.setHomeThemeImageDim(value)
                    : settings.setPlaybackThemeImageDim(value),
                onBlurChanged: (value) => surface == CustomThemeSurface.home
                    ? settings.setHomeThemeImageBlur(value)
                    : settings.setPlaybackThemeImageBlur(value),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (exists)
                  TextButton.icon(
                    onPressed: () => _restoreDefault(context),
                    icon: const Icon(Icons.restore),
                    label: const Text('恢复默认'),
                  ),
                FilledButton.tonalIcon(
                  onPressed: () => _openBackgroundHistory(context),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(exists ? '重新导入' : '导入图片'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setEnabled(BuildContext context, bool value) async {
    final settings = context.read<SettingsProvider>();
    switch (surface) {
      case CustomThemeSurface.home:
        await settings.setHomeThemeImageEnabled(value);
        break;
      case CustomThemeSurface.playback:
        await settings.setPlaybackThemeImageEnabled(value);
        break;
    }
  }

  Future<void> _openBackgroundHistory(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CustomThemeBackgroundPage(surface: surface),
      ),
    );
  }

  Future<void> _restoreDefault(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    switch (surface) {
      case CustomThemeSurface.home:
        await settings.setHomeThemeImage(null, enabled: false);
        break;
      case CustomThemeSurface.playback:
        await settings.setPlaybackThemeImage(null, enabled: false);
        break;
    }
  }
}
