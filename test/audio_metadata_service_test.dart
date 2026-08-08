import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/services/audio_metadata_service.dart';

void main() {
  test(
    'pure Dart metadata reader returns embedded cover and common tags',
    () async {
      final result = await readAudioInfoWithDart(
        path: 'test/fixtures/track-with-cover.mp3',
        options: const AudioInfoOptions(
          needCover: true,
          needLyrics: true,
          needAudioProps: true,
          needExtraTags: true,
          needTrackNumber: true,
        ),
      );

      expect(result.title, 'Title');
      expect(result.artist, 'Artist');
      expect(result.album, 'Album');
      expect(result.trackNumber, 1);
      expect(result.cover, isNotNull);
      expect(
        result.cover,
        File('test/fixtures/expected-cover.png').readAsBytesSync(),
      );
    },
  );

  test('pure Dart metadata reader returns cover embedded in WAV ID3', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'myune-wav-cover-',
    );
    final wavFile = File('${tempDirectory.path}/track-with-cover.wav');
    final expectedCover = File(
      'test/fixtures/expected-cover.png',
    ).readAsBytesSync();

    try {
      wavFile.writeAsBytesSync(_wavWithId3Cover(expectedCover));

      final result = await readAudioInfoWithDart(
        path: wavFile.path,
        options: const AudioInfoOptions(
          needCover: true,
          needLyrics: false,
          needAudioProps: false,
          needExtraTags: false,
          needTrackNumber: false,
        ),
      );

      expect(result.cover, expectedCover);
    } finally {
      await tempDirectory.delete(recursive: true);
    }
  });
}

Uint8List _wavWithId3Cover(Uint8List cover) {
  final apicPayload = BytesBuilder(copy: false)
    ..addByte(0)
    ..add('image/png'.codeUnits)
    ..addByte(0)
    ..addByte(3)
    ..addByte(0)
    ..add(cover);
  final apicBytes = apicPayload.takeBytes();

  final frame = BytesBuilder(copy: false)
    ..add('APIC'.codeUnits)
    ..add(_uint32(apicBytes.length, Endian.big))
    ..add([0, 0])
    ..add(apicBytes);
  final frameBytes = frame.takeBytes();

  final id3 = BytesBuilder(copy: false)
    ..add('ID3'.codeUnits)
    ..add([3, 0, 0])
    ..add(_syncSafe(frameBytes.length))
    ..add(frameBytes);

  final fmt = BytesBuilder(copy: false)
    ..add(_uint16(1))
    ..add(_uint16(1))
    ..add(_uint32(8000))
    ..add(_uint32(16000))
    ..add(_uint16(2))
    ..add(_uint16(16));
  final pcm = Uint8List(160);

  final chunks = BytesBuilder(copy: false)
    ..add(_riffChunk('fmt ', fmt.takeBytes()))
    ..add(_riffChunk('data', pcm))
    ..add(_riffChunk('ID3 ', id3.takeBytes()));
  final chunkBytes = chunks.takeBytes();

  return (BytesBuilder(copy: false)
        ..add('RIFF'.codeUnits)
        ..add(_uint32(4 + chunkBytes.length))
        ..add('WAVE'.codeUnits)
        ..add(chunkBytes))
      .takeBytes();
}

Uint8List _riffChunk(String id, Uint8List payload) {
  final chunk = BytesBuilder(copy: false)
    ..add(id.codeUnits)
    ..add(_uint32(payload.length))
    ..add(payload);
  if (payload.length.isOdd) chunk.addByte(0);
  return chunk.takeBytes();
}

Uint8List _uint16(int value) {
  final data = ByteData(2)..setUint16(0, value, Endian.little);
  return data.buffer.asUint8List();
}

Uint8List _uint32(int value, [Endian endian = Endian.little]) {
  final data = ByteData(4)..setUint32(0, value, endian);
  return data.buffer.asUint8List();
}

Uint8List _syncSafe(int value) {
  return Uint8List.fromList([
    (value >> 21) & 0x7f,
    (value >> 14) & 0x7f,
    (value >> 7) & 0x7f,
    value & 0x7f,
  ]);
}
