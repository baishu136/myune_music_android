import 'package:uuid/uuid.dart';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

class Song {
  final String title;
  final String artist;
  final String album;
  final String filePath;
  final String normalizedPath; // 缓存归一化路径，避免热路径上重复调用 p.normalize
  final Uint8List? albumArt;
  final Duration? duration;
  final int? trackNumber;

  Song({
    required this.title,
    required this.artist,
    this.album = '未知专辑',
    required this.filePath,
    this.albumArt,
    this.duration,
    this.trackNumber,
  }) : normalizedPath = p.normalize(filePath);

  Map<String, dynamic> toJson() {
    return {'title': title, 'artist': artist, 'filePath': filePath};
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      title: json['title'],
      artist: json['artist'],
      filePath: json['filePath'],
    );
  }
}

// 歌单歌曲元数据缓存
class SongMetadataCacheEntry {
  // Bump this whenever metadata decoding changes. Older entries may contain
  // already-decoded mojibake and therefore cannot be repaired reliably from
  // their cached strings alone; they must be read again from the audio file.
  static const int currentDecoderVersion = 3;

  final String title;
  final String artist;
  final String album;
  final int? durationMs;
  final int modifiedMs;
  final int decoderVersion;

  const SongMetadataCacheEntry({
    required this.title,
    required this.artist,
    required this.album,
    required this.modifiedMs,
    this.durationMs,
    this.decoderVersion = currentDecoderVersion,
  });

  bool get usesCurrentDecoder => decoderVersion == currentDecoderVersion;

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'artist': artist,
      'album': album,
      'durationMs': durationMs,
      'modifiedMs': modifiedMs,
      'decoderVersion': decoderVersion,
    };
  }

  factory SongMetadataCacheEntry.fromJson(Map<String, dynamic> json) {
    return SongMetadataCacheEntry(
      title: json['title'] ?? '',
      artist: json['artist'] ?? '',
      album: json['album'] ?? '',
      durationMs: json['durationMs'],
      modifiedMs: json['modifiedMs'] ?? 0,
      // Cache files written before the decoder version was introduced are
      // deliberately treated as stale and rebuilt on the next library load.
      decoderVersion: json['decoderVersion'] ?? 0,
    );
  }
}

class Playlist {
  final String id;
  String name;
  final bool isDefault;
  List<String> songFilePaths;
  List<Song>? songs; // 直接在歌单对象中存储已解析的歌曲

  // 保存当前歌单播放歌曲的索引
  int? currentPlayingIndex;

  // 标识是否为文件夹播放列表
  bool isFolderBased;
  // 存储相关文件夹路径
  List<String> folderPaths;

  Playlist({
    String? id,
    required this.name,
    this.isDefault = false,
    List<String>? songFilePaths,
    this.currentPlayingIndex,
    this.songs,
    this.isFolderBased = false,
    List<String>? folderPaths,
  }) : id = id ?? const Uuid().v4(),
       songFilePaths = songFilePaths ?? [],
       folderPaths = folderPaths ?? [];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isDefault': isDefault,
      'currentPlayingIndex': currentPlayingIndex,
      'isFolderBased': isFolderBased,
      'folderPaths': folderPaths,
    };
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'],
      name: json['name'],
      isDefault: json['isDefault'] ?? false,
      currentPlayingIndex: json['currentPlayingIndex'],
      isFolderBased: json['isFolderBased'] ?? false,
      folderPaths: json['folderPaths'] != null
          ? List<String>.from(json['folderPaths'])
          : [],
    );
  }
}

class LyricLine {
  final Duration timestamp;
  final List<String> texts;

  final List<List<LyricToken>>? tokens;
  final bool isInterlude;
  final Duration? interludeDuration;

  LyricLine({
    required this.timestamp,
    required this.texts,
    this.tokens,
    this.isInterlude = false,
    this.interludeDuration,
  });

  bool get isKaraoke => tokens != null && tokens!.isNotEmpty;
}

class LyricToken {
  final String text;
  final Duration start;
  final Duration end;

  LyricToken({required this.text, required this.start, required this.end});
}

class SongDetails {
  final String? title;
  final String? artist;
  final String? album;
  final Duration? duration;
  final Uint8List? albumArt;
  final int? bitrate;
  final int? sampleRate;
  final String filePath;
  final DateTime? created;
  final DateTime? modified;
  final int? year;
  final String? genre;
  final String? albumArtist;

  SongDetails({
    this.title,
    this.artist,
    this.album,
    this.duration,
    this.albumArt,
    this.bitrate,
    this.sampleRate,
    required this.filePath,
    this.created,
    this.modified,
    this.year,
    this.genre,
    this.albumArtist,
  });
}

class PlaybackState {
  final String? playlistId;
  final int songIndex;

  PlaybackState({this.playlistId, required this.songIndex});

  Map<String, dynamic> toJson() {
    return {'playlistId': playlistId, 'songIndex': songIndex};
  }

  factory PlaybackState.fromJson(Map<String, dynamic> json) {
    return PlaybackState(
      playlistId: json['playlistId'],
      songIndex: json['songIndex'],
    );
  }
}
