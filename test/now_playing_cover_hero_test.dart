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

  test('initial cover Hero requires a prepared high resolution image', () {
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
