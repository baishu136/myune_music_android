import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/mobile/mobile_shell.dart';

void main() {
  test('distant home navigation animates only across an adjacent bridge', () {
    expect(homePageAnimationBridge(0, 4), 3);
    expect(homePageAnimationBridge(4, 0), 1);
    expect(homePageAnimationBridge(1, 2), isNull);
    expect(homePageAnimationBridge(3, 3), isNull);
  });

  test('library entrance is claimed exactly when songs first appear', () {
    expect(
      shouldStartLibraryEntrance(
        enabled: true,
        libraryLoaded: true,
        hasSongs: true,
        alreadyStarted: false,
        alreadyClaimed: false,
      ),
      isTrue,
    );
    expect(
      shouldStartLibraryEntrance(
        enabled: true,
        libraryLoaded: true,
        hasSongs: true,
        alreadyStarted: true,
        alreadyClaimed: false,
      ),
      isFalse,
    );
    expect(
      shouldStartLibraryEntrance(
        enabled: true,
        libraryLoaded: true,
        hasSongs: false,
        alreadyStarted: false,
        alreadyClaimed: false,
      ),
      isFalse,
    );
    expect(
      shouldStartLibraryEntrance(
        enabled: true,
        libraryLoaded: true,
        hasSongs: true,
        alreadyStarted: false,
        alreadyClaimed: true,
      ),
      isFalse,
    );
    expect(
      shouldStartLibraryEntrance(
        enabled: true,
        libraryLoaded: false,
        hasSongs: true,
        alreadyStarted: false,
        alreadyClaimed: false,
      ),
      isFalse,
    );
  });

  test('library entrance limits keep both startup views lightweight', () {
    expect(libraryEntranceItemLimit(LibraryEntranceStyle.list), 6);
    expect(libraryEntranceItemLimit(LibraryEntranceStyle.indexed), 10);
  });

  testWidgets('original staggered song entrance remains visible in each mode', (
    tester,
  ) async {
    final animation = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 720),
    );
    addTearDown(animation.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          key: const ValueKey('entrance-host'),
          child: buildLibrarySongEntranceTransition(
            animation: animation,
            order: 0,
            child: const SizedBox(key: ValueKey('song-card')),
          ),
        ),
      ),
    );
    FadeTransition opacity() => tester.widget<FadeTransition>(
      find.descendant(
        of: find.byKey(const ValueKey('entrance-host')),
        matching: find.byType(FadeTransition),
      ),
    );
    SlideTransition translation() => tester.widget<SlideTransition>(
      find.descendant(
        of: find.byKey(const ValueKey('entrance-host')),
        matching: find.byType(SlideTransition),
      ),
    );

    expect(opacity().opacity.value, 0);
    expect(translation().position.value.dy, closeTo(.18, .001));
    animation.value = .3;
    await tester.pump();
    expect(opacity().opacity.value, inExclusiveRange(0, 1));
    animation.value = 1;
    await tester.pump();
    expect(opacity().opacity.value, 1);
    expect(translation().position.value.dy, 0);
  });

  testWidgets('indexed entrance animates one visible wave and skips its tail', (
    tester,
  ) async {
    final animation = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 720),
    );
    addTearDown(animation.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          key: const ValueKey('indexed-tail-host'),
          child: buildLibrarySongEntranceTransition(
            animation: animation,
            order: 10,
            style: LibraryEntranceStyle.indexed,
            child: const SizedBox(key: ValueKey('indexed-tail-song')),
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('indexed-tail-host')),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('indexed-tail-song')), findsOneWidget);
  });
}
