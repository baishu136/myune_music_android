import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:myune_music/widgets/now_playing_cover_hero.dart';

void main() {
  test('cover Hero is disabled whenever lyrics are visible', () {
    expect(
      shouldEnableNowPlayingCoverHero(
        showLyrics: true,
        routeTransitionComplete: true,
        initialCoverHeroReady: true,
      ),
      isFalse,
    );
  });

  test('initial cover Hero requires a prepared transition image', () {
    expect(
      shouldEnableNowPlayingCoverHero(
        showLyrics: false,
        routeTransitionComplete: false,
        initialCoverHeroReady: false,
      ),
      isFalse,
    );
    expect(
      shouldEnableNowPlayingCoverHero(
        showLyrics: false,
        routeTransitionComplete: false,
        initialCoverHeroReady: true,
      ),
      isTrue,
    );
  });

  test('visible cover can fly back after route entry is complete', () {
    expect(
      shouldEnableNowPlayingCoverHero(
        showLyrics: false,
        routeTransitionComplete: true,
        initialCoverHeroReady: false,
      ),
      isTrue,
    );
  });

  test('realtime lyrics pause only for the route transition window', () {
    expect(
      shouldRunNowPlayingLyricsRealtime(
        showLyrics: true,
        routeTransitionActive: true,
      ),
      isFalse,
    );
    expect(
      shouldRunNowPlayingLyricsRealtime(
        showLyrics: true,
        routeTransitionActive: false,
      ),
      isTrue,
    );
    expect(
      shouldRunNowPlayingLyricsRealtime(
        showLyrics: false,
        routeTransitionActive: false,
      ),
      isFalse,
    );
  });

  test('previous cover is retained only for the active song handoff', () {
    expect(
      shouldRetainPreviousNowPlayingArtwork(
        songPath: 'new-song',
        preparedPath: 'old-song',
        handoffTargetPath: 'new-song',
      ),
      isTrue,
    );
    expect(
      shouldRetainPreviousNowPlayingArtwork(
        songPath: 'new-song',
        preparedPath: 'old-song',
        handoffTargetPath: null,
      ),
      isFalse,
    );
    expect(
      shouldRetainPreviousNowPlayingArtwork(
        songPath: 'another-song',
        preparedPath: 'old-song',
        handoffTargetPath: 'new-song',
      ),
      isFalse,
    );
  });

  testWidgets('stable cover shuttle completes push and pop without swapping', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(
          body: Center(
            child: NowPlayingCoverHero(
              normalizedSongPath: 'song',
              child: SizedBox.square(dimension: 48),
            ),
          ),
        ),
      ),
    );

    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(
          body: Center(
            child: NowPlayingCoverHero(
              normalizedSongPath: 'song',
              child: SizedBox.square(dimension: 240),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
