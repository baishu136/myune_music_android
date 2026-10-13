import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/widgets/fullscreen_swipe_song_hint.dart';
import 'package:myune_music/widgets/lyrics_song_swipe_transition.dart';

final _a = Song(title: '第一首', artist: '歌手甲', filePath: '/a.mp3');
final _b = Song(title: '第二首', artist: '歌手乙', filePath: '/b.mp3');
final _c = Song(title: '第三首', artist: '歌手丙', filePath: '/c.mp3');
const _surface = ValueKey('retained-lyrics');
const _hint = ValueKey('fullscreen-swipe-song-hint');

void main() {
  testWidgets(
    'a completed swipe shows committed metadata, never pending data',
    (tester) async {
      final controller = FullscreenSwipeSongHintController();
      final load = Completer<void>();
      var current = _a;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Stack(
                children: [
                  LyricsSongSwipeTransition(
                    enabled: true,
                    songIdentity: current.normalizedPath,
                    onNext: () async {
                      await load.future;
                      rebuild(() => current = _b);
                    },
                    onPrevious: () async {},
                    onSwitchCompleted: (previous) {
                      if (current.normalizedPath != previous) {
                        controller.show(current);
                      }
                    },
                    child: const SizedBox.expand(key: _surface),
                  ),
                  Positioned(
                    top: 8,
                    left: 16,
                    right: 16,
                    child: FullscreenSwipeSongHint(
                      enabled: true,
                      currentSongIdentity: current.normalizedPath,
                      songChanges: controller,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
      final element = tester.element(find.byKey(_surface));
      final size = tester.getSize(find.byKey(_surface));
      await tester.drag(
        find.byType(LyricsSongSwipeTransition),
        const Offset(-200, 0),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byKey(_hint), findsNothing);
      load.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(_b.title), findsOneWidget);
      expect(find.text(_b.artist), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.text(_a.title), findsNothing);
      expect(tester.element(find.byKey(_surface)), same(element));
      expect(tester.getSize(find.byKey(_surface)), size);
      await tester.pump(const Duration(milliseconds: 1900));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(_hint), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  for (final mode in ['failure', 'no-op', 'disabled while pending']) {
    testWidgets('$mode does not publish a successful swipe', (tester) async {
      final load = Completer<void>();
      var enabled = true, callbacks = 0, completions = 0, errors = 0;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return LyricsSongSwipeTransition(
                enabled: enabled,
                songIdentity: _a.normalizedPath,
                onNext: () => load.future,
                onPrevious: () async {},
                onError: (_, _) => errors++,
                onSwitchCompleted: (previous) {
                  completions++;
                  if (_a.normalizedPath != previous) callbacks++;
                },
                child: const SizedBox.expand(key: _surface),
              );
            },
          ),
        ),
      );
      await tester.drag(
        find.byType(LyricsSongSwipeTransition),
        const Offset(-200, 0),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      if (mode == 'disabled while pending') {
        rebuild(() => enabled = false);
        await tester.pump();
      }
      if (mode == 'failure') {
        load.completeError(StateError('decoder failure'));
      } else {
        load.complete();
      }
      await tester.pumpAndSettle();
      expect(callbacks, 0);
      expect(completions, mode == 'no-op' ? 1 : 0);
      expect(errors, mode == 'failure' ? 1 : 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('renewed events replace metadata and cancel the old expiry', (
    tester,
  ) async {
    final controller = FullscreenSwipeSongHintController();
    Future<void> host(Song current, {bool enabled = true}) => tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: FullscreenSwipeSongHint(
            enabled: enabled,
            currentSongIdentity: current.normalizedPath,
            songChanges: controller,
          ),
        ),
      ),
    );
    await host(_a);
    await host(_b);
    expect(find.byKey(_hint), findsNothing, reason: 'external change is quiet');
    controller.show(_b);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2000));
    controller.show(_c);
    await host(_c);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(_c.title), findsOneWidget);
    expect(find.text(_b.title), findsNothing);
    final fade = tester.widget<FadeTransition>(
      find.byKey(const ValueKey('fullscreen-swipe-song-hint-fade')),
    );
    expect(fade.opacity.value, 1);
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(_hint), findsNothing);
    // The same cached Song must still issue a new event after expiration.
    controller.show(_c);
    await tester.pump();
    expect(find.text(_c.title), findsOneWidget);
    await host(_c, enabled: false);
    expect(find.byKey(_hint), findsNothing);
    await host(_c);
    expect(find.byKey(_hint), findsNothing, reason: 're-entry does not replay');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('hint passes touches through and fits narrow enlarged text', (
    tester,
  ) async {
    final controller = FullscreenSwipeSongHintController();
    final song = Song(
      title: '很长的歌曲名称' * 20,
      artist: '很长的歌手名字' * 20,
      filePath: '/long.mp3',
    );
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Center(
            child: SizedBox(
              width: 220,
              height: 400,
              child: Stack(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps++,
                    child: const SizedBox.expand(key: _surface),
                  ),
                  Positioned(
                    top: 8,
                    left: 16,
                    right: 16,
                    child: FullscreenSwipeSongHint(
                      enabled: true,
                      currentSongIdentity: song.normalizedPath,
                      songChanges: controller,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    controller.show(song);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(tester.getSize(find.byKey(_hint)).width, 188);
    expect(
      tester.getTopLeft(find.byKey(_hint)).dy,
      tester.getTopLeft(find.byKey(_surface)).dy + 8,
    );
    await tester.tapAt(tester.getCenter(find.byKey(_hint)));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'renewal during fade keeps opacity and external changes dismiss',
    (tester) async {
      final controller = FullscreenSwipeSongHintController();
      Future<void> host(Song current) => tester.pumpWidget(
        MaterialApp(
          home: FullscreenSwipeSongHint(
            enabled: true,
            currentSongIdentity: current.normalizedPath,
            songChanges: controller,
          ),
        ),
      );
      await host(_b);
      controller.show(_b);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump(const Duration(milliseconds: 100));
      double alpha() => tester
          .widget<FadeTransition>(
            find.byKey(const ValueKey('fullscreen-swipe-song-hint-fade')),
          )
          .opacity
          .value;
      final before = alpha();
      expect(before, inExclusiveRange(0, 1));
      controller.show(_c);
      await host(_c);
      expect(
        alpha(),
        0,
        reason: 'new metadata follows the lyric entry animation',
      );
      await tester.pump(const Duration(milliseconds: 240));
      expect(alpha(), 1);
      expect(find.text(_c.title), findsOneWidget);
      await host(_a);
      expect(find.byKey(_hint), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'right swipe supplies original identity and disposal cancels completion',
    (tester) async {
      final load = Completer<void>();
      Object? original;
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LyricsSongSwipeTransition(
            enabled: true,
            songIdentity: _b.normalizedPath,
            onNext: () async {},
            onPrevious: () => load.future,
            onSwitchCompleted: (previous) {
              calls++;
              original = previous;
            },
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.drag(
        find.byType(LyricsSongSwipeTransition),
        const Offset(200, 0),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(calls, 0);
      load.complete();
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(original, _b.normalizedPath);
      final pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: LyricsSongSwipeTransition(
            enabled: true,
            songIdentity: _a.normalizedPath,
            onNext: () => pending.future,
            onPrevious: () async {},
            onSwitchCompleted: (_) => calls++,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(LyricsSongSwipeTransition),
        const Offset(-200, 0),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pumpWidget(const SizedBox());
      pending.complete();
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'background and disposal cancel fading without replay or errors',
    (tester) async {
      final controller = FullscreenSwipeSongHintController();
      await tester.pumpWidget(
        MaterialApp(
          home: FullscreenSwipeSongHint(
            enabled: true,
            currentSongIdentity: _b.normalizedPath,
            songChanges: controller,
          ),
        ),
      );
      controller.show(_b);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byKey(_hint), findsNothing);
      controller.show(_b);
      await tester.pump();
      expect(find.byKey(_hint), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byKey(_hint), findsNothing);
      controller.show(_b);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
      controller.dispose();
    },
  );

  testWidgets('reduced motion shows immediately and expires without fading', (
    tester,
  ) async {
    final controller = FullscreenSwipeSongHintController();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: FullscreenSwipeSongHint(
            enabled: true,
            currentSongIdentity: _b.normalizedPath,
            songChanges: controller,
          ),
        ),
      ),
    );
    controller.show(_b);
    await tester.pump();
    expect(
      tester
          .widget<FadeTransition>(
            find.byKey(const ValueKey('fullscreen-swipe-song-hint-fade')),
          )
          .opacity
          .value,
      1,
    );
    await tester.pump(FullscreenSwipeSongHint.holdDuration);
    expect(find.byKey(_hint), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
