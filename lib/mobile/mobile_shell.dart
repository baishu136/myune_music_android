import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../page/playlist/playlist_content_notifier.dart';
import '../page/playlist/playlist_models.dart';
import '../page/pages/statistics_page.dart';
import '../page/pages/audio_analysis_page.dart';
import '../page/setting/setting_page.dart';
import '../page/setting/settings_provider.dart';
import '../page/statistics_page/statistics_manager.dart';
import '../widgets/playing_queue_drawer.dart';
import '../widgets/mobile_lyrics_list.dart';
import '../widgets/sort_dialog.dart';
import '../services/notification_service.dart';

/// Touch-first Android presentation. The desktop pages and their data model stay
/// intact; this shell only changes navigation density and common actions.
class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  static const _notificationPromptedKey = 'notification_permission_prompted';
  int _tab = 0;
  String _query = '';
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<String>? _infoSubscription;
  bool _noticeStreamsBound = false;
  bool _animateLibraryEntrance = true;
  bool _librarySelectionMode = false;
  final Set<String> _selectedLibrarySongPaths = {};

  static const _titles = ['音乐库', '歌单', '歌手', '专辑', '设置'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestNotificationPermissionOnFirstLaunch();
    });
  }

  Future<void> _requestNotificationPermissionOnFirstLaunch() async {
    if (!Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_notificationPromptedKey) ?? false) return;
    await prefs.setBool(_notificationPromptedKey, true);
    final status = await Permission.notification.request();
    if (!mounted || status.isGranted) return;
    context.read<NotificationService>().warning('未授予通知权限，后台播放时可能无法显示播放器控制栏');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_noticeStreamsBound) return;
    _noticeStreamsBound = true;
    final notifier = context.read<PlaylistContentNotifier>();
    final notices = context.read<NotificationService>();
    _errorSubscription = notifier.errorStream.listen(notices.error);
    _infoSubscription = notifier.infoStream.listen(notices.info);
  }

  @override
  void dispose() {
    _errorSubscription?.cancel();
    _infoSubscription?.cancel();
    super.dispose();
  }

  Future<void> _requestAudioAccess() async {
    final status = await Permission.audio.request();
    if (!status.isGranted) {
      if (!mounted) return;
      context.read<NotificationService>().warning('请允许“音乐和音频”权限后再导入歌曲');
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaylistContentNotifier>();
    final selecting = _tab == 0 && _librarySelectionMode;
    return Scaffold(
      appBar: AppBar(
        leading: selecting
            ? IconButton(
                tooltip: '退出多选',
                icon: const Icon(Icons.close),
                onPressed: _exitLibrarySelection,
              )
            : null,
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Text(
            selecting
                ? '已选择 ${_selectedLibrarySongPaths.length} 首'
                : _titles[_tab],
            key: ValueKey(selecting ? 'selection' : 'title-$_tab'),
          ),
        ),
        actions: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: selecting
                ? Row(
                    key: const ValueKey('selection-actions'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '全选',
                        icon: const Icon(Icons.select_all),
                        onPressed: _selectAllLibrarySongs,
                      ),
                      IconButton(
                        tooltip: '移除歌曲',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _removeSelectedLibrarySongs,
                      ),
                      IconButton(
                        tooltip: '收藏',
                        icon: const Icon(Icons.favorite_border),
                        onPressed: _favoriteSelectedLibrarySongs,
                      ),
                    ],
                  )
                : Row(
                    key: ValueKey('default-actions-$_tab'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_tab == 0 || _tab == 1)
                        IconButton(
                          tooltip: '排序歌曲',
                          icon: const Icon(Icons.sort),
                          onPressed: _showSortDialog,
                        ),
                      if (_tab != 4)
                        IconButton(
                          tooltip: '搜索',
                          icon: const Icon(Icons.search),
                          onPressed: () => _showSearch(context),
                        ),
                      IconButton(
                        tooltip: '播放队列',
                        icon: const Icon(Icons.queue_music),
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) =>
                              const SafeArea(child: PlayingQueueDrawer()),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
      body: switch (_tab) {
        0 => _LibraryTab(
          query: _query,
          animateEntrance: _animateLibraryEntrance,
          onEntranceFinished: () => _animateLibraryEntrance = false,
          selectionMode: _librarySelectionMode,
          selectedPaths: _selectedLibrarySongPaths,
          onToggleSelection: _toggleLibrarySongSelection,
        ),
        1 => const _PlaylistsTab(),
        2 => _GroupTab(groups: notifier.songsByArtist, kind: '歌手'),
        3 => _GroupTab(groups: notifier.songsByAlbum, kind: '专辑'),
        _ => const _SettingsTab(),
      },
      floatingActionButton: _tab == 1
          ? FloatingActionButton.extended(
              onPressed: _showImportOptions,
              icon: const Icon(Icons.add),
              label: const Text('添加歌曲'),
            )
          : null,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _MiniPlayer(),
            NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (index) => setState(() {
                if (index != 0) {
                  _librarySelectionMode = false;
                  _selectedLibrarySongPaths.clear();
                }
                _tab = index;
              }),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.library_music_outlined),
                  selectedIcon: Icon(Icons.library_music),
                  label: '音乐库',
                ),
                NavigationDestination(
                  icon: Icon(Icons.playlist_play_outlined),
                  selectedIcon: Icon(Icons.playlist_play),
                  label: '歌单',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: '歌手',
                ),
                NavigationDestination(
                  icon: Icon(Icons.album_outlined),
                  selectedIcon: Icon(Icons.album),
                  label: '专辑',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: '设置',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _toggleLibrarySongSelection(Song song) {
    setState(() {
      _librarySelectionMode = true;
      final path = song.normalizedPath.toLowerCase();
      if (!_selectedLibrarySongPaths.add(path)) {
        _selectedLibrarySongPaths.remove(path);
      }
      if (_selectedLibrarySongPaths.isEmpty) _librarySelectionMode = false;
    });
  }

  void _exitLibrarySelection() {
    setState(() {
      _librarySelectionMode = false;
      _selectedLibrarySongPaths.clear();
    });
  }

  void _selectAllLibrarySongs() {
    final songs = context.read<PlaylistContentNotifier>().allSongs;
    setState(() {
      _selectedLibrarySongPaths
        ..clear()
        ..addAll(songs.map((song) => song.normalizedPath.toLowerCase()));
    });
  }

  Future<void> _removeSelectedLibrarySongs() async {
    if (_selectedLibrarySongPaths.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('移除歌曲'),
        content: Text(
          '将从音乐库隐藏 ${_selectedLibrarySongPaths.length} 首歌曲。再次导入相同文件后会恢复显示。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final notifier = context.read<PlaylistContentNotifier>();
    final selectedSongs = notifier.allSongs
        .where(
          (song) => _selectedLibrarySongPaths.contains(
            song.normalizedPath.toLowerCase(),
          ),
        )
        .toList();
    await notifier.hideSongsFromLibrary(selectedSongs);
    if (mounted) _exitLibrarySelection();
  }

  Future<void> _favoriteSelectedLibrarySongs() async {
    if (_selectedLibrarySongPaths.isEmpty) return;
    final notifier = context.read<PlaylistContentNotifier>();
    final selected = notifier.allSongs
        .where(
          (song) => _selectedLibrarySongPaths.contains(
            song.normalizedPath.toLowerCase(),
          ),
        )
        .toList();
    await notifier.addSongsToFavorites(selected);
    if (mounted) _exitLibrarySelection();
  }

  Future<void> _showSortDialog() async {
    final notifier = context.read<PlaylistContentNotifier>();
    final hasSongs = _tab == 0
        ? notifier.allSongs.isNotEmpty
        : notifier.selectedIndex >= 0 &&
              notifier.currentPlaylistSongs.isNotEmpty;
    if (!hasSongs) {
      context.read<NotificationService>().warning('没有歌曲可以排序');
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const SortDialog(),
    );
    if (!mounted || result == null) return;

    final criterion = result['criterion'] as SortCriterion;
    final descending = result['descending'] as bool;
    if (_tab == 0) {
      await notifier.sortAllSongs(criterion: criterion, descending: descending);
    } else if (_tab == 1) {
      await notifier.sortCurrentPlaylist(
        criterion: criterion,
        descending: descending,
      );
    }
    if (mounted) {
      context.read<NotificationService>().success('歌曲排序已应用');
    }
  }

  Future<void> _showSearch(BuildContext context) async {
    final controller = TextEditingController(text: _query);
    await showSearch<void>(
      context: context,
      delegate: _SongSearchDelegate(
        initialQuery: _query,
        onChanged: (value) => setState(() => _query = value),
      ),
    );
    controller.dispose();
  }

  Future<void> _showImportOptions() async {
    await _requestAudioAccess();
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.audio_file_outlined),
              title: const Text('导入单曲'),
              subtitle: const Text('可一次选择一首或多首歌曲'),
              onTap: () => Navigator.pop(sheetContext, 'files'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_copy_outlined),
              title: const Text('导入整个文件夹'),
              subtitle: const Text('递归导入文件夹及子文件夹内的歌曲'),
              onTap: () => Navigator.pop(sheetContext, 'folder'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    final playlist = context.read<PlaylistContentNotifier>();
    if (action == 'folder') {
      await playlist.pickFolderAndAddSongs();
    } else {
      await playlist.pickAndAddSongs();
    }
  }
}

class _LibraryTab extends StatefulWidget {
  const _LibraryTab({
    required this.query,
    required this.animateEntrance,
    required this.onEntranceFinished,
    required this.selectionMode,
    required this.selectedPaths,
    required this.onToggleSelection,
  });
  final String query;
  final bool animateEntrance;
  final VoidCallback onEntranceFinished;
  final bool selectionMode;
  final Set<String> selectedPaths;
  final ValueChanged<Song> onToggleSelection;

  @override
  State<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<_LibraryTab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
    value: widget.animateEntrance ? 0 : 1,
  );
  bool _entranceStarted = false;

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaylistContentNotifier>();
    final songs = notifier.allSongs;
    final filtered = widget.query.isEmpty
        ? songs
        : notifier.searchSongs(widget.query, songs);
    if (widget.animateEntrance && songs.isNotEmpty && !_entranceStarted) {
      _entranceStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _entranceController.forward();
        widget.onEntranceFinished();
      });
    }
    if (songs.isEmpty) return const _EmptyLibrary();
    return _SongList(
      songs: filtered,
      entranceAnimation: widget.animateEntrance ? _entranceController : null,
      selectionMode: widget.selectionMode,
      selectedPaths: widget.selectedPaths,
      onToggleSelection: widget.onToggleSelection,
      onPlay: (index) {
        final notifier = context.read<PlaylistContentNotifier>();
        return widget.query.isEmpty
            ? notifier.playSongFromAllSongs(index)
            : notifier.playFromDynamicList(List<Song>.from(filtered), index);
      },
    );
  }
}

