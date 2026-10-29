import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:myune_music/models/audio_output_state.dart';
import 'package:myune_music/services/audio/audio_output_controller.dart';
import 'package:myune_music/services/audio/audio_service.dart';
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
  var driver = 'audiotrack';
  var playing = true;
  var selected = 0;
  var reloads = 0;
  var backendChanges = 0;
  @override
  PlayerStream get stream => events;
  @override
  PlayerState get state => PlayerState(
    playing: playing,
    playWhenReady: playing,
    position: const Duration(seconds: 80),
  );
  @override
  Future<String?> getRawProperty(String name) async => driver;
  @override
  Future<void> setRawProperty(String name, String value) async {
    writes.add('$name=$value');
    if (name == 'ao') {
      driver = value.split(',').first;
      backendChanges++;
    }
    if (name == 'aaudio-device-id') selected = int.parse(value);
  }

  @override
  Future<void> reloadAudio() async => reloads++;
  @override
  Future<void> setAudioExclusive(bool value) async {}
  @override
  Future<void> setAudioClientName(String value) async {}
  @override
  Future<void> setAudioBuffer(Duration value) async {
    writes.add('audio-buffer=${value.inMilliseconds}');
  }

  @override
  Future<void> setVolumeGain(double value) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<void> setTransparentOutput(
    bool value, {
    String format = 'auto',
    int sampleRate = 0,
    String channels = 'auto',
  }) async {}
}

Map<String, Object> _report(_Player player, {List<int> policy = const [2]}) => {
  'sdk': 35,
  'bridgeAvailable': true,
  'routeVerified': player.driver == 'aaudio',
  'stream': player.driver == 'aaudio'
      ? [0, 1, player.selected, 44100, 2, 2, 1, 4]
      : List<int>.filled(18, 0),
  'systemMediaDeviceIds': policy,
  'devices': [
    for (final id in [1, 2])
      {
        'id': id,
        'name': id == 1 ? 'Speaker' : 'Wireless',
        'profileKey': 'endpoint:$id',
        'persistentIdentity': true,
        'directSelectable': true,
      },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('wireless432');
  const events = EventChannel('wireless432-events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _Player player;
  late AudioOutputController output;
  var policy = <int>[2];
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    player = _Player();
    policy = [2];
    messenger.setMockMethodCallHandler(
      MethodChannel(events.name),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'snapshot') return _report(player, policy: policy);
      return null;
    });
    output = AudioOutputController(
      player: player,
      android: true,
      channel: channel,
      events: events,
    );
    await output.initializationFuture;
  });
  tearDown(() async {
    output.dispose();
    await output.releaseResources();
    await player.events.errors.close();
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(MethodChannel(events.name), null);
  });

  test('automatic music output keeps AudioTrack instead of forcing AAudio', () {
    expect(player.driver, 'audiotrack');
    expect(player.writes, contains('ao=audiotrack,opensles'));
    expect(player.reloads, 0);
    expect(player.state.position, const Duration(seconds: 80));
  });

  test(
    'music attributes and existing buffer are ready before opening media',
    () async {
      final service = AudioService(player: player, android: true);
      await service.init();
      expect(player.writes, contains('audio-set-media-role=yes'));
      expect(player.writes, contains('audio-buffer=500'));
      expect(player.reloads, 0);
      await service.dispose();
    },
  );

  test('reselecting healthy automatic output never tears down audio', () async {
    player.driver = 'audiotrack';
    player.writes.clear();
    for (var i = 0; i < 20; i++) {
      await output.useAutomatic();
    }
    expect(player.reloads, 0);
    expect(player.writes, isEmpty);
    player.playing = false;
    await output.useAutomatic();
    expect(player.reloads, 0);
  });

  test(
    'manual route remains verifiable and automatic returns to AudioTrack',
    () async {
      policy = [1];
      await output.refresh();
      await output.selectDevice(2);
      expect(player.driver, 'aaudio');
      expect(output.current?.id, 2);
      expect(player.reloads, 0);
      expect(player.backendChanges, 2);
      await output.useAutomatic();
      expect(player.driver, 'audiotrack');
      expect(output.requestedDeviceId, isNull);
      expect(player.reloads, 0);
      expect(player.backendChanges, 3);
      await output.useAutomatic();
      expect(player.reloads, 0);
      expect(player.backendChanges, 3);
    },
  );

  test(
    'changing explicit devices on the same backend reopens exactly once',
    () async {
      policy = [];
      await output.refresh();
      await output.selectDevice(2);
      await output.selectDevice(1);
      expect(output.current?.id, 1);
      expect(player.reloads, 1);
      expect(player.backendChanges, 2);
      expect(
        player.writes.where((value) => value == 'ao=aaudio'),
        hasLength(1),
      );
      await output.selectDevice(1);
      expect(player.reloads, 1);
    },
  );

  test(
    'selecting the system Bluetooth route retains compatibility output',
    () async {
      player.writes.clear();
      await output.selectDevice(2);
      expect(player.driver, 'audiotrack');
      expect(player.writes, isEmpty);
      expect(player.reloads, 0);
      expect(output.requestedDeviceId, isNull);
      expect(
        output.current,
        isNull,
      ); // Policy never masquerades as actual track.
      expect(output.message, contains('系统媒体路由'));
      expect(output.sync.hasDevice, isTrue);
    },
  );

  test(
    'system policy is never misreported as a verified application stream',
    () {
      final snapshot = AudioOutputSnapshot.fromMap(_report(player));
      expect(snapshot.current, isNull);
      expect(snapshot.routeVerified, isFalse);
      expect(snapshot.exclusiveConfirmed, isFalse);
      expect(output.sync.hasDevice, isTrue);
    },
  );

  test(
    'device compensation follows an unambiguous policy without reloading',
    () async {
      await output.sync.setDevice(180);
      policy = [1];
      await output.refresh();
      expect(output.sync.effectiveDeviceMs, 0);
      policy = [2];
      await output.refresh();
      expect(output.sync.effectiveDeviceMs, 180);
      expect(player.reloads, 0);
      for (var i = 0; i < 250; i++) {
        await output.refresh();
      }
      expect(player.reloads, 0);
    },
  );

  test(
    'unknown or duplicated system routes do not borrow a device profile',
    () async {
      await output.sync.setDevice(180);
      policy = [1, 2];
      await output.refresh();
      expect(output.sync.hasDevice, isFalse);
      expect(output.sync.effectiveDeviceMs, 0);
      policy = [99];
      await output.refresh();
      expect(output.sync.hasDevice, isFalse);
    },
  );

  test(
    'old AAudio errors do not disturb healthy compatibility output',
    () async {
      player.driver = 'audiotrack';
      for (var i = 0; i < 40; i++) {
        player.events.errors.add(
          const MpvLogError(
            prefix: 'ao/aaudio',
            level: LogLevel.error,
            text: 'AAUDIO_ERROR_DISCONNECTED, trying to reload...',
          ),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 1050));
      expect(player.reloads, 0);
    },
  );
}
