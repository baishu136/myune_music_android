import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/sort_dialog.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/services/song_sorting.dart';

void main() {
  for (final descending in [false, true]) {
    test(
      'numeric tracks, missing tags and ties: descending=$descending',
      () async {
        final tracks = <String, int?>{
          'two': 2,
          'ten': 10,
          'zero': 0,
          'none': null,
          'one': 1,
          'two-again': 2,
          'large': 12000,
          'negative': -1,
        };
        final source = tracks.keys.toList();
        final result = await sortSongPathsByTrackNumber(
          paths: source,
          readTrackNumber: (path) async => tracks[path],
          descending: descending,
        );
        expect(result, [
          if (descending) ...[
            'large',
            'ten',
            'two',
            'two-again',
            'one',
          ] else ...[
            'one',
            'two',
            'two-again',
            'ten',
            'large',
          ],
          'zero',
          'none',
          'negative',
        ]);
        expect(source, tracks.keys.toList());
      },
    );
  }
  test(
    'saved group order tolerates additions, removals and repeated paths',
    () {
      Song song(String path) => Song(title: path, artist: 'A', filePath: path);
      final source = [song('new'), song('a'), song('b')];
      expect(
        restoreSongCollectionOrder(source, [
          'missing',
          'b',
          'b',
          'a',
        ]).map((s) => s.filePath),
        ['b', 'a', 'new'],
      );
      expect(source.map((s) => s.filePath), ['new', 'a', 'b']);
      expect(restoreSongCollectionOrder(source, null), same(source));
    },
  );
  testWidgets('track-number sorting is available outside album view', (
    tester,
  ) async {
    Map<String, dynamic>? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (_) => const SortDialog(),
                );
              },
              child: const Text('排序'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('排序'));
    await tester.pumpAndSettle();
    expect(find.text('按音轨号排序'), findsOneWidget);
    await tester.ensureVisible(find.text('按音轨号排序'));
    await tester.tap(find.text('按音轨号排序'));
    await tester.tap(find.text('应用排序'));
    await tester.pumpAndSettle();
    expect(selected?['criterion'], SortCriterion.trackNumber);
  });
}