class _PlaylistsTab extends StatelessWidget {
  const _PlaylistsTab();

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaylistContentNotifier>();
    return Column(
      children: [
        SizedBox(
          height: 94,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            itemCount: notifier.playlists.length + 1,
            itemBuilder: (context, index) {
              if (index == notifier.playlists.length) {
                return _PlaylistCard(
                  name: '新建歌单',
                  icon: Icons.add,
                  onTap: () => _newPlaylist(context),
                );
              }
              final playlist = notifier.playlists[index];
              return _PlaylistCard(
                name: playlist.name,
                selected: index == notifier.selectedIndex,
                subtitle: '${playlist.songFilePaths.length} 首',
                onTap: () => notifier.setSelectedIndex(index),
                onLongPress: () => _showPlaylistActions(
                  context,
                  index: index,
                  playlist: playlist,
                ),
              );
            },
          ),
        ),
        Expanded(
          child: notifier.selectedIndex == -1
              ? const Center(child: Text('选择一个歌单开始管理音乐'))
              : _SongList(
                  songs: notifier.currentPlaylistSongs,
                  onPlay: (index) => notifier.playSongAtIndex(index),
                  showRemove: true,
                ),
        ),
      ],
    );
  }

  Future<void> _showPlaylistActions(
    BuildContext context, {
    required int index,
    required Playlist playlist,
  }) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.vertical_align_top),
              title: const Text('置顶歌单'),
              subtitle: playlist.isDefault ? const Text('默认歌单已固定在顶部') : null,
              enabled: !playlist.isDefault,
              onTap: playlist.isDefault
                  ? null
                  : () => Navigator.pop(sheetContext, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('移除歌单'),
              subtitle: playlist.isDefault ? const Text('默认歌单不可移除') : null,
              enabled: !playlist.isDefault,
              onTap: playlist.isDefault
                  ? null
                  : () => Navigator.pop(sheetContext, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;

    final notifier = context.read<PlaylistContentNotifier>();
    if (action == 'pin') {
      await notifier.pinPlaylist(index);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('移除歌单'),
        content: Text('确定移除歌单“${playlist.name}”吗？歌曲文件不会从设备中删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await notifier.deletePlaylist(index);
    }
  }

  Future<void> _newPlaylist(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '歌单名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty && context.mounted) {
      final folder = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('歌单类型'),
          content: const Text('普通歌单可从文件选择器添加歌曲；文件夹歌单会扫描并同步所选文件夹。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('普通歌单'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('文件夹歌单'),
            ),
          ],
        ),
      );
      if (!context.mounted || folder == null) return;
      if (!folder) {
        context.read<PlaylistContentNotifier>().addPlaylist(name);
        return;
      }
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择音乐文件夹',
      );
      if (path != null && context.mounted) {
        context.read<PlaylistContentNotifier>().addPlaylist(
          name,
          folderPaths: [path],
        );
      }
    }
  }
}

