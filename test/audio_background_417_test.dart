import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:myune_music/services/audio/audio_output_controller.dart';
import 'package:myune_music/services/audio/audio_output_error_policy.dart';

const disconnect = MpvLogError(
  prefix: 'ao/aaudio',
  level: LogLevel.error,
  text: 'AAUDIO_ERROR_DISCONNECTED, trying to reload...',
);
const failedOpen = MpvLogError(
  prefix: 'ao/aaudio',
  level: LogLevel.error,
  text: 'AAudioStreamBuilder_openStream() returned AAUDIO_ERROR_UNAVAILABLE',
);

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
  String driver = 'aaudio';
  int selected = 0, reloads = 0;
  @override
  PlayerStream get stream => events;
  @override
  PlayerState get state =>
      const PlayerState(playing: true, playWhenReady: true);
  @override
  Future<void> setRawProperty(String name, String value) async {
    writes.add('$name=$value');
    if (name == 'aaudio-device-id') selected = int.parse(value);
    if (name == 'ao') driver = value.split(',').first;
  }

  @override
  Future<String?> getRawProperty(String name) async => driver;
  @override
  Future<void> reloadAudio() async {
    reloads++;
  }

  @override
  Future<void> setAudioExclusive(bool value) async {}
  @override
  Future<void> setTransparentOutput(
    bool value, {
    String format = 'auto',
    int sampleRate = 0,
    String channels = 'auto',
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('background417');
  const events = EventChannel('background417-events');
  late _Player player;
  late AudioOutputController output;
  var available = true;
  Map<String, Object> snapshot() => {
    'bridgeAvailable': true,
    'sdk': 35,
    'routeVerified': player.driver != 'audiotrack',
    'stream': [
      0,
      1,
      player.selected == 0 ? 1 : player.selected,
      44100,
      4,
      2,
      1,
      4,
      0,
      0,
      0,
      0,
      44100,
      4,
      2,
      0,
      8820,
      0,
    ],
    'devices': [
      {
        'id': 1,
        'type': 2,
        'name': 'Speaker',
        'profileKey': 'builtin:2',
        'persistentIdentity': true,
        'directSelectable': true,
      },
      if (available)
        {
          'id': 2,
          'type': 8,
          'name': 'Bluetooth',
          'profileKey': 'endpoint:2',
          'persistentIdentity': true,
          'directSelectable': true,
        },
    ],
  };
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    player = _Player();
    available = true;
    messenger.setMockMethodCallHandler(
      MethodChannel(events.name),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'snapshot' ? snapshot() : null,
    );
    output = AudioOutputController(
      player: player,
      android: true,
      channel: channel,
      events: events,
    );
    await output.initializationFuture;
    player.writes.clear();
  });
  tearDown(() async {
    output.dispose();
    await output.releaseResources();
    await player.events.errors.close();
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(MethodChannel(events.name), null);
  });
  test('recoverable disconnect burst leaves a healthy player alone', () async {
    for (var i = 0; i < 10; i++) {
      player.events.errors.add(disconnect);
    }
    expect(player.reloads, 0);
    await Future<void>.delayed(const Duration(milliseconds: 1050));
    expect(player.reloads, 0);
    expect(player.writes, isEmpty);
    expect(isRecoveringAudioDisconnect(disconnect), isTrue);
  });
  test('codec errors containing audio never trigger output recovery', () async {
    const error = MpvLogError(
      prefix: 'ffmpeg/audio',
      level: LogLevel.error,
      text: 'audio decoder corrupt packet',
    );
    player.events.errors.add(error);
    await Future<void>.delayed(const Duration(milliseconds: 1050));
    expect(player.reloads, 0);
    expect(isAudioOutputFailure(error), isFalse);
  });
  test('failed null output falls back once after settling', () async {
    player.driver = 'null';
    for (var i = 0; i < 10; i++) {
      player.events.errors.add(failedOpen);
    }
    await Future<void>.delayed(const Duration(milliseconds: 1050));
    expect(player.reloads, 1);
    expect(
      player.writes.where((s) => s == 'ao=audiotrack,opensles'),
      hasLength(1),
    );
    expect(output.message, contains('兼容'));
  });
  test('manual device selection cancels an old failure recovery', () async {
    player.driver = 'null';
    player.events.errors.add(disconnect);
    await output.selectDevice(2);
    await Future<void>.delayed(const Duration(milliseconds: 1050));
    expect(output.requestedDeviceId, 2);
    expect(player.reloads, 1);
  });
  test(
    'select switches once and repeated same-device selection is idle',
    () async {
      await output.selectDevice(2);
      expect(player.reloads, 1);
      await output.selectDevice(2);
      expect(player.reloads, 1);
    },
  );
  test(
    'short inventory gaps do not repeatedly tear down a live route',
    () async {
      await output.selectDevice(2);
      available = false;
      await output.refresh();
      available = true;
      await output.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 1050));
      expect(output.requestedDeviceId, 2);
      expect(player.reloads, 1);
    },
  );
  test(
    'a running fallback driver is not reloaded for missing AAudio telemetry',
    () async {
      player.driver = 'audiotrack';
      player.events.errors.add(disconnect);
      await Future<void>.delayed(const Duration(milliseconds: 1050));
      expect(player.reloads, 0);
    },
  );
}
