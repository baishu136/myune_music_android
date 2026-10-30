import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:typed_data';
import 'artwork_image.dart';
import 'playback_control_sheet_surface.dart';
import 'playlist_created_label.dart';
import '../page/playlist/playlist_content_notifier.dart';
import '../page/playlist/playlist_models.dart';
import '../models/song_playlist_draft.dart';

Future<void> showSongPlaylistWindow(
  BuildContext context,
  Song song, {
  required bool fluid,
}) async {
  final notifier = context.read<PlaylistContentNotifier>();
  final draft = SongPlaylistDraft(song);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final themes = InheritedTheme.capture(
    from: context,
    to: Navigator.of(context, rootNavigator: true).context,
  );
  final route = RawDialogRoute<void>(
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
              child: SongPlaylistSheet(song: song, draft: draft),
            ),
          ),
        ),
      ),
    ),
  );
  await navigator.push<void>(route);
  await route.completed;
  if (!context.mounted) return;
  var failed = false;
  for (final change in draft.changes.entries) {
    final playlist = notifier.playlists
        .where((p) => p.id == change.key && !p.isLibrary)
        .firstOrNull;
    if (playlist == null ||
        playlist.containsSongPath(song.filePath) == change.value) {
      continue;
    }
    try {
      if (change.value) {
        await notifier.addSongsToPlaylistById(change.key, [song.filePath]);
      } else {
        await notifier.removeSongsFromPlaylistById(change.key, [song.filePath]);
      }
    } catch (_) {
      failed = true;
    }
  }
  for (final playlist in draft.created) {
    try {
      if (!await notifier.saveQueueAsPlaylist(
        playlist.name,
        draft.includes(playlist) ? [song] : [],
      )) {
        failed = true;
      }
    } catch (_) {
      failed = true;
    }
  }
  if (failed && messenger != null && messenger.mounted) {
    messenger.showSnackBar(const SnackBar(content: Text('部分歌单未能更新，请重新打开检查')));
  }
}

class SongPlaylistSheet extends StatefulWidget {
  const SongPlaylistSheet({super.key, required this.song, this.draft});
  final Song song;
  final SongPlaylistDraft? draft;

  @override
  State<SongPlaylistSheet> createState() => _SongPlaylistSheetState();
}

class _SongPlaylistSheetState extends State<SongPlaylistSheet> {
  late final _draft = widget.draft ?? SongPlaylistDraft(widget.song);

  Future<void> _create() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _PlaylistNameDialog(),
    );
    if (!mounted || name == null || name.isEmpty) return;
    if ([
      ...context.read<PlaylistContentNotifier>().playlists,
      ..._draft.created,
    ].any((p) => p.name == name)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('歌单名称已存在')));
      return;
    }
    setState(() => _draft.create(name));
  }

  void _setIncluded(Playlist playlist, bool included) =>
      setState(() => _draft.setIncluded(playlist, included));

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaylistContentNotifier>();
    final playlists = [
      ...notifier.playlists.where((p) => !p.isLibrary),
      ..._draft.created,
    ];
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
              onTap: _create,
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  final included = _draft.includes(playlist);
                  final preview = _draft.changes.containsKey(playlist.id)
                      ? Playlist(
                          id: playlist.id,
                          name: playlist.name,
                          songFilePaths: playlist.songFilePaths,
                        )
                      : playlist;
                  if (!identical(preview, playlist) && !included) {
                    preview.removeSongPaths([widget.song.filePath]);
                  } else if (!identical(preview, playlist) &&
                      !preview.containsSongPath(widget.song.filePath)) {
                    preview.songFilePaths.add(widget.song.filePath);
                  }
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
                              onChanged: (_) => _setIncluded(
                                playlist,
                                !_draft.includes(playlist),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _PlaylistCover(
                              path: preview.songFilePaths.firstOrNull,
                            ),
                          ],
                        ),
                        title: Text(playlist.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('包含 ${preview.songFilePaths.length} 首歌曲'),
                            if (compact) date,
                          ],
                        ),
                        trailing: compact
                            ? null
                            : ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 88),
                                child: date,
                              ),
                        onTap: () =>
                            _setIncluded(playlist, !_draft.includes(playlist)),
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