class _GroupTab extends StatelessWidget {
  const _GroupTab({required this.groups, required this.kind});
  final Map<String, List<Song>> groups;
  final String kind;

  @override
  Widget build(BuildContext context) {
    final entries = groups.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (entries.isEmpty) return const _EmptyLibrary();
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = entries[index];
        return ListTile(
          leading: CircleAvatar(
            child: Icon(kind == '歌手' ? Icons.person : Icons.album),
          ),
          title: Text(item.key),
          subtitle: Text('${item.value.length} 首歌曲'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  _SongCollectionPage(title: item.key, songs: item.value),
            ),
          ),
        );
      },
    );
  }
}

class _SongCollectionPage extends StatelessWidget {
  const _SongCollectionPage({required this.title, required this.songs});
  final String title;
  final List<Song> songs;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: _SongList(
      songs: songs,
      onPlay: (index) => context
          .read<PlaylistContentNotifier>()
          .playFromDynamicList(songs, index),
    ),
  );
}

class _SongList extends StatelessWidget {
  const _SongList({
    required this.songs,
    required this.onPlay,
    this.showRemove = false,
    this.entranceAnimation,
    this.selectionMode = false,
    this.selectedPaths = const {},
    this.onToggleSelection,
  });
  final List<Song> songs;
  final Future<void> Function(int index) onPlay;
  final bool showRemove;
  final Animation<double>? entranceAnimation;
  final bool selectionMode;
  final Set<String> selectedPaths;
  final ValueChanged<Song>? onToggleSelection;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const Center(child: Text('没有歌曲'));
    return ListView.builder(
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        final selected = selectedPaths.contains(
          song.normalizedPath.toLowerCase(),
        );
        final tile = AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          color: selected
              ? Theme.of(context).colorScheme.secondaryContainer
              : Colors.transparent,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 3,
            ),
            leading: _Cover(song: song),
            title: Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${song.artist} · ${song.album}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: selectionMode
                ? Checkbox(
                    value: selected,
                    onChanged: (_) => onToggleSelection?.call(song),
                  )
                : IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _songActions(context, song, index),
                  ),
            onLongPress: () => onToggleSelection?.call(song),
            onTap: () =>
                selectionMode ? onToggleSelection?.call(song) : onPlay(index),
          ),
        );
        final animation = entranceAnimation;
        if (animation == null) return tile;
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
          child: tile,
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
      },
    );
  }

  void _songActions(BuildContext context, Song song, int index) =>
      showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: const Text('立即播放'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onPlay(index);
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add),
                title: const Text('下一首播放'),
                onTap: () {
                  context.read<PlaylistContentNotifier>().addToPlayingQueueNext(
                    song,
                  );
                  Navigator.pop(sheetContext);
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue),
                title: const Text('添加到播放队列'),
                onTap: () {
                  context.read<PlaylistContentNotifier>().addToPlayingQueue(
                    song,
                  );
                  Navigator.pop(sheetContext);
                },
              ),
              if (showRemove)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('从当前歌单移除'),
                  onTap: () {
                    context
                        .read<PlaylistContentNotifier>()
                        .removeSongFromCurrentPlaylist(index);
                    Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        ),
      );
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer();
  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaylistContentNotifier>();
    final song = notifier.currentSong;
    if (song == null) return const SizedBox.shrink();
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: ListTile(
        leading: _Cover(song: song),
        title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const _NowPlayingPage()),
        ),
        trailing: IconButton(
          icon: Icon(
            notifier.isPlaying
                ? Icons.pause_circle_filled
                : Icons.play_circle_fill,
            size: 34,
          ),
          onPressed: notifier.isPlaying ? notifier.pause : notifier.play,
        ),
      ),
    );
  }
}

