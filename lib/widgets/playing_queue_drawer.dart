import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:silky_scroll/silky_scroll.dart';
import '../theme/scroll_config.dart';

import '../page/playlist/playlist_content_notifier.dart';
import '../page/playlist/playlist_content_widget.dart';
import '../page/playlist/playlist_models.dart';
import '../page/setting/settings_provider.dart';
import 'custom_theme_background.dart';

class PlayingQueueDrawer extends StatefulWidget {
  const PlayingQueueDrawer({
    super.key,
    this.transparentBackground = false,
    this.syncHomeBackground = true,
  });

  final bool transparentBackground;
  final bool syncHomeBackground;

  @override
  State<PlayingQueueDrawer> createState() => PlayingQueueDrawerState();
}

class PlayingQueueDrawerState extends State<PlayingQueueDrawer>
    with SingleTickerProviderStateMixin {
  late final ScrollController scrollController = ScrollController();
  late final AnimationController _scopeEntranceController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
    value: 1,
  );
  _QueueScope _scope = _QueueScope.library;
  _QueueScope? _lastSelectionScope;
  Playlist? _selectedPlaylist;
  PlaylistContentNotifier? _notifier;
  PlaybackSourceSnapshot? _originalSource;
  String _drawerArtist = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_notifier != null) return;
    final notifier = context.read<PlaylistContentNotifier>();
    _notifier = notifier;
    _originalSource = notifier.capturePlaybackSource();
    final song = notifier.currentSong;
    if (song != null) {
      final artists = notifier.getIndividualArtists(song.artist);
      _drawerArtist = artists.isEmpty ? song.artist : artists.first;
    }
  }

  @override
  void dispose() {
    final notifier = _notifier;
    final originalSource = _originalSource;
    if (notifier != null &&
        originalSource != null &&
        _lastSelectionScope != null &&
        _lastSelectionScope != _scope) {
      unawaited(notifier.restorePlaybackSource(originalSource));
    }
    _scopeEntranceController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<PlaylistContentNotifier, SettingsProvider>(
      builder: (context, notifier, settings, child) {
        final currentSong = notifier.currentSong;
        final librarySongs = notifier.allSongs;
        final artistSongs = librarySongs
            .where(
              (song) => notifier
                  .getIndividualArtists(song.artist)
                  .contains(_drawerArtist),
            )
            .toList(growable: false);
        final playlistSongs = _songsForPlaylist(notifier, _selectedPlaylist);
        final songs = switch (_scope) {
          _QueueScope.library => librarySongs,
          _QueueScope.artist => artistSongs,
          _QueueScope.playlists => playlistSongs,
        };

        final queueContent = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: _QueueScopeButton(
                      label: '音乐库',
                      icon: Icons.library_music_outlined,
                      selected: _scope == _QueueScope.library,
                      onTap: () => _setSongScope(_QueueScope.library),
                    ),
                  ),
                  const SizedBox(
                    height: 38,
                    child: VerticalDivider(width: 1, thickness: 1),
                  ),
                  Expanded(
                    child: _QueueScopeButton(
                      label: '歌手歌曲',
                      icon: Icons.person_outline,
                      selected: _scope == _QueueScope.artist,
                      enabled: _drawerArtist.trim().isNotEmpty,
                      onTap: () => _setSongScope(_QueueScope.artist),
                    ),
                  ),
                  IconButton(
                    tooltip: '歌单',
                    color: _scope == _QueueScope.playlists
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    icon: const Icon(Icons.playlist_play),
                    onPressed: () => _setSongScope(_QueueScope.playlists),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            if (_scope == _QueueScope.playlists && _selectedPlaylist == null)
              Expanded(child: _buildPlaylistList(context, notifier))
            else if (songs.isEmpty)
              Expanded(child: Center(child: Text(_emptyMessage)))
            else
              Expanded(
                child: Column(
                  children: [
                    if (_scope == _QueueScope.playlists)
                      ListTile(
                        leading: const Icon(Icons.arrow_back),
                        title: Text(_selectedPlaylist?.name ?? '歌单'),
                        onTap: () {
                          setState(() => _selectedPlaylist = null);
                          _restartEntrance();
                        },
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: SilkyScroll(
                          controller: scrollController,
                          silkyScrollDuration: ScrollConfig.duration,
                          scrollSpeed: ScrollConfig.speed,
                          animationCurve: ScrollConfig.curve,
                          builder: (context, controller, physics, _) =>
                              ListView.builder(
                                controller: controller,
                                physics: physics,
                                itemCount: songs.length,
                                itemBuilder: (context, index) {
                                  final song = songs[index];
                                  return _QueueEntranceItem(
                                    key: ValueKey(song.filePath),
                                    index: index,
                                    animation: _scopeEntranceController,
                                    child: SongTileWidget(
                                      song: song,
                                      index: index,
                                      enableContextMenu: false,
                                      contextPlaylist:
                                          _scope == _QueueScope.playlists &&
                                              _selectedPlaylist != null
                                          ? _selectedPlaylist!
                                          : notifier.allSongsVirtualPlaylist,
                                      onTap: () =>
                                          _playSong(notifier, songs, index),
                                    ),
                                  );
                                },
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
        final embeddedCover = currentSong?.albumArt;
        final currentCover = embeddedCover != null && embeddedCover.isNotEmpty
            ? embeddedCover
            : currentSong == null
            ? null
            : notifier.coverForSongPath(currentSong.filePath);
        final safeContent = SafeArea(child: queueContent);
        final content = !widget.syncHomeBackground
            ? safeContent
            : CustomThemeBackground(
                path: settings.homeThemeImagePath,
                enabled: settings.homeThemeImageEnabled,
                dim: settings.homeThemeImageDim,
                blurSigma: settings.homeThemeImageBlur,
                coverBytes: currentCover,
                coverEnabled:
                    settings.followAlbumArtOnHome &&
                    currentCover != null &&
                    currentCover.isNotEmpty,
                coverDim: settings.homeAlbumArtBackgroundDim,
                coverBlurSigma: settings.homeAlbumArtBackgroundBlur,
                child: safeContent,
              );
        if (widget.transparentBackground) {
          return Material(
            color: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            clipBehavior: Clip.antiAlias,
            child: content,
          );
        }
        return Drawer(width: 400, child: content);
      },
    );
  }

  String get _emptyMessage => switch (_scope) {
    _QueueScope.library => '音乐库中没有歌曲',
    _QueueScope.artist => '当前歌手没有可用歌曲',
    _QueueScope.playlists => '歌单中没有歌曲',
  };

  List<Song> _songsForPlaylist(
    PlaylistContentNotifier notifier,
    Playlist? playlist,
  ) {
    if (playlist == null) return const [];
    final loaded = playlist.songs;
    if (loaded != null && loaded.isNotEmpty) return loaded;
    final byPath = {
      for (final song in notifier.allSongs)
        song.normalizedPath.toLowerCase(): song,
    };
    return playlist.songFilePaths
        .map((path) => byPath[p.normalize(path).toLowerCase()])
        .whereType<Song>()
        .toList(growable: false);
  }

  Widget _buildPlaylistList(
    BuildContext context,
    PlaylistContentNotifier notifier,
  ) {
    final playlists = notifier.playlists
        .where((playlist) => !playlist.isDefault)
        .toList(growable: false);
    if (playlists.isEmpty) {
      return const Center(child: Text('暂无已创建的歌单'));
    }
    return ListView.builder(
      controller: scrollController,
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return ListTile(
          leading: const Icon(Icons.queue_music),
          title: Text(playlist.name),
          subtitle: Text('${playlist.songFilePaths.length} 首歌曲'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            setState(() => _selectedPlaylist = playlist);
            _restartEntrance();
          },
        );
      },
    );
  }

  Future<void> _playSong(
    PlaylistContentNotifier notifier,
    List<Song> songs,
    int index,
  ) async {
    _lastSelectionScope = _scope;
    switch (_scope) {
      case _QueueScope.library:
        await notifier.playSongFromAllSongs(index);
        return;
      case _QueueScope.artist:
        await notifier.playFromDynamicList(songs, index);
        return;
      case _QueueScope.playlists:
        final playlist = _selectedPlaylist;
        if (playlist != null) {
          await notifier.playSongFromPlaylist(playlist, index);
        }
        return;
    }
  }

  void _setSongScope(_QueueScope scope) {
    if (_scope == scope &&
        !(scope == _QueueScope.playlists && _selectedPlaylist != null)) {
      return;
    }
    if (scrollController.hasClients) {
      scrollController.jumpTo(0);
    }
    _scopeEntranceController.stop();
    setState(() {
      _scope = scope;
      if (scope == _QueueScope.playlists) _selectedPlaylist = null;
      _scopeEntranceController.value = 0;
    });
    _scopeEntranceController.forward();
  }

  void _restartEntrance() {
    if (!mounted) return;
    _scopeEntranceController
      ..stop()
      ..value = 0
      ..forward();
  }
}

enum _QueueScope { library, artist, playlists }

class _QueueEntranceItem extends StatelessWidget {
  const _QueueEntranceItem({
    super.key,
    required this.index,
    required this.animation,
    required this.child,
  });

  final int index;
  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final group = index.clamp(0, 4);
    final start = group * 0.08;
    final end = (start + 0.55).clamp(0.0, 1.0);
    final distance = switch (group) {
      0 => 100.0,
      1 => 75.0,
      2 => 50.0,
      3 => 25.0,
      _ => 25.0,
    };
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final progress = Curves.easeOutCubic.transform(
          Interval(start, end).transform(animation.value),
        );
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, distance * (1 - progress)),
            child: child,
          ),
        );
      },
    );
  }
}

class _QueueScopeButton extends StatelessWidget {
  const _QueueScopeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = !enabled
        ? Theme.of(context).disabledColor
        : selected
        ? Colors.white
        : scheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
