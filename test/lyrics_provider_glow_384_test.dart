import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/widgets/fullscreen_swipe_song_hint.dart';
import 'package:myune_music/widgets/now_playing_cover_glow.dart';

final _song = Song(filePath: '/new.mp3', title: 'New song', artist: 'Artist');
const _hint = ValueKey('fullscreen-swipe-song-hint');
const _fade = ValueKey('fullscreen-swipe-song-hint-fade');
const _slide = ValueKey('fullscreen-swipe-song-hint-slide');

class _HighlightSignal<T> extends ValueNotifier<T> {
  _HighlightSignal(super.value);
  bool get observed => hasListeners;
}

void main() {
  test('highlight start excludes prelude, blank and interlude rows', () {
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: [''], isInterlude: true),
      LyricLine(timestamp: const Duration(seconds: 3), texts: ['  ']),
      LyricLine(timestamp: const Duration(seconds: 5), texts: ['真正歌词']),
    ];
    bool active(int index, int ms) => hasHighlightedLyricLine(
      lines: lines,
      activeIndex: index,
      position: Duration(milliseconds: ms),
    );
    expect(active(-1, 0), isFalse);
    expect(active(0, 2500), isFalse);
    expect(active(1, 4500), isFalse);
    expect(active(2, 4999), isFalse);
    expect(active(2, 5000), isTrue);
    expect(active(3, 6000), isFalse);
  });

  testWidgets('highlight exits right early and unsubscribes after departure', (
    tester,
  ) async {
    final songs = FullscreenSwipeSongHintController();
    final highlight = _HighlightSignal<Object?>(null);
    await tester.pumpWidget(
      MaterialApp(
        home: FullscreenSwipeSongHint(
          enabled: true,
          currentSongIdentity: _song.normalizedPath,
          songChanges: songs,
          lyricHighlightChanges: highlight,
          readHighlightedSongIdentity: () => highlight.value,
        ),
      ),
    );
    expect(highlight.observed, isFalse);
    songs.show(_song);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    expect(find.byKey(_hint), findsOneWidget);
    expect(highlight.observed, isTrue);
    highlight.value = _song.normalizedPath;
    await tester.pump();
    await tester.pump(); // Anchor the ticker started by the post-frame check.
    await tester.pump(const Duration(milliseconds: 70));
    expect(
      tester.widget<FadeTransition>(find.byKey(_fade)).opacity.value,
      lessThan(1),
    );
    expect(
      tester.widget<Transform>(find.byKey(_slide)).transform.storage[12],
      greaterThan(0),
    );
    await tester.pump(const Duration(milliseconds: 90));
    expect(find.byKey(_hint), findsNothing);
    expect(highlight.observed, isFalse);
    await tester.pumpWidget(const SizedBox());
    highlight.dispose();
    songs.dispose();
  });

  testWidgets('stale other-song highlight preserves hold fallback', (
    tester,
  ) async {
    final songs = FullscreenSwipeSongHintController();
    final highlight = ValueNotifier<Object?>('/old.mp3');
    await tester.pumpWidget(
      MaterialApp(
        home: FullscreenSwipeSongHint(
          enabled: true,
          currentSongIdentity: _song.normalizedPath,
          songChanges: songs,
          lyricHighlightChanges: highlight,
          readHighlightedSongIdentity: () => highlight.value,
        ),
      ),
    );
    songs.show(_song);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.byKey(_hint), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1250));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(_hint), findsNothing);
    await tester.pumpWidget(const SizedBox());
    highlight.dispose();
    songs.dispose();
  });

  testWidgets(
    'highlight during entry preserves current pose without repeated restart',
    (tester) async {
      final songs = FullscreenSwipeSongHintController();
      final ticks = ValueNotifier<int>(0);
      Object? highlighted;
      await tester.pumpWidget(
        MaterialApp(
          home: FullscreenSwipeSongHint(
            enabled: true,
            currentSongIdentity: _song.normalizedPath,
            songChanges: songs,
            lyricHighlightChanges: ticks,
            readHighlightedSongIdentity: () => highlighted,
          ),
        ),
      );
      songs.show(_song);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      double x() =>
          tester.widget<Transform>(find.byKey(_slide)).transform.storage[12];
      final before = x();
      final alpha = tester
          .widget<FadeTransition>(find.byKey(_fade))
          .opacity
          .value;
      highlighted = _song.normalizedPath;
      ticks.value++;
      await tester.pump();
      expect(x(), closeTo(before, .001));
      expect(
        tester.widget<FadeTransition>(find.byKey(_fade)).opacity.value,
        closeTo(alpha, .001),
      );
      ticks.value++;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(x(), greaterThan(before));
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byKey(_hint), findsNothing);
      await tester.pumpWidget(const SizedBox());
      ticks.dispose();
      songs.dispose();
    },
  );

  testWidgets(
    'pending check cannot clear a replacement title or revive after disable',
    (tester) async {
      final songs = FullscreenSwipeSongHintController();
      final highlight = _HighlightSignal<Object?>(null);
      var enabled = true;
      var current = _song;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return FullscreenSwipeSongHint(
                enabled: enabled,
                currentSongIdentity: current.normalizedPath,
                songChanges: songs,
                lyricHighlightChanges: highlight,
                readHighlightedSongIdentity: () => highlight.value,
              );
            },
          ),
        ),
      );
      songs.show(_song);
      await tester.pump();
      highlight.value = _song.normalizedPath;
      final replacement = Song(
        filePath: '/replacement.mp3',
        title: 'Replacement',
        artist: 'Artist',
      );
      rebuild(() => current = replacement);
      songs.show(replacement);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));
      expect(find.text(replacement.title), findsOneWidget);
      highlight.value = replacement.normalizedPath;
      rebuild(() => enabled = false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(_hint), findsNothing);
      expect(highlight.observed, isFalse);
      await tester.pumpWidget(const SizedBox());
      highlight.dispose();
      songs.dispose();
    },
  );

  testWidgets(
    'cover halo is external and preserves cover layout/state across toggles',
    (tester) async {
      var enabled = true;
      late StateSetter rebuild;
      const coverKey = ValueKey('retained-cover');
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return NowPlayingCoverGlow(
                  enabled: enabled,
                  child: const SizedBox.square(
                    key: coverKey,
                    dimension: 240,
                    child: ColoredBox(color: Colors.blue),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final element = tester.element(find.byKey(coverKey));
      final bounds = tester.getRect(find.byKey(coverKey));
      final decorator = find.descendant(
        of: find.byType(NowPlayingCoverGlow),
        matching: find.byType(DecoratedBox),
      );
      BoxDecoration decoration() =>
          tester.widget<DecoratedBox>(decorator).decoration as BoxDecoration;
      expect(decoration().boxShadow!.single.color.a, closeTo(.20, .001));
      expect(decoration().boxShadow!.single.blurStyle, BlurStyle.outer);
      expect(find.byType(BackdropFilter), findsNothing);
      rebuild(() => enabled = false);
      await tester.pump();
      expect(decoration().boxShadow, isEmpty);
      expect(tester.element(find.byKey(coverKey)), same(element));
      expect(tester.getRect(find.byKey(coverKey)), bounds);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
}
