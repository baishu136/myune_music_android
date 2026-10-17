import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import '../page/playlist/playlist_content_notifier.dart';
import '../page/playlist/playlist_models.dart';

class SongPlaylistSheet extends StatefulWidget {
  const SongPlaylistSheet({super.key, required this.song});
  final Song song;

  @override
  State<SongPlaylistSheet> createState() => _SongPlaylistSheetState();
}

class _SongPlaylistSheetState extends State<SongPlaylistSheet> {
  bool _busy = false;

  Future<void> _create() async {
    if (_busy) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _PlaylistNameDialog(),
    );
    if (!mounted || name == null || name.isEmpty) return;
    setState(() => _busy = true);
    try {
      await context.read<PlaylistContentNotifier>().saveQueueAsPlaylist(name, [
        widget.song,
      ]);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(String id) async {
    setState(() => _busy = true);
    try {
      await context.read<PlaylistContentNotifier>().addSongsToPlaylistById(id, [
        widget.song.filePath,
      ]);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaylistContentNotifier>();
    final playlists = notifier.playlists.where((p) => !p.isLibrary).toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .62,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('新建歌单'),
              enabled: !_busy,
              onTap: _create,
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  final included = playlist.songFilePaths.any(
                    (path) =>
                        p.normalize(path).toLowerCase() ==
                        widget.song.normalizedPath.toLowerCase(),
                  );
                  return CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(playlist.name),
                    value: included,
                    onChanged: _busy || included
                        ? null
                        : (_) => _add(playlist.id),
                  );
                },
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog();
  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  final _input = TextEditingController();
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('新建歌单'),
    content: TextField(controller: _input, autofocus: true, maxLength: 100),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _input.text.trim()),
        child: const Text('创建'),
      ),
    ],
  );
}
