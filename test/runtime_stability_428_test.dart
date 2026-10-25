import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:myune_music/services/audio/audio_service.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/theme/theme_provider.dart';
import 'package:myune_music/services/cover_override_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myune_music/widgets/long_press_icon_button.dart';
import 'package:myune_music/widgets/transport_skip_button.dart';
import 'package:myune_music/widgets/lyrics_song_swipe_transition.dart';

class _Events extends Fake implements PlayerStream {
  final actual = StreamController<bool>.broadcast();
  @override
  Stream<bool> get playing => actual.stream;
  @override
  Stream<AudioParams> get audioParams => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => const Stream<Never>.empty();
}

class _Theme extends Fake implements ThemeProvider {}

class _Covers extends ChangeNotifier implements CoverOverrideService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Player extends Fake implements PlayerApi {
  final events = _Events();
  final opened = Completer<void>(), pitched = Completer<void>();
  Completer<void>? openGate, pitchGate, stopGate, exclusiveGate;
  var dsp = const MusicDspSettings();
  int plays = 0, stops = 0, releases = 0, rates = 0, eqs = 0;
  @override
  PlayerStream get stream => events;
  @override
  PlayerState get state => const PlayerState();
  @override
  MusicDspSettings get musicDsp => dsp;
  @override
  Future<void> setAudioClientName(String name) async {}
  @override
  Future<void> setRawProperty(String name, String value) async {}
  @override
  Future<void> setVolumeGain(double gain) async {}
  @override
  Future<void> setAudioExclusive(bool value) async {
    await exclusiveGate?.future;
  }

  @override
  Future<void> setPitch(double pitch) async {
    if (!pitched.isCompleted) pitched.complete();
    await pitchGate?.future;
  }

  @override
  Future<void> setRate(double rate) async {
    rates++;
  }

  @override
  Future<void> updateMusicDsp(
    MusicDspSettings Function(MusicDspSettings) mapper,
  ) async {
    eqs++;
    dsp = mapper(dsp);
  }

  @override
  Future<void> open(Media media, {bool? play}) async {
    if (!opened.isCompleted) opened.complete();
    await openGate?.future;
  }

  @override
  Future<void> openAll(List<Media> media, {int index = 0, bool? play}) =>
      open(media.first, play: play);
  @override
  Future<void> play() async {
    plays++;
  }

  @override
  Future<void> stop() async {
    stops++;
    await stopGate?.future;
  }

  @override
  Future<void> dispose() async {
    releases++;
  }
}

Future<void> _load(AudioService audio, bool gapless) => gapless
    ? audio.playSongGapless(
        'a.flac',
        nextPath: 'b.flac',
        pitch: 1,
        rate: 1,
        eqGains: [0, 0],
        eqFrequencies: [100, 1000],
      )
    : audio.playSong(
        'a.flac',
        pitch: 1,
        rate: 1,
        eqGains: [0, 0],
        eqFrequencies: [100, 1000],
      );

