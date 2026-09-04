import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/statistics_page/statistics_models.dart';
import 'package:myune_music/services/song_group_presentation.dart';

void main() {
  Song song(String title, String path) =>
      Song(title: title, artist: '歌手', album: '专辑', filePath: path);

  test('group songs default to descending play count with stable fallback', () {
    final first = song('B', r'C:\Music\first.mp3');
    final second = song('A', r'C:\Music\second.mp3');
    final neverPlayed = song('C', r'C:\Music\third.mp3');
    final counts = SongGroupPresentation.normalizedPlayCounts({
      r'c:/music/first.mp3': SongPlayStat(
        title: 'B',
        artist: '歌手',
        album: '专辑',
        path: r'c:/music/first.mp3',
        playCount: 3,
      ),
      r'C:\MUSIC\SECOND.MP3': SongPlayStat(
        title: 'A',
        artist: '歌手',
        album: '专辑',
        path: r'C:\MUSIC\SECOND.MP3',
        playCount: 8,
      ),
    });

    final sorted = SongGroupPresentation.sortByPlayCount([
      first,
      neverPlayed,
      second,
    ], counts);

    expect(sorted, [second, first, neverPlayed]);
    expect(
      SongGroupPresentation.representativeSong(sorted, counts),
      same(second),
    );
    expect(
      SongGroupPresentation.representativeSong([
        neverPlayed,
        first,
        second,
      ], counts),
      same(second),
    );
  });

  test('group names use pinyin initials and keep symbols in hash section', () {
    final grouped = SongGroupPresentation.groupByInitial<String>([
      '周杰伦',
      'Aimer',
      '9m88',
      '@Live',
      '草东没有派对',
      '坂本龍一',
    ], (value) => value);

    expect(grouped.keys, ['#', 'A', 'B', 'C', 'Z']);
    expect(grouped['#'], ['9m88', '@Live']);
    expect(grouped['A'], ['Aimer']);
    expect(grouped['B'], ['坂本龍一']);
    expect(grouped['C'], ['草东没有派对']);
    expect(grouped['Z'], ['周杰伦']);
  });

  test('pinned entries are removed from the regular collection', () {
    final separated = SongGroupPresentation.separatePinned([
      'A',
      'B',
      'C',
      'D',
    ], (value) => value == 'B' || value == 'D');

    expect(separated.pinned, ['B', 'D']);
    expect(separated.regular, ['A', 'C']);
    expect({...separated.pinned, ...separated.regular}.length, 4);
  });
}
