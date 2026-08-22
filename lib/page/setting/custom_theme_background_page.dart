import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/custom_theme_image_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/custom_theme_image_editor.dart';
import 'settings_provider.dart';

class CustomThemeBackgroundPage extends StatefulWidget {
  const CustomThemeBackgroundPage({super.key, required this.surface});

  final CustomThemeSurface surface;

  @override
  State<CustomThemeBackgroundPage> createState() =>
      _CustomThemeBackgroundPageState();
}

class _CustomThemeBackgroundPageState extends State<CustomThemeBackgroundPage> {
  List<String> _history = const [];
  bool _loading = true;
  bool _deleteMode = false;

  String get _title => switch (widget.surface) {
    CustomThemeSurface.home => '自定义主界面背景',
    CustomThemeSurface.playback => '自定义播放页背景',
  };

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final history = await CustomThemeImageService.history(widget.surface);
    if (!mounted) return;
    setState(() {
      _history = history;
      _loading = false;
      if (history.isEmpty) _deleteMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final currentPath = switch (widget.surface) {
      CustomThemeSurface.home => settings.homeThemeImagePath,
      CustomThemeSurface.playback => settings.playbackThemeImagePath,
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (_history.isNotEmpty)
            TextButton.icon(
              onPressed: () => setState(() => _deleteMode = !_deleteMode),
              icon: Icon(_deleteMode ? Icons.done : Icons.select_all),
              label: Text(_deleteMode ? '完成' : '多选'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '曾用背景',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '分别保留最近 ${CustomThemeImageService.maxHistoryCount} 张背景。点击图片立即应用；多选模式可永久删除。',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.62,
                        ),
                    itemCount: _history.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) return _buildImportTile();
                      final path = _history[index - 1];
                      return _buildHistoryTile(
                        path,
                        selected: path == currentPath,
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildImportTile() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _deleteMode ? null : _import,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 46, color: scheme.primary),
            const SizedBox(height: 10),
            const Text('导入背景'),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTile(String path, {required bool selected}) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 3 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Ink.image(
            image: FileImage(File(path)),
            fit: BoxFit.cover,
            child: InkWell(onTap: _deleteMode ? null : () => _apply(path)),
          ),
          if (selected)
            Positioned(
              left: 8,
              bottom: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: .92),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check,
                        size: 15,
                        color: scheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '使用中',
                        style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_deleteMode)
            Positioned(
              right: 6,
              top: 6,
              child: IconButton.filled(
                tooltip: '永久删除',
                style: IconButton.styleFrom(
                  backgroundColor: scheme.errorContainer,
                  foregroundColor: scheme.onErrorContainer,
                ),
                onPressed: () => _delete(path),
                icon: const Icon(Icons.close),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final sourcePath = result?.files.single.path;
    if (sourcePath == null || !mounted) return;
    final bytes = await showCustomThemeImageEditor(
      context,
      sourcePath: sourcePath,
      square: false,
      title: '调整主题背景',
    );
    if (bytes == null || !mounted) return;
    try {
      final savedPath = await CustomThemeImageService.save(
        widget.surface,
        bytes,
      );
      if (!mounted) return;
      await _setCurrent(savedPath);
      await _refresh();
      if (mounted) {
        context.read<NotificationService>().success('背景已保存并立即应用');
      }
    } catch (_) {
      if (mounted) {
        context.read<NotificationService>().error('无法保存图片，请重试');
      }
    }
  }

  Future<void> _apply(String path) async {
    await _setCurrent(path);
    if (!mounted) return;
    context.read<NotificationService>().success('历史背景已应用');
  }

  Future<void> _setCurrent(String path) async {
    final settings = context.read<SettingsProvider>();
    switch (widget.surface) {
      case CustomThemeSurface.home:
        await settings.setHomeThemeImage(path, enabled: true);
      case CustomThemeSurface.playback:
        await settings.setPlaybackThemeImage(path, enabled: true);
    }
  }

  Future<void> _delete(String path) async {
    final settings = context.read<SettingsProvider>();
    final isCurrent = switch (widget.surface) {
      CustomThemeSurface.home => settings.homeThemeImagePath == path,
      CustomThemeSurface.playback => settings.playbackThemeImagePath == path,
    };
    await FileImage(File(path)).evict();
    await CustomThemeImageService.remove(path);
    if (!mounted) return;
    if (isCurrent) {
      switch (widget.surface) {
        case CustomThemeSurface.home:
          await settings.setHomeThemeImage(null, enabled: false);
        case CustomThemeSurface.playback:
          await settings.setPlaybackThemeImage(null, enabled: false);
      }
    }
    await _refresh();
  }
}
