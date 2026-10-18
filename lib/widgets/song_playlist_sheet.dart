import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:typed_data';
import 'artwork_image.dart';
import 'playback_control_sheet_surface.dart';
import 'playlist_created_label.dart';
import '../page/playlist/playlist_content_notifier.dart';
import '../page/playlist/playlist_models.dart';

Future<void> showSongPlaylistWindow(
  BuildContext context,
  Song song, {
  required bool fluid,
}) {
  final themes = InheritedTheme.capture(
    from: context,
    to: Navigator.of(context, rootNavigator: true).context,
  );
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260),
    transitionBuilder: (_, animation, secondary, child) {
      final progress = animation.drive(CurveTween(curve: Curves.easeOutCubic));
      return FadeTransition(
        key: const ValueKey('song-playlist-window-fade'),
        opacity: progress,
        child: ScaleTransition(
          key: const ValueKey('song-playlist-window-scale'),
          scale: progress.drive(Tween(begin: .92, end: 1.0)),
          child: child,
        ),
      );
    },
    pageBuilder: (_, animation, secondary) => themes.wrap(
      SafeArea(
        child: Dialog(
          key: const ValueKey('song-playlist-floating-window'),
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 36,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: PlaybackControlSheetSurface(
              fluid: fluid,
              borderRadius: BorderRadius.circular(24),
              child: SongPlaylistSheet(song: song),
            ),
          ),
        ),
      ),
    ),
  );
}

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

  Future<void> _setIncluded(String id, bool included) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final notifier = context.read<PlaylistContentNotifier>();
      if (included) {
        await notifier.addSongsToPlaylistById(id, [widget.song.filePath]);
      } else {
        await notifier.removeSongsFromPlaylistById(id, [widget.song.filePath]);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('更新歌单失败，请重试')));
      }
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
        height: MediaQuery.sizeOf(context).height * .72,
        width: double.infinity,
        child: Column(
          children: [
            ListTile(
              leading: const SizedBox.square(
                dimension: 48,
                child: Icon(Icons.add, size: 32),
              ),
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
                  final included = playlist.containsSongPath(
                    widget.song.filePath,
                  );
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final compact =
                          constraints.maxWidth < 340 ||
                          MediaQuery.textScalerOf(context).scale(14) > 20;
                      final date = PlaylistCreatedLabel(
                        date: playlist.createdAt,
                      );
                      return ListTile(
                        key: ValueKey('song-playlist-${playlist.id}'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        horizontalTitleGap: 8,
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              key: ValueKey(
                                'song-playlist-selection-${playlist.id}',
                              ),
                              value: included,
                              shape: const CircleBorder(),
                              semanticLabel:
                                  '${included ? '移出' : '加入'}${playlist.name}',
                              onChanged: _busy
                                  ? null
                                  : (value) =>
                                        _setIncluded(playlist.id, value!),
                            ),
                            const SizedBox(width: 8),
                            _PlaylistCover(
                              path: playlist.songFilePaths.firstOrNull,
                            ),
                          ],
                        ),
                        title: Text(playlist.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('包含 ${playlist.songFilePaths.length} 首歌曲'),
                            if (compact) date,
                          ],
                        ),
                        trailing: compact
                            ? null
                            : ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 88),
                                child: date,
                              ),
                        enabled: !_busy,
                        onTap: () => _setIncluded(playlist.id, !included),
                      );
                    },
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

class _PlaylistCover extends StatefulWidget {
  const _PlaylistCover({required this.path});
  final String? path;
  @override
  State<_PlaylistCover> createState() => _PlaylistCoverState();
}

class _PlaylistCoverState extends State<_PlaylistCover> {
  Future<Uint8List?>? _cover;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(covariant _PlaylistCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _cover = null;
      _load();
    }
  }

  void _load() {
    if (_cover != null || widget.path == null) return;
    _cover = context.read<PlaylistContentNotifier>().ensureSongThumbnail(
      widget.path!,
    );
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: SizedBox.square(
      dimension: 48,
      child: FutureBuilder<Uint8List?>(
        future: _cover,
        builder: (_, snapshot) => widget.path == null || snapshot.data == null
            ? const Icon(Icons.queue_music)
            : ArtworkImage(
                bytes: snapshot.data!,
                size: ArtworkSize.thumbnail,
                width: 48,
                height: 48,
              ),
      ),
    ),
  );
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
