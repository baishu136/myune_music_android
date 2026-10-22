import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/services/song_group_presentation.dart';
import 'package:myune_music/widgets/song_collection_header.dart';

void main() {
  test('featured group uses combined listens and ignores prior pin order', () {
    Song song(String path) =>
        Song(title: path, artist: '', album: '', filePath: path);
    final a = song('a.mp3'), b = song('b.mp3'), c = song('c.mp3');
    final counts = {'a.mp3': 7, 'b.mp3': 6, 'c.mp3': 12};
    final totals = {
      'Pinned': SongGroupPresentation.totalPlayCount([c], counts),
      'Most': SongGroupPresentation.totalPlayCount([a, b], counts),
    };
    expect(SongGroupPresentation.mostPlayedGroup(totals), 'Most');
    expect(SongGroupPresentation.totalPlayCount([a, a, b], counts), 13);
    expect(SongGroupPresentation.mostPlayedGroup({'Z': 4, 'A': 4}), 'A');
    expect(SongGroupPresentation.mostPlayedGroup({'A': 0}), isNull);
    expect(SongGroupPresentation.mostPlayedGroup({}), isNull);
  });
  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(800, 1280),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('collection header remains usable $size scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var plays = 0;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: SongCollectionHeader(
                  title: '歌手名字与专辑名称 A long album title',
                  songCount: 242,
                  playCount: 12345,
                  artwork: const ColoredBox(color: Colors.teal),
                  onPlayAll: () => plays++,
                ),
              ),
            ),
          ),
        );
        expect(find.text('共 242 首歌曲'), findsOneWidget);
        expect(find.text('已收听 12345 次'), findsOneWidget);
        await tester.tap(find.byTooltip('播放全部'));
        expect(plays, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
