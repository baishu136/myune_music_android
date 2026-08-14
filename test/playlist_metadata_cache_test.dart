import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';

void main() {
  group('SongMetadataCacheEntry decoder migration', () {
    test('legacy cache entries are treated as stale', () {
      final entry = SongMetadataCacheEntry.fromJson({
        'title': 'ÎÚÔÆµäµ±¼Ç',
        'artist': 'ÍòÄÜÇàÄêÂÃµê',
        'album': 'µ¥Çú',
        'modifiedMs': 123,
      });

      expect(entry.usesCurrentDecoder, isFalse);
    });

    test('new cache entries preserve the current decoder version', () {
      const original = SongMetadataCacheEntry(
        title: '乌云典当记',
        artist: '万能青年旅店',
        album: '单曲',
        durationMs: 480000,
        modifiedMs: 456,
      );

      final restored = SongMetadataCacheEntry.fromJson(original.toJson());

      expect(restored.usesCurrentDecoder, isTrue);
      expect(restored.title, '乌云典当记');
      expect(restored.artist, '万能青年旅店');
      expect(restored.album, '单曲');
    });
  });
}
