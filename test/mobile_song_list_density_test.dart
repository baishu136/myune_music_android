import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/mobile/mobile_shell.dart';

void main() {
  testWidgets(
    'phone song rows leave a small gap without shrinking artwork or hit area',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var tapped = -1;

      Widget buildRows({double textScale = 1}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: ListView(
              children: List.generate(
                3,
                (index) => KeyedSubtree(
                  key: ValueKey('song-row-$index'),
                  child: buildMobileSongListTile(
                    grid: false,
                    compact: false,
                    leading: SizedBox(
                      key: ValueKey('song-cover-$index'),
                      width: 48,
                      height: 48,
                    ),
                    title: Text('测试歌曲 $index', maxLines: 1),
                    subtitle: const Text('测试歌手 · 测试专辑', maxLines: 1),
                    trailing: const SizedBox(width: 48, height: 48),
                    onTap: () => tapped = index,
                    onLongPress: null,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(buildRows());
      final first = find.byKey(const ValueKey('song-row-0'));
      final second = find.byKey(const ValueKey('song-row-1'));
      final firstCover = find.byKey(const ValueKey('song-cover-0'));
      final secondCover = find.byKey(const ValueKey('song-cover-1'));
      expect(tester.getSize(first).height, closeTo((78 + 56) / 2, .01));
      expect(
        tester.getTopLeft(second).dy - tester.getTopLeft(first).dy,
        closeTo(mobileSongListRowExtent, .01),
      );
      expect(tester.getSize(firstCover).height, 48);
      expect(
        tester.getTopLeft(secondCover).dy - tester.getBottomLeft(firstCover).dy,
        closeTo((30 + 8) / 2, .01),
      );
      expect(tester.getSize(first).height, greaterThanOrEqualTo(48));
      await tester.tap(find.text('测试歌曲 1'));
      expect(tapped, 1);
      expect(tester.takeException(), isNull);

      // A larger system text scale must expand naturally instead of clipping.
      await tester.pumpWidget(buildRows(textScale: 1.6));
      expect(
        tester.getSize(first).height,
        greaterThanOrEqualTo(mobileSongListRowExtent),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('grid and split-pane rows retain their existing layout rules', (
    tester,
  ) async {
    for (final (grid, compact) in [(true, false), (false, true)]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: buildMobileSongListTile(
              grid: grid,
              compact: compact,
              leading: const SizedBox(width: 40, height: 40),
              title: const Text('歌曲'),
              subtitle: const Text('歌手 · 专辑'),
              trailing: const SizedBox(width: 48, height: 48),
              onTap: null,
              onLongPress: null,
            ),
          ),
        ),
      );
      final tile = tester.widget<ListTile>(find.byType(ListTile));
      expect(tile.minTileHeight, isNull);
      expect(tile.contentPadding!.vertical, grid ? 6 : 0);
      expect(tile.minVerticalPadding, compact ? 10 : isNull);
      expect(tester.takeException(), isNull);
    }
  });
}
