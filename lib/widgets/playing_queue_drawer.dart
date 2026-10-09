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
  final _searchController = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_notifier != null) return;
    final notifier = context.read<PlaylistContentNotifier>();
    _notifier = notifier;
    _originalSource = notifier.capturePlaybackSource();
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
    _searchController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<PlaylistContentNotifier, SettingsProvider>(
      builder: (context, notifier, settings, child) {
        final currentSong = notifier.currentSong;
        final librarySongs = notifier.allSongs;
        // Resolve live metadata on every notifier update, not only on entry.
        final artists = currentSong == null
            ? const <String>[]
            : notifier.getIndividualArtists(currentSong.artist);
        final drawerArtist = artists.isEmpty ? '' : artists.first;
        final drawerAlbum = currentSong?.album ?? '';
        final artistSongs = _scope != _QueueScope.artist
            ? const <Song>[]
            : librarySongs
                  .where(
                    (song) =>
                        currentSong != null &&
                        notifier
                            .getIndividualArtists(song.artist)
                            .contains(drawerArtist),
                  )
                  .toList(growable: false);
        final albumSongs = _scope != _QueueScope.album
            ? const <Song>[]
            : librarySongs
                  .where(
                    (song) => currentSong != null && song.album == drawerAlbum,
                  )
                  .toList(growable: false);
        final playlistSongs = _scope == _QueueScope.playlists
            ? _songsForPlaylist(notifier, _selectedPlaylist)
            : const <Song>[];
        final songs = switch (_scope) {
          _QueueScope.library => librarySongs,
          _QueueScope.artist => artistSongs,
          _QueueScope.album => albumSongs,
          _QueueScope.search => notifier.searchSongs(
            _searchController.text,
            librarySongs,
          ),
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
                  Expanded(
                    child: _QueueScopeButton(
                      label: '歌手',
                      icon: Icons.person_outline,
                      selected: _scope == _QueueScope.artist,
                      enabled: drawerArtist.trim().isNotEmpty,
                      onTap: () => _setSongScope(_QueueScope.artist),
                    ),
                  ),
                  Expanded(
                    child: _QueueScopeButton(
                      label: '专辑',
                      icon: Icons.album_outlined,
                      selected: _scope == _QueueScope.album,
                      enabled: drawerAlbum.trim().isNotEmpty,
                      onTap: () => _setSongScope(_QueueScope.album),
                    ),
                  ),
                  Expanded(
                    child: _QueueScopeButton(
                      label: '搜索',
                      icon: Icons.search,
                      selected: _scope == _QueueScope.search,
                      onTap: () => _setSongScope(_QueueScope.search),
                    ),
                  ),
                  IconButton(
                    tooltip: '歌单',
                    color: _scope == _QueueScope.playlists
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    icon: const Icon(Icons.playlist_play),
                    onPressed: () => _setSongScope(_QueueScope.playlists),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (_scope == _QueueScope.search)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  key: const ValueKey('queue-library-search'),
                  controller: _searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: '搜索音乐库',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除搜索',
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(_searchController.clear),
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),

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
        final safeContent = SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: _scope == _QueueScope.search
                  ? MediaQuery.viewInsetsOf(context).bottom
                  : 0,
            ),
            child: queueContent,
          ),
        );
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
    _QueueScope.album => '当前专辑没有可用歌曲',
    _QueueScope.search => '没有匹配的歌曲',
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
      case _QueueScope.album:
        await notifier.playFromDynamicList(songs, index);
        return;
      case _QueueScope.search:
        await notifier.playAllSongsSearchResult(songs[index]);
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
    FocusScope.of(context).unfocus();
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

enum _QueueScope { library, artist, album, search, playlists }

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
        ? scheme.primary
        : scheme.onSurfaceVariant;
    return IconButton(
      tooltip: label,
      isSelected: selected,
      color: color,
      icon: Icon(icon, size: 22),
      onPressed: enabled ? onTap : null,
    );
  }
}
