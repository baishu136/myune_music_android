import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../page/playlist/playlist_content_notifier.dart';
import '../page/playlist/playlist_models.dart';
import '../page/pages/statistics_page.dart';
import '../page/setting/setting_page.dart';
import '../page/setting/settings_provider.dart';
import '../page/statistics_page/statistics_manager.dart';
import '../widgets/playing_queue_drawer.dart';
import '../widgets/mobile_lyrics_list.dart';

/// Touch-first Android presentation. The desktop pages and their data model stay
/// intact; this shell only changes navigation density and common actions.
class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  int _tab = 0;
  String _query = '';

  static const _titles = ['音乐库', '歌单', '歌手', '专辑', '设置'];

  Future<void> _requestAudioAccess() async {
    final status = await Permission.audio.request();
    if (!status.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请允许“音乐和音频”权限后再导入歌曲')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaylistContentNotifier>();
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
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
              builder: (_) => const SafeArea(child: PlayingQueueDrawer()),
            ),
          ),
        ],
      ),
      body: switch (_tab) {
        0 => _LibraryTab(query: _query),
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
              onDestinationSelected: (index) => setState(() => _tab = index),
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

class _LibraryTab extends StatelessWidget {
  const _LibraryTab({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final songs = context.watch<PlaylistContentNotifier>().allSongs;
    final filtered = query.isEmpty
        ? songs
        : songs
              .where(
                (song) => '${song.title} ${song.artist} ${song.album}'
                    .toLowerCase()
                    .contains(query.toLowerCase()),
              )
              .toList();
    if (songs.isEmpty) return const _EmptyLibrary();
    return _SongList(
      songs: filtered,
      onPlay: (index) =>
          context.read<PlaylistContentNotifier>().playSongFromAllSongs(index),
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
  });
  final List<Song> songs;
  final Future<void> Function(int index) onPlay;
  final bool showRemove;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const Center(child: Text('没有歌曲'));
    return ListView.builder(
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 3,
          ),
          leading: _Cover(song: song),
          title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${song.artist} · ${song.album}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _songActions(context, song, index),
          ),
          onTap: () => onPlay(index),
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
                        tooltip: '自定义均衡器',
                        icon: const Icon(Icons.tune),
                        onPressed: () => _showEqualizer(context, notifier),
                      ),
                    ),
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

  void _showEqualizer(BuildContext context, PlaylistContentNotifier notifier) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .88,
        minChildSize: .55,
        maxChildSize: .95,
        builder: (context, controller) => SafeArea(
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Row(
                children: [
                  Text('自定义均衡器', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  TextButton(
                    onPressed: notifier.resetAudioControls,
                    child: const Text('重置'),
                  ),
                ],
              ),
              Text('当前预设：${notifier.equalizerPresetName}'),
              const SizedBox(height: 8),
              ...List.generate(
                PlaylistContentNotifier.equalizerFrequencies.length,
                (index) {
                  final frequency =
                      PlaylistContentNotifier.equalizerFrequencies[index];
                  final gain = notifier.equalizerGains[index];
                  return Row(
                    children: [
                      SizedBox(width: 58, child: Text(_frequency(frequency))),
                      Expanded(
                        child: Slider(
                          min: -12,
                          max: 12,
                          divisions: 48,
                          value: gain,
                          onChanged: (value) =>
                              notifier.setEqualizerBand(index, value),
                          onChangeEnd: (value) =>
                              notifier.commitEqualizerBand(index, value),
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: Text('${gain.toStringAsFixed(1)} dB'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
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
  });
  final String name;
  final String? subtitle;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;
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
    final songs = context
        .watch<PlaylistContentNotifier>()
        .allSongs
        .where(
          (song) => '${song.title} ${song.artist} ${song.album}'
              .toLowerCase()
              .contains(query.toLowerCase()),
        )
        .toList();
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
