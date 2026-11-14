import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/playback_bottom_sheet.dart';
import 'package:myune_music/widgets/landscape_playback_surface.dart';
import 'package:myune_music/widgets/compact_playback_lyrics.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';

void main() {
  testWidgets('side panel slides from right and ends at right edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPlaybackBottomSheet<void>(
                context: context,
                fromRight: true,
                builder: (_) => const SizedBox(
                  key: ValueKey('panel'),
                  height: 400,
                  child: Text('Panel'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final entering = tester
        .getTopLeft(find.byKey(const ValueKey('playback-side-panel')))
        .dx;
    await tester.pumpAndSettle();
    final rect = tester.getRect(
      find.byKey(const ValueKey('playback-side-panel')),
    );
    expect(entering, greaterThan(rect.left));
    expect(rect.right, closeTo(800, .1));
  });
  testWidgets(
    'information cover swipes right to centered and resize snaps geometry',
    (tester) async {
      var mode = LandscapeCoverMode.info;
      var width = 800.0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, set) {
                update = set;
                return Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    height: 400,
                    child: LandscapePlaybackSurface(
                      landscape: true,
                      mode: mode,
                      showLyrics: false,
                      title: 'Title',
                      artist: 'Artist',
                      cover: const ColoredBox(
                        key: ValueKey('cover'),
                        color: Colors.blue,
                      ),
                      lyrics: const SizedBox(),
                      onModeChanged: (value) => set(() => mode = value),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.drag(
        find.byKey(const ValueKey('cover')),
        const Offset(100, 0),
      );
      await tester.pumpAndSettle();
      expect(mode, LandscapeCoverMode.centered);
      update(() => width = 650);
      await tester.pump();
      final first = tester.getRect(find.byKey(const ValueKey('cover')));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const ValueKey('cover'))), first);
    },
  );
  testWidgets('interlude preview shows ellipsis', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompactPlaybackLyrics(
            lines: [
              LyricLine(
                timestamp: Duration.zero,
                texts: const [''],
                isInterlude: true,
              ),
            ],
            active: 0,
          ),
        ),
      ),
    );
    expect(find.text('…'), findsOneWidget);
  });
  test('ordinary preview progress is bounded and uses next timestamp', () {
    final line = LyricLine(
      timestamp: const Duration(seconds: 2),
      texts: const ['abc'],
    );
    expect(
      compactLyricProgress(line, Duration.zero, const Duration(seconds: 6)),
      0,
    );
    expect(
      compactLyricProgress(
        line,
        const Duration(seconds: 4),
        const Duration(seconds: 6),
      ),
      .5,
    );
    expect(
      compactLyricProgress(
        line,
        const Duration(seconds: 9),
        const Duration(seconds: 6),
      ),
      1,
    );
  });
}
