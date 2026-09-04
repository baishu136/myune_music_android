import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/statistics_page/statistics_models.dart';

void main() {
  test('cumulative playback duration survives statistics serialization', () {
    final data = StatisticsData()
      ..recordSongPlayed(
        SongPlayStat(
          title: 'Song',
          artist: 'Artist',
          album: 'Album',
          path: '/music/song.flac',
        ),
      )
      ..addPlaybackDuration(const Duration(hours: 3, minutes: 12, seconds: 8));

    final restored = StatisticsData.fromJson(data.toJson());

    expect(
      restored.totalPlaybackDuration,
      const Duration(hours: 3, minutes: 12, seconds: 8),
    );
    expect(restored.totalPlays, 1);
  });

  test('legacy statistics without playback duration migrate to zero', () {
    final restored = StatisticsData.fromJson('{"songs":[]}');
    expect(restored.totalPlaybackDuration, Duration.zero);
  });
}
