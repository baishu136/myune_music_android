import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart'
    as metadata_reader;

import '../src/rust/api/audio_info.dart' as rust_audio;

export '../src/rust/api/audio_info.dart' show AudioInfo, AudioInfoOptions;

/// Uses the existing Rust reader on desktop and a pure Dart reader on Android,
/// where the Rust metadata library is not included in the APK.
Future<rust_audio.AudioInfo> readAudioInfo({
  required String path,
  required rust_audio.AudioInfoOptions options,
}) async {
  if (!Platform.isAndroid) {
    return rust_audio.readAudioInfo(path: path, options: options);
  }

  return readAudioInfoWithDart(path: path, options: options);
}

/// Pure Dart metadata path used by Android and covered independently in tests.
Future<rust_audio.AudioInfo> readAudioInfoWithDart({
  required String path,
  required rust_audio.AudioInfoOptions options,
}) {
  return Isolate.run(() {
    final metadata = metadata_reader.readMetadata(
      File(path),
      getImage: options.needCover,
    );
    final cover = options.needCover && metadata.pictures.isNotEmpty
        ? metadata.pictures.first.bytes
        : null;

    return rust_audio.AudioInfo(
      title: metadata.title,
      artist: metadata.artist,
      album: metadata.album,
      cover: cover,
      lyrics: options.needLyrics ? metadata.lyrics : null,
      durationMs: options.needAudioProps && metadata.duration != null
          ? BigInt.from(metadata.duration!.inMilliseconds)
          : null,
      bitrate: options.needAudioProps ? metadata.bitrate : null,
      sampleRate: options.needAudioProps ? metadata.sampleRate : null,
      year: options.needExtraTags ? metadata.year?.year : null,
      genre: options.needExtraTags && metadata.genres.isNotEmpty
          ? metadata.genres.first
          : null,
      trackNumber: options.needTrackNumber ? metadata.trackNumber : null,
    );
  });
}

Future<void> writeReplayGainTags({
  required String path,
  required double gainDb,
  required double peak,
}) {
  return rust_audio.writeReplayGainTags(path: path, gainDb: gainDb, peak: peak);
}