class _NowPlayingPage extends StatefulWidget {
  const _NowPlayingPage();

  @override
  State<_NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<_NowPlayingPage> {
  bool _showLyrics = false;
  double? _seekPositionMs;
  String? _lastSongPath;

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaylistContentNotifier>();
    final settings = context.watch<SettingsProvider>();
    final song = notifier.currentSong;
    if (song == null) {
      return const Scaffold(body: Center(child: Text('尚未播放歌曲')));
    }
    if (_lastSongPath != song.filePath) {
      _lastSongPath = song.filePath;
      _seekPositionMs = null;
      _showLyrics = false;
    }

    final totalMs = notifier.totalDuration.inMilliseconds.toDouble();
    final playerPosition = notifier.currentPosition.inMilliseconds
        .toDouble()
        .clamp(0, totalMs > 0 ? totalMs : 1)
        .toDouble();
    final displayPosition = (_seekPositionMs ?? playerPosition)
        .clamp(0, totalMs > 0 ? totalMs : 1)
        .toDouble();

    return Scaffold(
      appBar: AppBar(
        title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '歌曲详情',
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showSongDetails(context, notifier, song),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _showLyrics = !_showLyrics),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _showLyrics
                        ? Card(
                            key: const ValueKey('lyrics'),
                            clipBehavior: Clip.antiAlias,
                            child: MobileLyricsList(
                              lines: notifier.currentLyrics,
                              active: notifier.currentLyricLineIndex,
                            ),
                          )
                        : LayoutBuilder(
                            key: const ValueKey('cover'),
                            builder: (context, constraints) {
                              final size = constraints.biggest.shortestSide
                                  .clamp(180.0, 360.0)
                                  .toDouble();
                              return Center(
                                child: Hero(
                                  tag: song.filePath,
                                  child: _Cover(song: song, size: size),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.equalizer, size: 18),
                    label: Text(notifier.equalizerPresetName),
                    onPressed: () => _showPresetPicker(context, notifier),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Slider(
                value: displayPosition,
                max: totalMs > 0 ? totalMs : 1,
                onChangeStart: (value) =>
                    setState(() => _seekPositionMs = value),
                onChanged: (value) => setState(() => _seekPositionMs = value),
                onChangeEnd: (value) async {
                  await notifier.mediaPlayer.seek(
                    Duration(milliseconds: value.round()),
                  );
                  if (!mounted) return;
                  setState(() {
                    // Keep the chosen value visible while paused. Starting
                    // playback clears it and resumes live position updates.
                    _seekPositionMs = notifier.isPlaying ? null : value;
                  });
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _duration(
                        Duration(milliseconds: displayPosition.round()),
                      ),
                    ),
                    Text(_duration(notifier.totalDuration)),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: notifier.isFavorite(song) ? '取消收藏' : '收藏',
                    icon: Icon(
                      notifier.isFavorite(song)
                          ? Icons.favorite
                          : Icons.favorite_border,
                    ),
                    color: notifier.isFavorite(song)
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    onPressed: () => notifier.toggleFavorite(song),
                  ),
                  IconButton(
                    tooltip: '上一首',
                    icon: const Icon(Icons.skip_previous, size: 38),
                    onPressed: () {
                      setState(() => _seekPositionMs = null);
                      notifier.playPrevious();
                    },
                  ),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(18),
                    ),
                    onPressed: () {
                      if (notifier.isPlaying) {
                        notifier.pause();
                      } else {
                        setState(() => _seekPositionMs = null);
                        notifier.play();
                      }
                    },
                    child: Icon(
                      notifier.isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 42,
                    ),
                  ),
                  IconButton(
                    tooltip: '下一首',
                    icon: const Icon(Icons.skip_next, size: 38),
                    onPressed: () {
                      setState(() => _seekPositionMs = null);
                      notifier.playNext();
                    },
                  ),
                  IconButton(
                    tooltip: _modeLabel(notifier.playMode),
                    icon: Icon(_modeIcon(notifier.playMode), size: 28),
                    onPressed: notifier.togglePlayMode,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Material(
                color: Theme.of(context).colorScheme.surfaceContainer,
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: Row(
                  children: [
                    Expanded(
                      child: IconButton(
                        tooltip: '歌词源',
                        icon: const Icon(Icons.lyrics_outlined),
                        onPressed: () => _showLyricSource(context),
                      ),
                    ),
                    const SizedBox(
                      height: 30,
                      child: VerticalDivider(width: 1),
                    ),
                    Expanded(
                      child: IconButton(
                        tooltip: '歌曲列表',
                        icon: const Icon(Icons.queue_music),
                        onPressed: () => _showQueue(context),
                      ),
                    ),
                    const SizedBox(
                      height: 30,
                      child: VerticalDivider(width: 1),
                    ),
                    Expanded(
                      child: IconButton(
                        tooltip: '音频效果',
                        icon: const Icon(Icons.tune),
                        onPressed: () => _showAudioEffects(context),
                      ),
                    ),
                    if (settings.showAudioAnalysis) ...[
                      const SizedBox(
                        height: 30,
                        child: VerticalDivider(width: 1),
                      ),
                      Expanded(
                        child: IconButton(
                          tooltip: '音频分析',
                          icon: const Icon(Icons.graphic_eq),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AudioAnalysisPage(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQueue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: .82,
        child: PlayingQueueDrawer(),
      ),
    );
  }

  void _showPresetPicker(
    BuildContext context,
    PlaylistContentNotifier notifier,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('均衡器预设', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: PlaylistContentNotifier.equalizerPresets
                    .skip(1)
                    .map(
                      (preset) => ChoiceChip(
                        label: Text(preset.name),
                        selected: preset.name == notifier.equalizerPresetName,
                        onSelected: (_) {
                          notifier.applyEqualizerPreset(preset);
                          Navigator.pop(sheetContext);
                        },
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLyricSource(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Consumer<SettingsProvider>(
          builder: (context, settings, _) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('歌词源设置', style: Theme.of(context).textTheme.titleLarge),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('从网络获取歌词'),
                  value: settings.enableOnlineLyrics,
                  onChanged: settings.setEnableOnlineLyrics,
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'qq', label: Text('企鹅')),
                    ButtonSegment(value: 'netease', label: Text('网抑')),
                    ButtonSegment(value: 'kugou', label: Text('库狗')),
                  ],
                  selected: {settings.primaryLyricSource},
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) return;
                    final primary = selection.first;
                    settings.setPrimaryLyricSource(primary);
                    settings.setSecondaryLyricSource(
                      primary == 'qq' ? 'netease' : 'qq',
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAudioEffects(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: .92,
        child: _AudioEffectsSheet(),
      ),
    );
  }

  Future<void> _showSongDetails(
    BuildContext context,
    PlaylistContentNotifier notifier,
    Song song,
  ) async {
    FileStat? stat;
    if (!song.filePath.startsWith('content://')) {
      try {
        final file = File(song.filePath);
        if (await file.exists()) stat = await file.stat();
      } catch (_) {}
    }
    if (!context.mounted) return;
    final playCount =
        context
            .read<StatisticsManager>()
            .getSongStatByPath(song.filePath)
            ?.playCount ??
        0;
    final state = notifier.mediaPlayer.state;
    final bitrate = state.audioBitrate;
    final sampleRate = state.audioParams.sampleRate;
    final duration = song.duration ?? notifier.totalDuration;
    final estimatedListening = Duration(
      milliseconds: duration.inMilliseconds * playCount,
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .72,
        minChildSize: .45,
        maxChildSize: .92,
        builder: (context, controller) => SafeArea(
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Text('歌曲详情', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              _DetailRow(label: '歌曲名', value: song.title),
              _DetailRow(label: '歌手', value: song.artist),
              _DetailRow(label: '专辑', value: song.album),
              _DetailRow(label: '收听次数', value: '$playCount 次'),
              _DetailRow(
                label: '累计收听时间',
                value: '${_longDuration(estimatedListening)}（估算）',
              ),
              _DetailRow(
                label: '比特率',
                value: bitrate == null
                    ? '未知'
                    : '${(bitrate / 1000).round()} kbps',
              ),
              _DetailRow(
                label: '采样率',
                value: sampleRate == null
                    ? '未知'
                    : '${(sampleRate / 1000).toStringAsFixed(1)} kHz',
              ),
              _DetailRow(label: '时长', value: _duration(duration)),
              _DetailRow(
                label: '创建日期',
                value: stat == null ? '未知' : _dateTime(stat.changed),
              ),
              _DetailRow(
                label: '修改日期',
                value: stat == null ? '未知' : _dateTime(stat.modified),
              ),
              _DetailRow(label: '文件路径', value: song.filePath, selectable: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudioEffectsSheet extends StatefulWidget {
  const _AudioEffectsSheet();

  @override
  State<_AudioEffectsSheet> createState() => _AudioEffectsSheetState();
}

class _AudioEffectsSheetState extends State<_AudioEffectsSheet> {
  int _section = 0;

  static const _sections = [
    (icon: Icons.tune, label: '自定义均衡器'),
    (icon: Icons.spatial_audio_off, label: '空间与立体声扩张'),
    (icon: Icons.nightlight_round, label: '动态与夜间平稳'),
    (icon: Icons.equalizer, label: '音调与频响修饰'),
    (icon: Icons.auto_awesome, label: '复古与创意音效'),
    (icon: Icons.auto_fix_high, label: '修复与人声优化'),
  ];

  static const _effects = <int, List<({String id, String label})>>{
    1: [
      (id: 'crossfeed', label: '交叉混音'),
      (id: 'earwax', label: 'Bauer 空间模拟'),
      (id: 'widerStereo', label: '立体声扩展'),
      (id: 'haas', label: 'Haas 空间效果'),
      (id: 'vocalBoost', label: '人声增强'),
      (id: 'vocalRemover', label: '人声削弱'),
    ],
    2: [
      (id: 'acompressor', label: '动态范围压缩'),
      (id: 'softClip', label: '柔和削波'),
      (id: 'deNoise', label: '背景降噪'),
    ],
    3: [
      (id: 'virtualbass', label: '低音增强'),
      (id: 'subboost', label: '极重低音'),
      (id: 'crystalizer', label: '高频增强'),
      (id: 'tilt', label: '倾斜均衡'),
    ],
    4: [
      (id: 'vinyl', label: '黑胶/收音机'),
      (id: 'exciter', label: '谐波激励'),
      (id: 'echo', label: '回声与空间延迟'),
    ],
    5: [
      (id: 'deesser', label: '人声齿音消除'),
      (id: 'declip', label: '数字破音修复'),
      (id: 'arnndn', label: '人声降噪'),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaylistContentNotifier>();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 68,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              border: Border(right: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Column(
              children: [
                for (var index = 0; index < _sections.length; index++) ...[
                  Tooltip(
                    message: _sections[index].label,
                    child: IconButton.filledTonal(
                      isSelected: _section == index,
                      selectedIcon: Icon(_sections[index].icon),
                      icon: Icon(_sections[index].icon),
                      onPressed: () => setState(() => _section = index),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _sections[_section].label,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: notifier.resetAudioControls,
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('重置'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _section == 0
                      ? _equalizer(context, notifier)
                      : _effectList(context, notifier),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _equalizer(BuildContext context, PlaylistContentNotifier notifier) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Text('当前预设：${notifier.equalizerPresetName}'),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: PlaylistContentNotifier.equalizerPresets
                .skip(1)
                .map(
                  (preset) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(preset.name),
                      selected: preset.name == notifier.equalizerPresetName,
                      onSelected: (_) => notifier.applyEqualizerPreset(preset),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 8),
        ...List.generate(PlaylistContentNotifier.equalizerFrequencies.length, (
          index,
        ) {
          final frequency = PlaylistContentNotifier.equalizerFrequencies[index];
          final gain = notifier.equalizerGains[index];
          return Row(
            children: [
              SizedBox(width: 42, child: Text(_frequency(frequency))),
              Expanded(
                child: Slider(
                  min: -12,
                  max: 12,
                  divisions: 48,
                  value: gain,
                  onChanged: (value) => notifier.setEqualizerBand(index, value),
                  onChangeEnd: (value) =>
                      notifier.commitEqualizerBand(index, value),
                ),
              ),
              SizedBox(width: 55, child: Text('${gain.toStringAsFixed(1)} dB')),
            ],
          );
        }),
      ],
    );
  }

  Widget _effectList(BuildContext context, PlaylistContentNotifier notifier) {
    final effects = _effects[_section] ?? const [];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Text(
          '音效可组合使用；存在冲突的效果会自动互斥。',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: effects.map((effect) {
            final selected = notifier.isEffectEnabled(effect.id);
            return FilterChip(
              selected: selected,
              showCheckmark: true,
              avatar: Icon(_effectIcon(effect.id), size: 18),
              label: Text(effect.label),
              onSelected: (enabled) async {
                if (effect.id == 'arnndn' &&
                    enabled &&
                    notifier.arnndnModelPath == null) {
                  final path = await _pickNoiseModel();
                  if (path == null) return;
                  await notifier.setArnndnModelPath(path);
                }
                await notifier.toggleEffect(effect.id, enabled);
              },
            );
          }).toList(),
        ),
        if (_section == 5) ...[
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () async {
              final path = await _pickNoiseModel();
              if (path == null) return;
              await notifier.setArnndnModelPath(path);
              if (context.mounted) {
                context.read<NotificationService>().success('人声降噪模型已保存');
              }
            },
            icon: const Icon(Icons.folder_open),
            label: Text(
              notifier.arnndnModelPath == null ? '选择 .rnnn 模型' : '更换降噪模型',
            ),
          ),
        ],
      ],
    );
  }

  Future<String?> _pickNoiseModel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['rnnn'],
      );
      final source = result?.files.single.path;
      if (source == null) return null;
      final directory = await getApplicationSupportDirectory();
      final modelDirectory = Directory(p.join(directory.path, 'models'));
      await modelDirectory.create(recursive: true);
      final destination = p.join(modelDirectory.path, p.basename(source));
      await File(source).copy(destination);
      return destination;
    } catch (error) {
      if (mounted) {
        context.read<NotificationService>().error('无法保存降噪模型：$error');
      }
      return null;
    }
  }

  IconData _effectIcon(String id) => switch (id) {
    'crossfeed' || 'earwax' || 'widerStereo' || 'haas' => Icons.surround_sound,
    'vocalBoost' ||
    'vocalRemover' ||
    'deesser' ||
    'arnndn' => Icons.record_voice_over,
    'acompressor' || 'softClip' => Icons.compress,
    'deNoise' => Icons.noise_control_off,
    'virtualbass' || 'subboost' => Icons.speaker,
    'crystalizer' || 'tilt' => Icons.equalizer,
    'vinyl' => Icons.album,
    'exciter' => Icons.bolt,
    'echo' => Icons.multitrack_audio,
    'declip' => Icons.healing,
    _ => Icons.tune,
  };
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Expanded(child: SettingPage()),
        const Divider(height: 1),
        ListTile(
          dense: true,
          leading: const Icon(Icons.leaderboard_outlined),
          title: const Text('播放统计'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const StatisticsPage()),
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 104,
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        Expanded(child: selectable ? SelectableText(value) : Text(value)),
      ],
    ),
  );
}

class _Cover extends StatefulWidget {
  const _Cover({required this.song, this.size = 48});
  final Song song;
  final double size;

  @override
  State<_Cover> createState() => _CoverState();
}

class _CoverState extends State<_Cover> {
  PlaylistContentNotifier? _notifier;
  String? _requestedPath;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _notifier ??= context.read<PlaylistContentNotifier>();
    _requestCover(widget.song.filePath);
  }

  @override
  void didUpdateWidget(covariant _Cover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.filePath != widget.song.filePath) {
      _releaseCover();
      _requestCover(widget.song.filePath);
    }
  }

  void _requestCover(String filePath) {
    if (_requestedPath == filePath) return;
    _requestedPath = filePath;
    _notifier?.requestSongCover(filePath);
  }

  void _releaseCover() {
    final path = _requestedPath;
    if (path != null) {
      _notifier?.releaseSongCover(path);
      _requestedPath = null;
    }
  }

  @override
  void dispose() {
    _releaseCover();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final art = widget.song.albumArt;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: art == null
            ? ColoredBox(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Icon(Icons.music_note, size: widget.size * .5),
              )
            : Image.memory(art, fit: BoxFit.cover),
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.name,
    required this.onTap,
    this.subtitle,
    this.selected = false,
    this.icon = Icons.queue_music,
    this.onLongPress,
  });
  final String name;
  final String? subtitle;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.secondaryContainer
            : Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 120,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon),
                  const Spacer(),
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SongSearchDelegate extends SearchDelegate<void> {
  _SongSearchDelegate({required String initialQuery, required this.onChanged}) {
    query = initialQuery;
  }

  final ValueChanged<String> onChanged;

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
          onChanged(query);
        },
      ),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () {
      onChanged(query);
      close(context, null);
    },
  );

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final notifier = context.watch<PlaylistContentNotifier>();
    final songs = notifier.searchSongs(query, notifier.allSongs);
    return _SongList(
      songs: songs,
      onPlay: (index) => context
          .read<PlaylistContentNotifier>()
          .playFromDynamicList(songs, index),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.audio_file_outlined, size: 56),
          SizedBox(height: 16),
          Text('还没有音乐'),
          Text('进入“歌单”，新建或选择歌单后添加本地音频文件。', textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

String _duration(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

String _longDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  if (hours == 0) return '$minutes 分钟';
  return '$hours 小时 $minutes 分钟';
}

String _frequency(num value) => value >= 1000
    ? '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}k'
    : value.toStringAsFixed(0);

String _dateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

String _modeLabel(PlayMode mode) => switch (mode) {
  PlayMode.shuffle => '随机播放',
  PlayMode.repeatOne => '单曲循环',
  _ => '列表循环',
};

IconData _modeIcon(PlayMode mode) => switch (mode) {
  PlayMode.shuffle => Icons.shuffle,
  PlayMode.repeatOne => Icons.repeat_one,
  _ => Icons.repeat,
};
