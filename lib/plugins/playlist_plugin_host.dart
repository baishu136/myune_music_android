import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../page/playlist/playlist_content_notifier.dart';
import '../page/playlist/playlist_models.dart';
import 'plugin_controller.dart';

Map<String, dynamic> pluginSong(Song song) => {
  'id': sha256.convert(utf8.encode(song.normalizedPath)).toString(),
  'title': song.title,
  'artist': song.artist,
  'album': song.album,
  'durationMs': song.duration?.inMilliseconds,
};

class PlaylistPluginHost implements PluginHost {
  PlaylistPluginHost(this.notifier, this.plugins) {
    notifier.addListener(_changed);
    plugins.bindHost(this);
  }
  final PlaylistContentNotifier notifier;
  final PluginController plugins;
  final Map<String, String> _knownSongs = {};
  @override
  String? get songIdentity => notifier.currentSong?.normalizedPath;
  Map<String, dynamic> _song(Song song) {
    final data = pluginSong(song);
    _knownSongs[data['id'] as String] = song.normalizedPath;
    while (_knownSongs.length > 4096) {
      _knownSongs.remove(_knownSongs.keys.first);
    }
    return data;
  }

  @override
  Map<String, dynamic> snapshot() => {
    'song': notifier.currentSong == null ? null : _song(notifier.currentSong!),
    'playing': notifier.isPlaying,
    'positionMs': notifier.currentPosition.inMilliseconds,
    'durationMs': notifier.totalDuration.inMilliseconds,
  };
  void _changed() =>
      plugins.playbackChanged((songIdentity, notifier.isPlaying));
  @override
  Future<Object?> call(String method, Map<String, dynamic> args) async {
    if (method == 'library.query') {
      final rawOffset = args['offset'] ?? 0, rawLimit = args['limit'] ?? 50;
      if (rawOffset is! int ||
          rawOffset < 0 ||
          rawLimit is! int ||
          rawLimit < 1 ||
          rawLimit > 100) {
        throw StateError('查询分页无效');
      }
      final q = args['query'] ?? '';
      if (q is! String || q.length > 200) throw StateError('查询词无效');
      final songs = notifier.allSongs, result = <Map<String, dynamic>>[];
      var offset = rawOffset, scanned = 0;
      final needle = q.toLowerCase();
      while (offset < songs.length &&
          result.length < rawLimit &&
          scanned++ < 5000) {
        final song = songs[offset++];
        if (needle.isEmpty ||
            '${song.title} ${song.artist} ${song.album}'.toLowerCase().contains(
              needle,
            )) {
          result.add(_song(song));
        }
      }
      return {
        'songs': result,
        'total': songs.length,
        'nextOffset': offset < songs.length ? offset : null,
      };
    }
    if (method == 'playback.command') {
      switch (args['command']) {
        case 'play':
          await notifier.play();
        case 'pause':
          await notifier.pause();
        case 'next':
          await notifier.playNext();
        case 'previous':
          await notifier.playPrevious();
        case 'seek':
          final ms = args['positionMs'];
          if (ms is! int ||
              ms < 0 ||
              ms > notifier.totalDuration.inMilliseconds) {
            throw StateError('播放位置无效');
          }
          final position = Duration(milliseconds: ms);
          notifier.signalLyricSeekIntent();
          await notifier.mediaPlayer.seek(position);
          notifier.signalLyricSeek(position);
          notifier.updateLyricLine(position);
        default:
          throw StateError('不支持的播放命令');
      }
      return true;
    }
    if (method == 'queue.append' || method == 'queue.play') {
      final ids = args['ids'];
      if (ids is! List ||
          ids.isEmpty ||
          ids.length > 100 ||
          ids.any((id) => id is! String || !_knownSongs.containsKey(id))) {
        throw StateError('歌曲清单无效，请重新查询曲库');
      }
      final byPath = {for (final s in notifier.allSongs) s.normalizedPath: s};
      final selected = <Song>[];
      for (final id in ids) {
        final song = byPath[_knownSongs[id]];
        if (song == null) throw StateError('歌曲已不在曲库中');
        if (!selected.contains(song)) selected.add(song);
      }
      if (method == 'queue.play') {
        await notifier.playFromDynamicList(selected, 0);
      } else {
        await notifier.addSongsToPlayingQueue(selected);
      }
      return {'count': selected.length};
    }
    throw StateError('不支持的宿主操作');
  }

  void dispose() {
    notifier.removeListener(_changed);
    plugins.unbindHost(this);
  }
}
