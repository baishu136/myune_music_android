import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart'
    as metadata_reader;
import 'package:charset/charset.dart' show gbk;

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
    final riffInfo = _readRiffInfoTags(File(path));
    final cover = options.needCover
        ? _selectEmbeddedCover(metadata.pictures) ??
              _readRiffId3Cover(File(path))
        : null;

    return rust_audio.AudioInfo(
      title: riffInfo?.title ?? _repairLegacyMetadataText(metadata.title),
      artist: riffInfo?.artist ?? _repairLegacyMetadataText(metadata.artist),
      album: riffInfo?.album ?? _repairLegacyMetadataText(metadata.album),
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

Uint8List? _selectEmbeddedCover(List<metadata_reader.Picture> pictures) {
  if (pictures.isEmpty) return null;
  return pictures
      .firstWhere(
        (picture) =>
            picture.pictureType == metadata_reader.PictureType.coverFront,
        orElse: () => pictures.first,
      )
      .bytes;
}

final class _RiffInfoTags {
  const _RiffInfoTags({this.title, this.artist, this.album});

  final String? title;
  final String? artist;
  final String? album;

  bool get isEmpty => title == null && artist == null && album == null;
}

/// Reads the raw LIST/INFO strings from a RIFF/WAVE file.
///
/// A large amount of Chinese WAV software writes these fields as GBK without
/// an encoding marker. Metadata libraries commonly interpret those bytes as
/// Latin-1, which produces strings such as `ÍòÄÜÇàÄêÂÃµê`. Reading the raw
/// bytes here lets us try strict UTF-8 first and then the de-facto GBK format.
_RiffInfoTags? _readRiffInfoTags(File file) {
  RandomAccessFile? reader;
  try {
    reader = file.openSync();
    final fileLength = reader.lengthSync();
    if (fileLength < 12) return null;

    final header = reader.readSync(12);
    if (_fourCc(header, 0) != 'RIFF' || _fourCc(header, 8) != 'WAVE') {
      return null;
    }

    String? title;
    String? artist;
    String? album;
    var offset = 12;
    while (offset + 8 <= fileLength) {
      reader.setPositionSync(offset);
      final chunkHeader = reader.readSync(8);
      if (chunkHeader.length < 8) break;

      final chunkId = _fourCc(chunkHeader, 0);
      final chunkSize = ByteData.sublistView(
        chunkHeader,
        4,
        8,
      ).getUint32(0, Endian.little);
      final dataOffset = offset + 8;
      final chunkEnd = dataOffset + chunkSize;
      if (chunkEnd > fileLength) break;

      if (chunkId == 'LIST' && chunkSize >= 4) {
        reader.setPositionSync(dataOffset);
        final listType = reader.readSync(4);
        if (listType.length == 4 && _fourCc(listType, 0) == 'INFO') {
          var infoOffset = dataOffset + 4;
          while (infoOffset + 8 <= chunkEnd) {
            reader.setPositionSync(infoOffset);
            final infoHeader = reader.readSync(8);
            if (infoHeader.length < 8) break;

            final infoId = _fourCc(infoHeader, 0);
            final infoSize = ByteData.sublistView(
              infoHeader,
              4,
              8,
            ).getUint32(0, Endian.little);
            final valueOffset = infoOffset + 8;
            final valueEnd = valueOffset + infoSize;
            if (valueEnd > chunkEnd) break;

            if ((infoId == 'INAM' || infoId == 'IART' || infoId == 'IPRD') &&
                infoSize <= 64 * 1024) {
              reader.setPositionSync(valueOffset);
              final value = _decodeRiffInfoValue(reader.readSync(infoSize));
              switch (infoId) {
                case 'INAM':
                  title ??= value;
                  break;
                case 'IART':
                  artist ??= value;
                  break;
                case 'IPRD':
                  album ??= value;
                  break;
              }
            }

            final nextInfoOffset = valueEnd + (infoSize.isOdd ? 1 : 0);
            if (nextInfoOffset <= infoOffset || nextInfoOffset > chunkEnd) {
              break;
            }
            infoOffset = nextInfoOffset;
          }
        }
      }

      final nextOffset = chunkEnd + (chunkSize.isOdd ? 1 : 0);
      if (nextOffset <= offset || nextOffset > fileLength) break;
      offset = nextOffset;
    }

    final tags = _RiffInfoTags(title: title, artist: artist, album: album);
    return tags.isEmpty ? null : tags;
  } catch (_) {
    return null;
  } finally {
    reader?.closeSync();
  }
}

String? _decodeRiffInfoValue(Uint8List rawValue) {
  var end = rawValue.length;
  while (end > 0 && rawValue[end - 1] == 0) {
    end--;
  }
  if (end == 0) return null;
  final bytes = rawValue.sublist(0, end);

  try {
    final value = utf8.decode(bytes, allowMalformed: false).trim();
    if (value.isNotEmpty) return value;
  } on FormatException {
    // Chinese RIFF/INFO writers commonly use GBK instead of UTF-8.
  }

  try {
    final value = gbk.decode(bytes).replaceAll('\u0000', '').trim();
    if (value.isNotEmpty) return value;
  } catch (_) {
    final value = latin1.decode(bytes).replaceAll('\u0000', '').trim();
    return value.isEmpty ? null : value;
  }
  return null;
}

/// Repairs metadata bytes that a dependency has already decoded as Latin-1.
/// This is intentionally conservative so legitimate accented names stay intact.
String? _repairLegacyMetadataText(String? value) {
  if (value == null) return null;
  final cleaned = value.replaceAll('\u0000', '').trim();
  if (cleaned.isEmpty) return null;
  if (cleaned.codeUnits.any((unit) => unit > 0xff)) return cleaned;

  final bytes = Uint8List.fromList(cleaned.codeUnits);
  try {
    final decoded = utf8.decode(bytes, allowMalformed: false).trim();
    if (decoded.isNotEmpty && decoded != cleaned) return decoded;
  } on FormatException {
    // Try the common legacy Chinese encoding below.
  }

  if (!_containsCjk(cleaned)) {
    try {
      final decoded = gbk.decode(bytes).trim();
      if (_containsCjk(decoded)) return decoded;
    } catch (_) {
      // Keep the original text when the byte sequence is not valid GBK.
    }
  }
  return cleaned;
}

bool _containsCjk(String value) => value.runes.any(
  (rune) =>
      (rune >= 0x3400 && rune <= 0x4dbf) || (rune >= 0x4e00 && rune <= 0x9fff),
);

/// Reads APIC artwork from an ID3 chunk embedded in a RIFF/WAVE container.
///
/// `audio_metadata_reader` 1.7.1 detects RIFF ID3 tags, but its high-level
/// reader does not forward `getImage` to the RIFF parser. Keep this bounded
/// fallback until the dependency exposes WAV artwork through `pictures`.
Uint8List? _readRiffId3Cover(File file) {
  RandomAccessFile? reader;
  try {
    reader = file.openSync();
    final fileLength = reader.lengthSync();
    if (fileLength < 12) return null;

    final header = reader.readSync(12);
    if (_fourCc(header, 0) != 'RIFF' || _fourCc(header, 8) != 'WAVE') {
      return null;
    }

    var offset = 12;
    while (offset + 8 <= fileLength) {
      reader.setPositionSync(offset);
      final chunkHeader = reader.readSync(8);
      if (chunkHeader.length < 8) return null;

      final chunkId = _fourCc(chunkHeader, 0);
      final chunkSize = ByteData.sublistView(
        chunkHeader,
        4,
        8,
      ).getUint32(0, Endian.little);
      final dataOffset = offset + 8;
      final chunkEnd = dataOffset + chunkSize;
      if (chunkEnd > fileLength) return null;

      if (chunkId == 'ID3 ' || chunkId == 'id3 ' || chunkId == 'ID32') {
        final cover = _readValidatedId3Cover(reader, dataOffset, chunkSize);
        if (cover != null && cover.isNotEmpty) return cover;
      }

      final nextOffset = chunkEnd + (chunkSize.isOdd ? 1 : 0);
      if (nextOffset <= offset || nextOffset > fileLength) return null;
      offset = nextOffset;
    }
  } catch (_) {
    return null;
  } finally {
    reader?.closeSync();
  }
  return null;
}

Uint8List? _readValidatedId3Cover(
  RandomAccessFile reader,
  int dataOffset,
  int chunkSize,
) {
  if (chunkSize < 10) return null;

  reader.setPositionSync(dataOffset);
  final header = reader.readSync(10);
  if (header.length < 10 || _fourCc(header, 0).substring(0, 3) != 'ID3') {
    return null;
  }

  final tagSize =
      ((header[6] & 0x7f) << 21) |
      ((header[7] & 0x7f) << 14) |
      ((header[8] & 0x7f) << 7) |
      (header[9] & 0x7f);
  final hasFooter = (header[5] & 0x10) != 0;
  final totalTagSize = 10 + tagSize + (hasFooter ? 10 : 0);
  if (totalTagSize > chunkSize) return null;

  reader.setPositionSync(dataOffset);
  final id3 = metadata_reader.ID3v2Parser(fetchImage: true).parse(reader);
  return _selectEmbeddedCover(id3.pictures);
}

String _fourCc(Uint8List bytes, int offset) {
  return latin1.decode(bytes.sublist(offset, offset + 4));
}

Future<void> writeReplayGainTags({
  required String path,
  required double gainDb,
  required double peak,
}) {
  return rust_audio.writeReplayGainTags(path: path, gainDb: gainDb, peak: peak);
}
