import 'package:flutter/material.dart';

import '../playlist/playlist_content_notifier.dart';

class FolderPlaylistRefresher extends StatefulWidget {
  final PlaylistContentNotifier notifier;

  const FolderPlaylistRefresher({super.key, required this.notifier});

  @override
  State<FolderPlaylistRefresher> createState() =>
      _FolderPlaylistRefresherState();
}

class _FolderPlaylistRefresherState extends State<FolderPlaylistRefresher> {
  bool _isRefreshing = false;

  Future<void> _startRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);

    ImportedFolderRefreshSummary? summary;
    Object? failure;
    try {
      summary = await widget.notifier.refreshImportedAudioFolders();
    } catch (error, stackTrace) {
      failure = error;
      debugPrint('刷新已导入文件夹失败: $error\n$stackTrace');
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }

    if (!mounted) return;
    if (failure != null || summary == null) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('刷新失败'),
          content: const Text('无法刷新已导入的文件夹，请检查存储权限后重试。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('刷新完成'),
        content: _RefreshSummaryContent(summary: summary!),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            '刷新所有文件夹歌单',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: _isRefreshing ? null : _startRefresh,
          icon: _isRefreshing
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync, size: 20),
          label: Text(_isRefreshing ? '正在刷新' : '开始刷新'),
        ),
      ],
    );
  }
}

class _RefreshSummaryContent extends StatelessWidget {
  final ImportedFolderRefreshSummary summary;

  const _RefreshSummaryContent({required this.summary});

  @override
  Widget build(BuildContext context) {
    final hasHistory =
        summary.refreshedFolders > 0 ||
        summary.skippedFolders > 0 ||
        summary.failedFolders.isNotEmpty;
    if (!hasHistory) {
      return const Text('尚未记录通过“导入整个文件夹”添加的目录。');
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460, maxHeight: 420),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('已扫描 ${summary.refreshedFolders} 个文件夹'),
            if (summary.skippedFolders > 0)
              Text('已跳过 ${summary.skippedFolders} 个曲库中已无对应歌曲的文件夹'),
            Text('新增 ${summary.addedSongs} 首歌曲'),
            Text('移除 ${summary.removedSongs} 首失效歌曲'),
            if (summary.failedFolders.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '以下文件夹无法访问：',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              ...summary.failedFolders.map(
                (folder) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    folder,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
