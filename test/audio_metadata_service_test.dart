import 'dart:io';

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
}
