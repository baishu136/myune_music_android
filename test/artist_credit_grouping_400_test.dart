import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/services/library_preparation_worker.dart';
import 'package:myune_music/services/artist_names.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'legacy defaults include slash collaborations in the solo artist group',
    () async {
      SharedPreferences.setMockInitialValues({
        'artistSeparators': [';', '、', '；', '，', ','],
      });
      final settings = SettingsProvider();
      addTearDown(settings.dispose);
      await settings.initializationFuture;
      final result = prepareLibraryMetadata(
        [
          ['Solo', 'The Weeknd', 'One'],
          ['Collaboration', 'Future/the WEEKND', 'Two'],
          ['Different name', 'The Weekend', 'Three'],
        ],
        settings.artistSeparators,
        includeSearchIndex: false,
      );
      expect(result.artists['The Weeknd'], [0, 1]);
      expect(result.artists['Future'], [1]);
      expect(result.artists['The Weekend'], [2]);
    },
  );

  test(
    'custom multi-character delimiters are literal and repeated credits do not duplicate songs',
    () {
      final result = prepareLibraryMetadata(
        [
          ['Collaboration', 'Future feat. The Weeknd feat. FUTURE', 'One'],
          ['Solo', ' The   Weeknd ', 'Two'],
        ],
        [' feat. '],
        includeSearchIndex: false,
      );
      expect(result.artists, {
        'Future': [0],
        'The Weeknd': [0, 1],
      });
    },
  );

  test(
    'new defaults include both slash forms and an explicit removal survives restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      addTearDown(settings.dispose);
      await settings.initializationFuture;
      expect(settings.artistSeparators, containsAll(['/', '／']));
      await settings.setArtistSeparators(legacyArtistSeparators);
      final restored = SettingsProvider();
      addTearDown(restored.dispose);
      await restored.initializationFuture;
      expect(restored.artistSeparators, legacyArtistSeparators);
    },
  );

  test('custom and deliberately empty separator lists are preserved', () async {
    for (final separators in [
      <String>[' feat. ', '&'],
      <String>[],
    ]) {
      SharedPreferences.setMockInitialValues({'artistSeparators': separators});
      final settings = SettingsProvider();
      addTearDown(settings.dispose);
      await settings.initializationFuture;
      expect(settings.artistSeparators, separators);
    }
  });

  test(
    'parser uses longest literal delimiters, keeps distinct names and deduplicates case variants',
    () {
      final parser = ArtistNameParser([
        '|',
        '||',
        ' feat. ',
        '/',
        '／',
        ' ',
        '',
      ]);
      expect(parser.split(' Future||THE   Weeknd/FUTURE／ feat. '), [
        'Future',
        'THE Weeknd',
      ]);
      expect(parser.split('AC DC'), ['AC DC']);
      expect(parser.split(' / ／ '), ['未知歌手']);
      expect(artistMatchKey(' The\tWEEKND '), artistMatchKey('the weeknd'));
      expect(
        artistMatchKey('The Weeknd'),
        isNot(artistMatchKey('The Weekend')),
      );
    },
  );

  test(
    'foreground grouping and both worker phases publish identical artist lists',
    () async {
      final rows = [
        ['Solo', 'The Weeknd', 'One'],
        ['Shared', 'Future/the WEEKND/FUTURE', 'Two'],
        ['Wide', 'Future／ THE   WEEKND', 'Three'],
        ['Unknown', ' ', 'Four'],
      ];
      final groups = groupByArtist<int>(
        Iterable<int>.generate(rows.length),
        (index) => rows[index][1],
        ArtistNameParser(defaultArtistSeparators),
      );
      expect(groups, {
        'The Weeknd': [0, 1, 2],
        'Future': [1, 2],
        '未知歌手': [3],
      });
      final worker = LibraryPreparationWorker();
      addTearDown(worker.dispose);
      for (final full in [false, true]) {
        final result = await worker.prepare(
          rows,
          defaultArtistSeparators,
          includeSearchIndex: full,
        );
        expect(result.artists, groups);
        expect(result.sortKeys.keys, containsAll(groups.keys));
      }
    },
  );
}
