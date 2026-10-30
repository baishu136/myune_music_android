import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:silky_scroll/silky_scroll.dart';
import '../../theme/scroll_config.dart';
import '../playlist/playlist_content_notifier.dart';
import '../playlist/playlist_models.dart';
import '../setting/settings_provider.dart';
import 'statistics_manager.dart';
import '../../widgets/artwork_image.dart';
import '../../widgets/home_glass_surface.dart';

enum StatisticsRanking {
  songs('歌曲播放排行'),
  artists('艺术家播放排行'),
  albums('专辑播放排行');

  const StatisticsRanking(this.title);
  final String title;
}

class Statistics extends StatefulWidget {
  const Statistics({
    super.key,
    this.ranking,
    this.backgroundEnabled = false,
    this.onOpenRanking,
  });
  final StatisticsRanking? ranking;
  final bool backgroundEnabled;
  final ValueChanged<StatisticsRanking>? onOpenRanking;
  @override
  State<Statistics> createState() => _StatisticsState();
}

class _StatisticsState extends State<Statistics> {
  final _scroll = ScrollController();
  Object? _libraryKey, _rankingKey;
  final _rankings = <StatisticsRanking, List<_RankedItem>>{};
  final _songsByPath = <String, Song>{}, _songsByFile = <String, Song>{};
  final _artists = <String, Song>{}, _albums = <String, Song>{};
  List<Song> _songs = const [];
  Duration _totalDuration = Duration.zero;
  int? _libraryBytes;
  int? _sizeSignature, _seenLibraryRevision;
  int _librarySignature = 0;
  int _sizeGeneration = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant Statistics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ranking != widget.ranking) _rankings.clear();
  }

  Iterable<String> _split(String artists, List<String> separators) {
    var parts = [artists];
    for (final separator in separators) {
      if (separator.isEmpty) continue;
      parts = parts.expand((part) => part.split(separator)).toList();
    }
    return parts
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toSet();
  }

  void _prefer(Map<String, Song> index, String key, Song song) {
    if (!index.containsKey(key) ||
        (index[key]!.albumArt == null && song.albumArt != null)) {
      index[key] = song;
    }
  }

  int _readLibrarySignature(PlaylistContentNotifier library) {
    if (_seenLibraryRevision != library.libraryRevision) {
      _seenLibraryRevision = library.libraryRevision;
      _librarySignature = Object.hashAll(
        library.allSongs.map(
          (song) => Object.hash(
            song.normalizedPath,
            song.title,
            song.artist,
            song.album,
            song.duration,
          ),
        ),
      );
    }
    return _librarySignature;
  }

  void _syncLibrary(
    PlaylistContentNotifier library,
    List<String> separators,
    int signature,
  ) {
    final key = (signature, Object.hashAll(separators));
    if (_libraryKey == key) return;
    _libraryKey = key;
    _songs = library.allSongs;
    _songsByPath.clear();
    _songsByFile.clear();
    _artists.clear();
    _albums.clear();
    _totalDuration = Duration.zero;
    for (final song in _songs) {
      _songsByPath[song.normalizedPath.toLowerCase()] = song;
      _prefer(_songsByFile, p.basename(song.filePath), song);
      for (final artist in _split(song.artist, separators)) {
        _prefer(_artists, artist, song);
      }
      if (song.album.trim().isNotEmpty) _prefer(_albums, song.album, song);
      _totalDuration += song.duration ?? Duration.zero;
    }
    final sizeSignature = Object.hashAllUnordered(
      _songs.map((song) => song.normalizedPath.toLowerCase()),
    );
    if (widget.ranking == null && sizeSignature != _sizeSignature) {
      _sizeSignature = sizeSignature;
      _libraryBytes = null;
      final generation = ++_sizeGeneration;
      _calculateLibraryBytes(
        _songs.map((song) => song.filePath).toList(growable: false),
        generation,
      ).then((bytes) {
        if (mounted && generation == _sizeGeneration) {
          setState(() => _libraryBytes = bytes);
        }
      });
    }
  }

  List<_RankedItem> _items(
    StatisticsRanking kind,
    StatisticsManager stats,
    List<String> separators,
  ) => _rankings.putIfAbsent(kind, () {
    final limit = widget.ranking == null ? 5 : 0x7fffffff;
    if (kind == StatisticsRanking.songs) {
      return stats
          .getTopPlayedSongs(limit)
          .map((stat) {
            final fallback = Song(
              title: stat.title,
              artist: stat.artist,
              album: stat.album,
              filePath: stat.path,
            );
            final song =
                _songsByPath[fallback.normalizedPath.toLowerCase()] ??
                _songsByFile[p.basename(stat.path)] ??
                fallback;
            return _RankedItem(
              stat.path,
              stat.title,
              stat.playCount,
              song,
              artist: stat.artist,
              album: stat.album,
            );
          })
          .toList(growable: false);
    }
    final groups = kind == StatisticsRanking.artists
        ? stats.getTopArtists(limit, separators)
        : stats.getTopAlbums(limit);
    final covers = kind == StatisticsRanking.artists ? _artists : _albums;
    return groups
        .map(
          (entry) =>
              _RankedItem(entry.key, entry.key, entry.value, covers[entry.key]),
        )
        .toList(growable: false);
  });

  @override
  Widget build(BuildContext context) {
    final library = context.read<PlaylistContentNotifier>();
    final librarySignature = context.select<PlaylistContentNotifier, int>(
      _readLibrarySignature,
    );
    final revision = context.select<StatisticsManager, int>(
      (value) => value.songRevision,
    );
    final stats = context.read<StatisticsManager>();
    final settings = context.watch<SettingsProvider>();
    final separators = settings.artistSeparators;
    _syncLibrary(library, separators, librarySignature);
    final key = (revision, _libraryKey);
    if (_rankingKey != key) {
      _rankingKey = key;
      _rankings.clear();
    }
    final ranking = widget.ranking;
    if (ranking != null) {
      final rows = _items(ranking, stats, separators);
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
        child: _surface(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  ranking.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? Align(alignment: Alignment.topLeft, child: _empty())
                    : SilkyScroll(
                        controller: _scroll,
                        silkyScrollDuration: ScrollConfig.duration,
                        scrollSpeed: ScrollConfig.speed,
                        animationCurve: ScrollConfig.curve,
                        builder: (_, controller, physics, _) =>
                            ListView.separated(
                              key: ValueKey(
                                'statistics-ranking-${ranking.name}',
                              ),
                              controller: controller,
                              physics: physics,
                              padding: EdgeInsets.symmetric(
                                vertical: ranking == StatisticsRanking.songs
                                    ? 2
                                    : 8,
                              ),
                              itemCount: rows.length,
                              separatorBuilder: (_, _) => Divider(
                                height: ranking == StatisticsRanking.songs
                                    ? 2
                                    : 16,
                              ),
                              itemBuilder: (_, index) =>
                                  _tile(rows[index], ranking, settings),
                            ),
                      ),
              ),
            ],
          ),
        ),
      );
    }
    final played = context.select<StatisticsManager, Duration>(
      (value) => value.totalPlaybackDuration,
    );
    return SilkyScroll(
      controller: _scroll,
      silkyScrollDuration: ScrollConfig.duration,
      scrollSpeed: ScrollConfig.speed,
      animationCurve: ScrollConfig.curve,
      builder: (_, controller, physics, _) => SingleChildScrollView(
        controller: controller,
        physics: physics,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _surface(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(stats),
                    const SizedBox(height: 16),
                    _stat(Icons.music_note, '总歌曲数', '${_songs.length}'),
                    _stat(Icons.album, '总专辑数', '${_albums.length}'),
                    _stat(Icons.person, '总歌手数', '${_artists.length}'),
                    _stat(
                      Icons.access_time,
                      '总时长',
                      '${_totalDuration.inHours.toString().padLeft(2, '0')}:${(_totalDuration.inMinutes % 60).toString().padLeft(2, '0')}:${(_totalDuration.inSeconds % 60).toString().padLeft(2, '0')}',
                    ),
                    _stat(
                      Icons.storage_outlined,
                      '曲库空间',
                      _libraryBytes == null
                          ? '计算中…'
                          : '${(_libraryBytes! / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB',
                    ),
                    _stat(
                      Icons.timelapse,
                      '累计播放时长',
                      played.inHours > 0
                          ? '${played.inHours} 小时 ${played.inMinutes.remainder(60)} 分钟'
                          : '${played.inMinutes} 分钟',
                    ),
                  ],
                ),
              ),
              for (final kind in StatisticsRanking.values) ...[
                const SizedBox(height: 24),
                _rankingSection(
                  kind,
                  _items(kind, stats, separators),
                  settings,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _surface(Widget child) => HomePlaylistCard(child: child);
  Widget _empty() => Padding(
    padding: const EdgeInsets.all(16),
    child: Text('暂无播放记录', style: Theme.of(context).textTheme.bodyMedium),
  );

  Widget _stat(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 76),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                '$label：$value',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _rankingSection(
    StatisticsRanking kind,
    List<_RankedItem> rows,
    SettingsProvider settings,
  ) => _surface(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(kind, rows.length),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          _empty()
        else
          Padding(
            padding: EdgeInsets.symmetric(
              vertical: kind == StatisticsRanking.songs ? 2 : 8,
            ),
            child: Column(
              children: [
                for (var index = 0; index < rows.length; index++) ...[
                  if (index > 0)
                    Divider(height: kind == StatisticsRanking.songs ? 2 : 16),
                  _tile(rows[index], kind, settings),
                ],
              ],
            ),
          ),
      ],
    ),
  );

  Widget _heading(StatisticsRanking kind, int count) {
    final row = Row(
      children: [
        Expanded(
          child: Text(
            kind.title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        if (count >= 5)
          TextButton(
            onPressed: () => widget.onOpenRanking?.call(kind),
            child: const Text('查看更多'),
          ),
      ],
    );
    return Padding(padding: const EdgeInsets.only(left: 12), child: row);
  }

  Widget _header(StatisticsManager stats) {
    final row = Row(
      children: [
        Text('统计信息', style: Theme.of(context).textTheme.titleLarge),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: '重置统计数据',
          onPressed: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('确认重置'),
                content: const Text('此操作将清空所有播放记录，且无法撤销'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('确定'),
                  ),
                ],
              ),
            );
            if (confirm == true) await stats.clearAllStats();
          },
        ),
      ],
    );
    return Padding(padding: const EdgeInsets.only(left: 12), child: row);
  }

  Widget _tile(
    _RankedItem item,
    StatisticsRanking kind,
    SettingsProvider settings,
  ) => ListTile(
    key: ValueKey('${kind.name}-${item.id}'),
    leading: _StatisticsCover(
      key: ValueKey('${kind.name}-cover-${item.id}'),
      song: item.cover,
      kind: kind,
    ),
    title: Text(item.title),
    subtitle: kind == StatisticsRanking.songs
        ? Text(
            settings.showAlbumName
                ? '${item.artist} - ${item.album}'
                : item.artist!,
          )
        : null,
    trailing: Text('${item.count} 次'),
  );

  Future<int> _calculateLibraryBytes(List<String> paths, int generation) async {
    var bytes = 0;
    for (final path in paths) {
      if (!mounted || generation != _sizeGeneration) break;
      try {
        bytes += await File(path).length();
      } on FileSystemException {
        continue;
      }
    }
    return bytes;
  }
}