void main() {
  test(
    'real playlist owner releases subscriptions during unfinished startup',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      final player = _Player(), covers = _Covers();
      final audio = AudioService(player: player);
      final notifier = PlaylistContentNotifier(
        settings,
        _Theme(),
        covers,
        audioService: audio,
      );
      expect(player.events.actual.hasListener, isTrue);
      player.exclusiveGate = Completer<void>();
      final lateFailure = notifier.toggleExclusiveMode(true);
      notifier.dispose();
      player.exclusiveGate!.completeError(StateError('late exclusive failure'));
      await lateFailure;
      expect(await notifier.saveQueueAsPlaylist('', []), isFalse);
      await audio.dispose();
      await settings.initializationFuture;
      await Future<void>.delayed(Duration.zero);
      expect(player.events.actual.hasListener, isFalse);
      player.events.actual.add(true);
      await Future<void>.delayed(Duration.zero);
      expect([player.plays, player.releases], [0, 1]);
      expect(notifier.isPlaying, isFalse);
      await player.events.actual.close();
      settings.dispose();
      covers.dispose();
    },
  );
  for (final continuous in [false, true]) {
    testWidgets(
      'short press interrupted before release stays canceled: continuous=$continuous',
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: continuous
                  ? TransportSkipButton(
                      tooltip: 'skip',
                      icon: Icons.skip_next,
                      onSkip: () async {
                        calls++;
                      },
                    )
                  : LongPressIconButton(
                      tooltip: 'mode',
                      icon: const Icon(Icons.repeat),
                      onPressed: () => calls++,
                      onLongPress: () => calls++,
                    ),
            ),
          ),
        );
        final pointer = await tester.startGesture(
          tester.getCenter(find.byType(IconButton)),
        );
        await tester.pump(const Duration(milliseconds: 200));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await pointer.up();
        await tester.pumpAndSettle();
        expect(calls, 0);
        await tester.tap(find.byType(IconButton));
        await tester.pump();
        expect(calls, 1);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'repeated canceled lyric exits recover without orphan animations',
    (tester) async {
      var calls = 0;
      Future<void> host(bool enabled) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LyricsSongSwipeTransition(
              enabled: enabled,
              songIdentity: 1,
              onNext: () async {
                calls++;
              },
              onPrevious: () async {},
              child: const SizedBox.expand(key: ValueKey('surface')),
            ),
          ),
        ),
      );
      for (var i = 0; i < 40; i++) {
        await host(true);
        await tester.drag(
          find.byKey(const ValueKey('surface')),
          const Offset(-180, 0),
        );
        await tester.pump(const Duration(milliseconds: 20));
        await host(false);
        await tester.pumpAndSettle();
      }
      expect(calls, 0);
      await host(true);
      await tester.drag(
        find.byKey(const ValueKey('surface')),
        const Offset(-180, 0),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'failed held skip releases once, stops repeats, then accepts a new tap',
    (tester) async {
      var calls = 0, errors = 0, releases = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransportSkipButton(
              tooltip: 'skip',
              icon: Icons.skip_next,
              onHoldStart: () => () {
                releases++;
              },
              onError: (_, __) => errors++,
              onSkip: () {
                calls++;
                if (calls == 1) throw StateError('failed');
                return Future.value();
              },
            ),
          ),
        ),
      );
      final pointer = await tester.startGesture(
        tester.getCenter(find.byType(IconButton)),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 4));
      expect([calls, errors, releases], [1, 1, 1]);
      await pointer.up();
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(calls, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'backgrounding a pending lyric load cannot duplicate it or replay an old callback',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0, completions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LyricsSongSwipeTransition(
              enabled: true,
              songIdentity: 1,
              onNext: () {
                calls++;
                return calls == 1 ? pending.future : Future.value();
              },
              onPrevious: () async {},
              onSwitchCompleted: (_) => completions++,
              child: const SizedBox.expand(key: ValueKey('surface')),
            ),
          ),
        ),
      );
      final surface = find.byKey(const ValueKey('surface'));
      await tester.drag(surface, const Offset(-200, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(calls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.drag(surface, const Offset(-200, 0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, 1);
      pending.complete();
      await tester.pumpAndSettle();
      expect(completions, 0);
      await tester.drag(surface, const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect([calls, completions], [2, 1]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final gapless in [false, true]) {
    test('shutdown cannot restart a late open: gapless=$gapless', () async {
      final player = _Player()..openGate = Completer<void>();
      final audio = AudioService(player: player);
      final loading = _load(audio, gapless);
      await player.opened.future;
      await audio.dispose();
      player.openGate!.complete();
      await loading;
      expect(player.plays, 0);
      expect(player.releases, 1);
    });
  }
  test(
    'shutdown interrupts the remaining playback configuration writes',
    () async {
      final player = _Player()..pitchGate = Completer<void>();
      final audio = AudioService(player: player);
      final loading = _load(audio, false);
      await player.pitched.future;
      await audio.dispose();
      player.pitchGate!.complete();
      await loading;
      expect(player.rates, 0);
      expect(player.eqs, 0);
      expect(player.opened.isCompleted, isFalse);
    },
  );
  test(
    'concurrent shutdown callers wait for the same completed release',
    () async {
      final player = _Player()..stopGate = Completer<void>();
      final audio = AudioService(player: player);
      final first = audio.dispose();
      var secondFinished = false;
      final second = audio.dispose().then((_) => secondFinished = true);
      await Future<void>.delayed(Duration.zero);
      expect(secondFinished, isFalse);
      player.stopGate!.complete();
      await Future.wait([first, second]);
      expect([player.stops, player.releases], [1, 1]);
    },
  );
  for (final continuous in [false, true]) {
    testWidgets(
      'interrupted hold cannot trigger after resume: continuous=$continuous',
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: continuous
                  ? TransportSkipButton(
                      tooltip: 'skip',
                      icon: Icons.skip_next,
                      onSkip: () async {
                        calls++;
                      },
                    )
                  : LongPressIconButton(
                      tooltip: 'mode',
                      icon: const Icon(Icons.repeat),
                      onPressed: () => calls++,
                      onLongPress: () => calls++,
                    ),
            ),
          ),
        );
        final pointer = await tester.startGesture(
          tester.getCenter(find.byType(IconButton)),
        );
        await tester.pump(const Duration(milliseconds: 250));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump(const Duration(milliseconds: 400));
        await pointer.up();
        await tester.pump(const Duration(seconds: 2));
        expect(calls, 0);
        await tester.tap(find.byType(IconButton));
        await tester.pump();
        expect(calls, 1);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final covered in [false, true]) {
    testWidgets(
      'interrupted lyric exit does not change media: covered=$covered',
      (tester) async {
        var calls = 0;
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: Scaffold(
              body: LyricsSongSwipeTransition(
                enabled: true,
                songIdentity: 1,
                onNext: () async {
                  calls++;
                },
                onPrevious: () async {},
                child: const SizedBox.expand(key: ValueKey('surface')),
              ),
            ),
          ),
        );
        await tester.drag(
          find.byKey(const ValueKey('surface')),
          const Offset(-200, 0),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        if (covered) {
          unawaited(
            navigator.currentState!.push(
              PageRouteBuilder<void>(
                transitionDuration: Duration.zero,
                pageBuilder: (_, __, ___) =>
                    const Scaffold(body: Text('other page')),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 200));
          navigator.currentState!.pop();
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
        await tester.pumpAndSettle();
        expect(calls, 0);
        expect(
          tester
              .widget<FadeTransition>(
                find.byKey(const ValueKey('lyrics_song_handoff')),
              )
              .opacity
              .value,
          1,
        );
        await tester.drag(
          find.byKey(const ValueKey('surface')),
          const Offset(-200, 0),
        );
        await tester.pumpAndSettle();
        expect(calls, 1);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
