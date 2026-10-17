import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/services/playback_navigation.dart';
import 'package:myune_music/services/library_root_playlist.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';

void main() {
  test(
    'an empty or root-only restored list still has an independent favorite target',
    () {
      final empty = ensureLibraryRoot([]);
      expect(empty.map((p) => p.name), ['总歌曲', '收藏']);
      final rootOnly = ensureLibraryRoot([empty.first]);
      expect(rootOnly.map((p) => p.name), ['总歌曲', '收藏']);
      expect(rootOnly.last.songFilePaths, isEmpty);
    },
  );
  test(
    'library migration keeps existing IDs, favorites and all hidden source paths',
    () {
      final favorites = Playlist(
        id: 'old',
        name: '收藏',
        isDefault: true,
        songFilePaths: ['a', 'hidden'],
      );
      final custom = Playlist(
        id: 'custom',
        name: '我的歌单',
        songFilePaths: ['b', 'a'],
      );
      final migrated = ensureLibraryRoot([favorites, custom]);
      expect(migrated.map((p) => p.id), [Playlist.libraryId, 'old', 'custom']);
      expect(migrated.first.songFilePaths, ['a', 'hidden', 'b']);
      expect(favorites.songFilePaths, ['a', 'hidden']);
      migrated.first.songFilePaths.add('new-import');
      expect(favorites.songFilePaths, isNot(contains('new-import')));
      favorites.songFilePaths.remove('a');
      expect(ensureLibraryRoot(migrated).first.songFilePaths, contains('a'));
      expect(
        ensureLibraryRoot(migrated).where((p) => p.isLibrary),
        hasLength(1),
      );
      final restored = migrated
          .map(
            (p) =>
                Playlist.fromJson(p.toJson())..songFilePaths = p.songFilePaths,
          )
          .toList();
      expect(
        ensureLibraryRoot(restored).first.songFilePaths,
        contains('new-import'),
      );
    },
  );

  test('skip filters combine threshold boundary and title scripts', () {
    Song song(String title) => Song(title: title, artist: '', filePath: title);
    const rules = PlaybackSkipRules(
      lowPlayCount: true,
      english: true,
      japanese: true,
    );
    expect(rules.minimumPlayCount, 10);
    expect(rules.allows(song('歌曲'), 9), isFalse);
    expect(rules.allows(song('歌曲'), 10), isTrue);
    expect(rules.allows(song('Earned It'), 20), isFalse);
    expect(rules.allows(song('愛はエネルギー'), 20), isFalse);
    expect(songTitleLanguage('中文 Love'), SongTitleLanguage.chinese);
    expect(songTitleLanguage('愛はEnergy'), SongTitleLanguage.japanese);
    expect(songTitleLanguage('Été'), SongTitleLanguage.english);
    expect(songTitleLanguage('123 🎶'), SongTitleLanguage.other);
    expect(rules.copyWith(chinese: true).allows(song('中文'), 20), isFalse);
  });

  test(
    'new mode repeats on completion but switches to random order manually in both directions',
    () {
      const order = [2, 0, 3, 1];
      int? choose({
        bool auto = false,
        bool previous = false,
        bool stop = false,
      }) => nextPlaybackIndex(
        count: 4,
        current: 0,
        mode: PlayMode.repeatShuffle,
        automatic: auto,
        previous: previous,
        shuffleOrder: order,
        stopAfterQueue: stop,
        allows: (_) => true,
      );
      expect(choose(auto: true), 0);
      expect(choose(), 3);
      expect(choose(previous: true), 2);
      expect(choose(auto: true, stop: true), isNull);
      expect(
        PlayMode.repeatOne.index,
        2,
        reason: 'existing persisted modes keep their index',
      );
    },
  );

  test(
    'forward, reverse, shuffled and automatic lookahead skip identical candidates with bounded work',
    () {
      for (final mode in PlayMode.values) {
        var checks = 0;
        final result = nextPlaybackIndex(
          count: 100,
          current: 0,
          mode: mode,
          automatic: false,
          allows: (_) {
            checks++;
            return false;
          },
        );
        expect(result, isNull);
        expect(checks, 100);
      }
      int? choose({
        bool reverse = false,
        bool automatic = false,
        bool stop = false,
      }) => nextPlaybackIndex(
        count: 5,
        current: 2,
        mode: PlayMode.sequence,
        automatic: automatic,
        previous: reverse,
        stopAfterQueue: stop,
        allows: (i) => i == 0,
      );
      expect(choose(), 0);
      expect(choose(reverse: true), 0);
      expect(choose(automatic: true), 0);
      expect(choose(automatic: true, stop: true), isNull);
      expect(
        nextPlaybackIndex(
          count: 0,
          current: -1,
          mode: PlayMode.shuffle,
          automatic: false,
          allows: (_) => true,
        ),
        isNull,
      );
      expect(
        nextPlaybackIndex(
          count: 1,
          current: 0,
          mode: PlayMode.repeatOne,
          automatic: true,
          allows: (_) => false,
        ),
        0,
        reason: 'looping the current track is not a song change',
      );
    },
  );
}
