import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/lyrics_song_swipe_transition.dart';

void main() {
  testWidgets(
    'fullscreen left/right change songs after exit, without replacing content',
    (tester) async {
      var next = 0, previous = 0, vertical = 0;
      final surface = GlobalKey();
      Future<void> host({bool enabled = true, Object song = 1}) =>
          tester.pumpWidget(
            MaterialApp(
              home: LyricsSongSwipeTransition(
                enabled: enabled,
                songIdentity: song,
                onNext: () async {
                  next++;
                },
                onPrevious: () async {
                  previous++;
                },
                child: GestureDetector(
              behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (_) => vertical++,
                  child: SizedBox.expand(key: surface),
                ),
              ),
            ),
          );
      double alpha() => tester
          .widget<FadeTransition>(
            find.byKey(const ValueKey('lyrics_song_handoff')),
          )
          .opacity
          .value;
      await host();
      final element = surface.currentContext;
      await tester.drag(find.byKey(surface), const Offset(-200, 0));
      expect(
        next,
        0,
        reason: 'media is not replaced while old lyrics are visible',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(alpha(), inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 60));
      expect(next, 1);
      await tester.pumpAndSettle();
      expect(alpha(), 1);
      expect(surface.currentContext, same(element));
      await tester.drag(find.byKey(surface), const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(previous, 1);
      await tester.drag(find.byKey(surface), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(vertical, greaterThan(0));
      expect([next, previous], [1, 1]);
      await host(enabled: false);
      await tester.drag(find.byKey(surface), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(next, 1);
    },
  );

  testWidgets('short and two-finger gestures do not change media', (
    tester,
  ) async {
    var count = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LyricsSongSwipeTransition(
          enabled: true,
          songIdentity: 1,
          onNext: () async {
            count++;
          },
          onPrevious: () async {
            count++;
          },
          child: const SizedBox.expand(key: ValueKey('surface')),
        ),
      ),
    );
    final center = tester.getCenter(find.byKey(const ValueKey('surface')));
    final short = await tester.startGesture(center);
    await short.moveBy(const Offset(-35, 0));
    await tester.pump(const Duration(milliseconds: 200));
    await short.up();
    await tester.pumpAndSettle();
    expect(count, 0);
    final one = await tester.startGesture(center, pointer: 1);
    final two = await tester.startGesture(
      center + const Offset(0, 40),
      pointer: 2,
    );
    await one.moveBy(const Offset(-180, 0));
    await two.moveBy(const Offset(-180, 0));
    await one.up();
    await two.up();
    await tester.pumpAndSettle();
    expect(count, 0);
  });

  testWidgets(
    'pending media load locks repeat swipes; errors restore the surface',
    (tester) async {
      final loading = Completer<void>();
      var count = 0, errors = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LyricsSongSwipeTransition(
            enabled: true,
            songIdentity: 1,
            onNext: () {
              count++;
              return loading.future;
            },
            onPrevious: () async {},
            onError: (_, _) => errors++,
            child: const SizedBox.expand(key: ValueKey('surface')),
          ),
        ),
      );
      await tester.drag(
        find.byKey(const ValueKey('surface')),
        const Offset(-200, 0),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(count, 1);
      await tester.drag(
        find.byKey(const ValueKey('surface')),
        const Offset(-200, 0),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(count, 1);
      loading.completeError(StateError('load failed'));
      await tester.pumpAndSettle();
      expect(errors, 1);
      expect(
        tester
            .widget<FadeTransition>(
              find.byKey(const ValueKey('lyrics_song_handoff')),
            )
            .opacity
            .value,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disable/dispose cancels an exit before media mutation', (
    tester,
  ) async {
    var count = 0;
    Future<void> host(bool enabled) => tester.pumpWidget(
      MaterialApp(
        home: LyricsSongSwipeTransition(
          enabled: enabled,
          songIdentity: 1,
          onNext: () async {
            count++;
          },
          onPrevious: () async {},
          child: const SizedBox.expand(key: ValueKey('surface')),
        ),
      ),
    );
    await host(true);
    await tester.drag(
      find.byKey(const ValueKey('surface')),
      const Offset(-200, 0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await host(false);
    await tester.pumpAndSettle();
    expect(count, 0);
    expect(
      tester
          .widget<FadeTransition>(
            find.byKey(const ValueKey('lyrics_song_handoff')),
          )
          .opacity
          .value,
      1,
    );
    await host(true);
    await tester.drag(
      find.byKey(const ValueKey('surface')),
      const Offset(-200, 0),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(count, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'external song identity enters smoothly with one retained child',
    (tester) async {
      final key = GlobalKey();
      Future<void> host(int song) => tester.pumpWidget(
        MaterialApp(
          home: LyricsSongSwipeTransition(
            enabled: true,
            songIdentity: song,
            onNext: () async {},
            onPrevious: () async {},
            child: SizedBox.expand(key: key),
          ),
        ),
      );
      await host(1);
      final element = key.currentContext;
      await host(2);
      expect(
        tester
            .widget<FadeTransition>(
              find.byKey(const ValueKey('lyrics_song_handoff')),
            )
            .opacity
            .value,
        0,
      );
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        tester
            .widget<FadeTransition>(
              find.byKey(const ValueKey('lyrics_song_handoff')),
            )
            .opacity
            .value,
        inExclusiveRange(0, 1),
      );
      await tester.pumpAndSettle();
      expect(key.currentContext, same(element));
    },
  );
}
