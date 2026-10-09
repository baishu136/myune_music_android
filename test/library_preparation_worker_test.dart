import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/services/library_preparation_worker.dart';
import 'package:myune_music/services/search_service.dart';
import 'package:myune_music/services/song_group_presentation.dart';

void main() {
  test('group publication does not require per-song search indices', () async {
    final worker = LibraryPreparationWorker();
    addTearDown(worker.dispose);
    final rows = [
      ['光辉岁月', 'Beyond/黄家驹', '命运派对'],
    ];
    final groups = await worker.prepare(rows, ['/'], includeSearchIndex: false);
    expect(groups.artists, {
      'Beyond': [0],
      '黄家驹': [0],
    });
    expect(groups.albums, {
      '命运派对': [0],
    });
    expect(groups.sortKeys['黄家驹'], 'huangjiaju');
    expect(groups.sortKeys.containsKey('光辉岁月'), isFalse);
    expect(groups.pinyin, isEmpty);
    expect(groups.initials, isEmpty);
    expect(groups.mixedKeys, isEmpty);
    final indexed = await worker.prepare(rows, ['/']);
    expect(indexed.pinyin.single.first, 'guanghuisuiyue');
    expect(indexed.artists, groups.artists);
  });
  test(
    'worker groups multi-artist songs and exports reusable search/sort results',
    () async {
      final worker = LibraryPreparationWorker();
      addTearDown(worker.dispose);
      final rows = [
        ['光辉岁月', 'Beyond/黄家驹', '命运派对'],
        ['打上花火', 'DAOKO', 'THANK YOU BLUE'],
        ['空白', '', ''],
      ];
      final result = await worker.prepare(rows, ['/']);
      expect(result.sortKeys['光辉岁月'], 'guanghuisuiyue');
      expect(result.mixedKeys['光辉岁月'], 'guanghuisuiyue');
      expect(result.artists['黄家驹'], [0]);
      expect(result.artists['未知歌手'], [2]);
      expect(result.albums['命运派对'], [0]);
      final songs = [
        for (var i = 0; i < rows.length; i++)
          Song(
            title: rows[i][0],
            artist: rows[i][1],
            album: rows[i][2],
            filePath: '/$i.mp3',
          ),
      ];
      final prepared = SearchService()
        ..installPrepared(songs, result.pinyin, result.initials);
      final reference = SearchService()..rebuild(songs);
      for (final query in [
        'ghsy',
        'guanghuisuiyue',
        'hjj',
        'daoko',
        'thank blue',
        '打花',
      ]) {
        expect(
          prepared.search(query, songs),
          reference.search(query, songs),
          reason: query,
        );
      }
      SongGroupPresentation.installSortKeys(result.sortKeys);
      expect(
        SongGroupPresentation.alphabeticSortKey('黄家驹'),
        result.sortKeys['黄家驹'],
      );
      final updated = await worker.prepare([
        ['新歌', '甲/乙', '新专辑'],
      ], []);
      expect(updated.artists.keys, ['甲/乙']);
      expect(updated.albums.keys, ['新专辑']);
    },
  );

  test('worker disposal rejects further work', () async {
    final worker = LibraryPreparationWorker();
    worker.dispose();
    await expectLater(worker.prepare([], []), throwsStateError);
  });

  test(
    'disposing during worker startup completes the pending request',
    () async {
      for (var attempt = 0; attempt < 8; attempt++) {
        final worker = LibraryPreparationWorker();
        final pending = expectLater(
          worker.prepare([], []).timeout(const Duration(seconds: 2)),
          throwsStateError,
        );
        worker.dispose();
        await pending;
      }
    },
  );

  test(
    'text-only early search becomes full pinyin search after publication',
    () async {
      final worker = LibraryPreparationWorker();
      addTearDown(worker.dispose);
      final song = Song(
        title: '光辉岁月',
        artist: 'Beyond',
        album: '命运派对',
        filePath: '/early.mp3',
      );
      final search = SearchService(allowColdPinyin: false);
      expect(search.search('光辉', [song]), [song]);
      expect(search.search('ghsy', [song]), isEmpty);
      final result = await worker.prepare(
        [
          [song.title, song.artist, song.album],
        ],
        [],
        labels: ['中文歌单'],
      );
      search.installPrepared([song], result.pinyin, result.initials);
      expect(search.search('ghsy', [song]), [song]);
      expect(result.sortKeys['中文歌单'], 'zhongwengedan');
    },
  );
}
