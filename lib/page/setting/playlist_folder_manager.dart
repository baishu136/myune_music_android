import 'package:flutter/material.dart';

import '../playlist/playlist_content_notifier.dart';

class PlaylistFolderManager extends StatefulWidget {
  const PlaylistFolderManager({super.key, required this.notifier});
  final PlaylistContentNotifier notifier;

  @override
  State<PlaylistFolderManager> createState() => _PlaylistFolderManagerState();
}

class _PlaylistFolderManagerState extends State<PlaylistFolderManager> {
  late Future<List<String>> _folders = widget.notifier.importedAudioFolders();
  bool _busy = false;

  Future<void> _manage(String root, {required bool remove}) async {
    if (_busy) return;
    String? associatePlaylistId;
    if (!remove &&
        !widget.notifier.playlists.any(
          (playlist) => folderPlaylistTracksImportedRoot(playlist, root),
        )) {
      associatePlaylistId = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('选择关联歌单'),
          content: SizedBox(
            width: 360,
            height: 300,
            child: ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('此历史文件夹未记录所属歌单。选择刷新歌曲的目标歌单。'),
                ),
                for (final playlist in widget.notifier.playlists)
                  ListTile(
                    title: Text(playlist.name),
                    onTap: () => Navigator.pop(context, playlist.id),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        ),
      );
      if (associatePlaylistId == null || !mounted || _busy) return;
    }
    if (remove) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('移除歌单文件夹'),
          content: Text('解除此文件夹与歌单的关联，并从关联歌单移除对应歌曲。磁盘音乐文件保留。\n\n$root'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('移除'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || _busy) return;
    }
    setState(() => _busy = true);
    String message;
    try {
      if (remove) {
        await widget.notifier.removeImportedAudioFolder(root);
        message = '已移除歌单文件夹';
      } else {
        if (associatePlaylistId != null) {
          await widget.notifier.associateImportedAudioFolder(
            root,
            associatePlaylistId,
          );
        }
        final result = await widget.notifier.refreshImportedAudioFolders(
          folderPath: root,
        );
        message = result.failedFolders.isNotEmpty
            ? '无法访问文件夹，原歌曲列表已保留'
            : '已刷新：新增 ${result.addedSongs} 首，移除 ${result.removedSongs} 首失效歌曲';
      }
    } catch (error) {
      message = '操作失败：$error';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _folders = widget.notifier.importedAudioFolders();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('歌单文件夹管理'),
    leading: const Icon(Icons.folder_open),
    onExpansionChanged: (open) {
      if (open && !_busy) {
        setState(() {
          _folders = widget.notifier.importedAudioFolders();
        });
      }
    },
    children: [
      FutureBuilder<List<String>>(
        future: _folders,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const ListTile(title: Text('无法读取文件夹记录'));
          }
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            );
          }
          final roots = snapshot.data!;
          if (roots.isEmpty) return const ListTile(title: Text('暂无已导入的歌单文件夹'));
          return Column(
            children: [
              for (final root in roots)
                ListTile(
                  title: Text(
                    root,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    widget.notifier.playlists
                        .where(
                          (playlist) =>
                              folderPlaylistTracksImportedRoot(playlist, root),
                        )
                        .map((playlist) => playlist.name)
                        .join('、'),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '刷新文件夹歌曲',
                        icon: const Icon(Icons.refresh),
                        onPressed: _busy || widget.notifier.isLoadingSongs
                            ? null
                            : () => _manage(root, remove: false),
                      ),
                      IconButton(
                        tooltip: '移除歌单文件夹',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _busy || widget.notifier.isLoadingSongs
                            ? null
                            : () => _manage(root, remove: true),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}
