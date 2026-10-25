import 'dart:collection';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/statistics_page/statistics_manager.dart';
import 'package:myune_music/page/statistics_page/statistics_models.dart';
import 'package:myune_music/services/lyric_line_lookup.dart';
import 'package:myune_music/widgets/karaoke_sweep_timeline.dart';

class _ReadCounter extends ListBase<LyricLine> {
  _ReadCounter(this.source);
  final List<LyricLine> source;
  int reads = 0;
  @override
  int get length => source.length;
  @override
  set length(int value) => throw UnsupportedError('read only');
  @override
  LyricLine operator [](int index) {
    reads++;
    return source[index];
  }

  @override
  void operator []=(int index, LyricLine value) =>
      throw UnsupportedError('read only');
}

void main() {
  test(
    'lyric interval reuse is bounded and random seeks match the timestamp oracle',
    () {
      final source = List.generate(
        4096,
        (i) => LyricLine(
          timestamp: Duration(milliseconds: (i ~/ 3) * 1000),
          texts: ['$i'],
        ),
      );
      final lines = _ReadCounter(source);
      for (var i = 0; i < 100; i++) {
        expect(
          lyricLineIndexAt(
            lines,
            Duration(milliseconds: 100000 + i),
            hint: 302,
          ),
          302,
        );
      }
      expect(lines.reads, 200);
      final random = Random(427);
      var hint = -1;
      for (var i = 0; i < 700; i++) {
        final position = Duration(milliseconds: random.nextInt(1500000) - 1000);
        var expected = -1;
        for (var j = 0; j < source.length; j++) {
          if (source[j].timestamp > position) break;
          expected = j;
        }
        final before = lines.reads;
        hint = lyricLineIndexAt(lines, position, hint: hint);
        expect(hint, expected);
        expect(lines.reads - before, lessThanOrEqualTo(18));
      }
      expect(lyricLineIndexAt([], Duration.zero), -1);
      expect(
        lyricLineIndexAt(source, const Duration(days: 1), hint: 99999),
        4095,
      );
    },
  );

  test(
    'count snapshots survive duration updates and invalidate on count/import/reset',
    () {
      final manager = StatisticsManager();
      final data = manager.statisticsData;
      data.updateStats({});
      final initial = manager.normalizedPlayCounts;
      final revision = manager.songRevision;
      data.addPlaybackDuration(const Duration(seconds: 20));
      expect(manager.songRevision, revision);
      expect(manager.normalizedPlayCounts, same(initial));
      data.recordSongPlayed(
        SongPlayStat(title: 'A', artist: 'B', album: 'C', path: 'MUSIC/A.mp3'),
      );
      final counted = manager.normalizedPlayCounts;
      expect(counted['music/a.mp3'], 1);
      expect(manager.getSongStatByPath('MUSIC/A.mp3')?.playCount, 1);
      expect(counted, isNot(same(initial)));
      expect(() => counted['x'] = 2, throwsUnsupportedError);
      data.updateStats({
        'new.mp3': SongPlayStat(
          title: '',
          artist: '',
          album: '',
          path: 'new.mp3',
          playCount: 8,
        ),
      });
      expect(manager.normalizedPlayCounts, {'new.mp3': 8});
      data.clearStats();
      expect(manager.normalizedPlayCounts, isEmpty);
      expect(manager.getSongStatByPath('MUSIC/A.mp3'), isNull);
    },
  );

  test(
    'cached word segment stays identical after pauses, reverse seeks and boundaries',
    () {
      final segments = [
        for (var i = 0; i < 100; i++)
          (startUs: i * 200000, endUs: (i + 1) * 200000, advance: 10.0 + i % 7),
      ];
      final cached = KaraokeSweepTimeline(segments);
      final random = Random(427);
      final times = <int>[
        -1,
        0,
        1,
        199999,
        200000,
        200001,
        20000000,
        20000001,
        for (var i = 0; i < 400; i++) random.nextInt(21000000),
      ];
      for (final time in times) {
        final expected = KaraokeSweepTimeline(segments).phaseAt(time);
        expect(cached.phaseAt(time), expected);
        expect(cached.phaseAt(time), expected);
      }
    },
  );
}
