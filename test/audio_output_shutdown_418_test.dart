import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:myune_music/models/audio_output_state.dart';
import 'package:myune_music/services/audio/audio_output_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Events extends Fake implements PlayerStream {
  final errors = StreamController<MpvPlayerError>.broadcast(sync: true);
  @override
  Stream<MpvPlayerError> get error => errors.stream;
  @override
  Stream<AudioParams> get audioParams => const Stream.empty();
}

class _Player extends Fake implements PlayerApi {
  final events = _Events();
  final writes = <String>[];
  final initializationStarted = Completer<void>();
  Completer<void>? initializationGate;
  final reloadStarted = Completer<void>();
  Completer<void>? reloadGate;
  int reloads = 0;
  @override
  PlayerStream get stream => events;
  @override
  PlayerState get state => const PlayerState(
    playing: true,
    playWhenReady: true,
    audioParams: AudioParams(
      format: Format.s16,
      sampleRate: 44100,
      channelCount: 2,
    ),
  );
  @override
  Future<void> setRawProperty(String name, String value) async {
    if (name == 'ao' && !initializationStarted.isCompleted) {
      initializationStarted.complete();
      await initializationGate?.future;
    }
    writes.add('$name=$value');
  }

  @override
  Future<String?> getRawProperty(String name) async => 'null';
  @override
  Future<void> reloadAudio() async {
    reloads++;
    if (!reloadStarted.isCompleted) reloadStarted.complete();
    await reloadGate?.future;
  }

  @override
  Future<void> setAudioExclusive(bool value) async {
    writes.add('exclusive=$value');
  }

  @override
  Future<void> setTransparentOutput(
    bool value, {
    String format = 'auto',
    int sampleRate = 0,
    String channels = 'auto',
  }) async {
    writes.add('transparent=$value');
  }
}

class _Harness {
  _Harness({bool blockInitialization = false}) {
    if (blockInitialization) player.initializationGate = Completer<void>();
    final name = 'output-shutdown-418-${_nextId++}';
    channel = MethodChannel(name);
    events = EventChannel('$name-events');
    messenger.setMockMethodCallHandler(
      MethodChannel(events.name),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'snapshot'
          ? {
              'sdk': 35,
              'bridgeAvailable': true,
              'routeVerified': true,
              'stream': [0, 1, 1, 44100, 1, 2, 1, 4],
              'devices': [
                {
                  'id': 1,
                  'name': 'USB DAC',
                  'profileKey': 'connection:usb',
                  'persistentIdentity': false,
                  'usb': true,
                  'directSelectable': true,
                },
              ],
            }
          : null;
    });
    output = AudioOutputController(
      player: player,
      android: true,
      channel: channel,
      events: events,
    );
  }
  static int _nextId = 0;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final player = _Player();
  final calls = <String>[];
  late final MethodChannel channel;
  late final EventChannel events;
  late final AudioOutputController output;
  bool notifierDisposed = false;
  void disposeNotifier() {
    if (notifierDisposed) return;
    notifierDisposed = true;
    output.dispose();
  }

  Future<void> close() async {
    final gate = player.initializationGate;
    if (gate != null && !gate.isCompleted) gate.complete();
    final reloadGate = player.reloadGate;
    if (reloadGate != null && !reloadGate.isCompleted) reloadGate.complete();
    disposeNotifier();
    await output.initializationFuture;
    await output.releaseResources();
    await player.events.errors.close();
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(MethodChannel(events.name), null);
  }
}

const _failure = MpvLogError(
  prefix: 'ao/aaudio',
  level: LogLevel.error,
  text: 'AAudioStreamBuilder_openStream() returned AAUDIO_ERROR_UNAVAILABLE',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'release waits for in-flight initialization before restoring output',
    () async {
      final harness = _Harness(blockInitialization: true);
      addTearDown(harness.close);
      await harness.player.initializationStarted.future;
      var released = false;
      final release = harness.output.releaseResources().then(
        (_) => released = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(released, isFalse);
      expect(harness.player.writes, isEmpty);
      harness.player.initializationGate!.complete();
      await release;
      expect(harness.player.writes, [
        'ao=audiotrack,opensles',
        'transparent=false',
        'exclusive=false',
      ]);
    },
  );

  test('release cancels a pending recovery before notifier disposal', () async {
    final harness = _Harness();
    addTearDown(harness.close);
    await harness.output.initializationFuture;
    harness.player.events.errors.add(_failure);
    await harness.output.releaseResources();
    expect(harness.player.events.errors.hasListener, isFalse);
    final writes = List<String>.of(harness.player.writes);
    await Future<void>.delayed(const Duration(milliseconds: 1050));
    expect(harness.player.reloads, 0);
    expect(harness.player.writes, writes);
  });

  test('late errors cannot reopen released output', () async {
    final harness = _Harness();
    addTearDown(harness.close);
    await harness.output.initializationFuture;
    await harness.output.releaseResources();
    harness.player.events.errors.add(_failure);
    await Future<void>.delayed(const Duration(milliseconds: 1050));
    expect(harness.player.reloads, 0);
  });

  test(
    'post-release output actions do not reach player or native channel',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      await harness.output.initializationFuture;
      await harness.output.releaseResources();
      final writes = List<String>.of(harness.player.writes);
      final calls = List<String>.of(harness.calls);
      await harness.output.useAutomatic();
      await harness.output.selectDevice(1);
      await harness.output.setMode(AudioOutputMode.standard);
      await harness.output.refresh();
      await harness.output.requestUsbIdentity();
      await harness.output.systemPicker();
      expect(harness.player.writes, writes);
      expect(harness.calls, calls);
      expect(harness.player.reloads, 0);
    },
  );

  test('release is idempotent before and after notifier disposal', () async {
    final harness = _Harness();
    addTearDown(harness.close);
    await harness.output.initializationFuture;
    final first = harness.output.releaseResources();
    expect(identical(first, harness.output.releaseResources()), isTrue);
    await first;
    final writes = List<String>.of(harness.player.writes);
    harness.disposeNotifier();
    await harness.output.releaseResources();
    expect(harness.player.writes, writes);
  });

  test(
    'early release prevents initialization from starting a new backend',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      await harness.output.releaseResources();
      await harness.output.initializationFuture;
      expect(harness.player.writes, ['transparent=false', 'exclusive=false']);
      expect(harness.calls, ['clearMixer']);
      expect(harness.player.events.errors.hasListener, isFalse);
    },
  );

  test(
    'release drains the active command and cancels queued selections',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      await harness.output.initializationFuture;
      harness.player.reloadGate = Completer<void>();
      final active = harness.output.useAutomatic();
      await harness.player.reloadStarted.future;
      final queued = harness.output.selectDevice(1);
      var released = false;
      final release = harness.output.releaseResources().then(
        (_) => released = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(released, isFalse);
      harness.player.reloadGate!.complete();
      await Future.wait([active, queued, release]);
      expect(harness.player.reloads, 1);
      expect(harness.player.writes, isNot(contains('aaudio-device-id=1')));
      expect(harness.player.writes.sublist(harness.player.writes.length - 2), [
        'transparent=false',
        'exclusive=false',
      ]);
    },
  );
}