class _RankedItem {
  const _RankedItem(
    this.id,
    this.title,
    this.count,
    this.cover, {
    this.artist,
    this.album,
  });
  final String id, title;
  final int count;
  final Song? cover;
  final String? artist, album;
}

class _StatisticsCover extends StatefulWidget {
  const _StatisticsCover({super.key, required this.song, required this.kind});
  final Song? song;
  final StatisticsRanking kind;
  @override
  State<_StatisticsCover> createState() => _StatisticsCoverState();
}

class _StatisticsCoverState extends State<_StatisticsCover> {
  PlaylistContentNotifier? _library;
  Listenable? _signal;
  String? _path;
  bool _requested = false;
  int _generation = 0;
  void _release() {
    if (_requested) {
      final library = _library!, path = _path!;
      Future.microtask(() => library.releaseSongCover(path));
    }
    _requested = false;
    _generation++;
  }

  void _bind() {
    final library = context.read<PlaylistContentNotifier>();
    final path = widget.song?.filePath;
    if (identical(library, _library) && path == _path) return;
    _release();
    _library = library;
    _path = path;
    _signal = path == null ? null : library.coverListenableForSongPath(path);
    if (path == null) return;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      _requested = true;
      library.requestSongCover(path);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  @override
  void didUpdateWidget(covariant _StatisticsCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bind();
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  Widget _image() {
    final cover = widget.song == null
        ? null
        : _library!.displayThumbnailForSong(widget.song!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(
        widget.kind == StatisticsRanking.artists ? 100 : 4,
      ),
      child: cover == null
          ? Icon(switch (widget.kind) {
              StatisticsRanking.songs => Icons.music_note,
              StatisticsRanking.artists => Icons.person,
              StatisticsRanking.albums => Icons.album,
            }, size: 20)
          : ArtworkImage(
              bytes: cover,
              size: ArtworkSize.thumbnail,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
            ),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 40,
    child: _signal == null
        ? _image()
        : AnimatedBuilder(animation: _signal!, builder: (_, _) => _image()),
  );
}
