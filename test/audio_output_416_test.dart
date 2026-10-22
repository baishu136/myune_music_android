import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:myune_music/models/audio_output_state.dart';
import 'package:myune_music/services/audio/audio_output_controller.dart';
import 'package:myune_music/services/lyric_sync_preferences.dart';
import 'package:myune_music/services/lyric_visual_timeline.dart';
import 'package:myune_music/page/setting/audio_output_page.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';

class _OutputPlaylist extends ChangeNotifier
    implements PlaylistContentNotifier {
  _OutputPlaylist(this.audioOutput);
  @override
  final AudioOutputController audioOutput;
  @override
  List<LyricLine> get currentLyrics => const [];
  @override
  Song? get currentSong => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Streams extends Fake implements PlayerStream {
  final params = StreamController<AudioParams>.broadcast();
  @override
  Stream<AudioParams> get audioParams => params.stream;
  @override
  Stream<MpvPlayerError> get error => const Stream.empty();
}

class _Player extends Fake implements PlayerApi {
  final events = _Streams();
  final writes = <String>[];
  var current = const PlayerState(
    playWhenReady: true,
    playing: true,
    audioParams: AudioParams(
      format: Format.s16,
      sampleRate: 44100,
      channelCount: 2,
    ),
  );
  int requested = 1;
  bool transparent = false, exclusive = false;
  @override
  PlayerState get state => current;
  @override
  PlayerStream get stream => events;
  @override
  Future<void> setRawProperty(String name, String value) async {
    writes.add('$name=$value');
    if (name == 'aaudio-device-id') requested = int.parse(value);
  }

  @override
  Future<void> setTransparentOutput(
    bool value, {
    String format = 'auto',
    int sampleRate = 0,
    String channels = 'auto',
  }) async {
    transparent = value;
  }

  @override
  Future<void> setAudioExclusive(bool value) async {
    exclusive = value;
  }

  @override
  Future<void> reloadAudio() async {
    writes.add('reload');
  }

  @override
  Future<String?> getRawProperty(String name) async => {
    'af': '',
    'volume': '100',
    'volume-gain': '0',
    'speed': '1',
    'pitch': '1',
    'replaygain': 'no',
  }[name];
}

Map<String, Object?> report({
  int current = 1,
  int sharing = 1,
  bool mixer = false,
  bool hardware = true,
}) {
  final values = List<int>.filled(18, 0);
  values[1] = 1;
  values[2] = current;
  values[3] = 44100;
  values[4] = 1;
  values[5] = 2;
  values[6] = sharing;
  values[7] = 4;
  if (hardware) {
    values[12] = 44100;
    values[13] = 1;
    values[14] = 2;
  }
  return {
    'sdk': 35,
    'bridgeAvailable': true,
    'routeVerified': true,
    'mixerConfirmed': mixer,
    'stream': values,
    'devices': [
      for (final id in [1, 20, 30])
        {
          'id': id,
          'name': id == 1
              ? '扬声器'
              : id == 20
              ? '同名耳机'
              : 'USB DAC',
          'profileKey': 'device-$id',
          'persistentIdentity': id != 30,
          'usb': id == 30,
          'directSelectable': true,
          'sampleRates': [44100, 48000],
          'mixerFormats': id == 30
              ? [
                  {
                    'bitPerfect': true,
                    'format': {
                      'sampleRate': 44100,
                      'encoding': 2,
                      'channels': 2,
                    },
                  },
                ]
              : [],
        },
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'long running projection stays bounded through jitter, pause, rate and seeks',
    () {
      final timeline = LyricVisualTimeline();
      var mediaUs = 0;
      for (var frame = 0; frame < 60000; frame++) {
        final running = frame % 4000 < 3900;
        final rate = frame % 6000 < 3000 ? 1.0 : 1.75;
        if (running) mediaUs += (20000 * rate).round();
        if (frame % 10000 == 0) {
          mediaUs = 1000000;
          timeline.reset();
        }
        final raw = Duration(
          microseconds: mediaUs + (running ? (frame.isEven ? -5000 : 5000) : 0),
        );
        final visual = timeline.sample(
          raw,
          Duration(microseconds: frame * 20000),
          running: running,
          rate: rate,
          automatic: true,
        );
        expect((visual - raw).inMicroseconds.abs(), lessThan(120000));
        if (!running) expect(visual, raw);
      }
    },
  );
  test(
    'same-name devices never share a profile and malformed settings preserve playback',
    () async {
      SharedPreferences.setMockInitialValues({
        LyricSyncPreferences.key: '{broken',
      });
      final sync = LyricSyncPreferences();
      await sync.initializationFuture;
      sync.useDevice('connection:A', persistent: false);
      await sync.setDevice(180);
      sync.useDevice('connection:B', persistent: false);
      expect(sync.effectiveDeviceMs, 0);
      await sync.setDevice(-260);
      sync.useDevice('connection:A', persistent: false);
      expect(sync.effectiveDeviceMs, 180);
      await sync.setGlobal(-1000);
      await sync.setDevice(null);
      expect(sync.visualPosition(Duration.zero), const Duration(seconds: 1));
      await sync.reset();
      expect(sync.effectiveDeviceMs, 0);
      sync.dispose();
    },
  );
  test(
    'buffer reports are diagnostic only and ambiguous streams never verify a route',
    () async {
      final data = report();
      final stream = data['stream'] as List<int>;
      stream[8] = 8820;
      stream[9] = 2205;
      stream[10] = 1000000000;
      stream[11] = 1050000000;
      final snapshot = AudioOutputSnapshot.fromMap(data);
      expect(snapshot.localQueuedAudio, const Duration(milliseconds: 100));
      final sync = LyricSyncPreferences();
      await sync.initializationFuture;
      expect(
        sync.visualPosition(const Duration(seconds: 1)),
        const Duration(seconds: 1),
      );
      stream[1] = 2;
      expect(AudioOutputSnapshot.fromMap(data).current, isNull);
      sync.dispose();
    },
  );
  testWidgets(
    'output calibration uses real inventory, integer offsets and fits large text',
    (tester) async {
      const channel = MethodChannel('output-ui-416');
      const events = EventChannel('output-ui-events-416');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        MethodChannel(events.name),
        (_) async => null,
      );
      messenger.setMockMethodCallHandler(channel, (_) async => report());
      late AudioOutputController output;
      late SettingsProvider settings;
      await tester.runAsync(() async {
        output = AudioOutputController(
          player: _Player(),
          android: true,
          channel: channel,
          events: events,
        );
        settings = SettingsProvider();
        await Future.wait([
          output.initializationFuture,
          settings.initializationFuture,
        ]);
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final playlist = _OutputPlaylist(output);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PlaylistContentNotifier>.value(
              value: playlist,
            ),
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ],
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(320, 800),
                textScaler: TextScaler.linear(2),
              ),
              child: AudioOutputPage(),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('扬声器'), findsOneWidget);
      expect(find.textContaining('实际输出中'), findsOneWidget);
      expect(find.text('USB 输出模式'), findsNothing);
      await tester.scrollUntilVisible(find.text('全局默认'), 250);
      final slider = tester.widget<Slider>(find.byType(Slider).first);
      expect(slider.divisions, 4000);
      await tester.runAsync(() async {
        slider.onChanged!(180);
      });
      await tester.pump();
      expect(output.sync.effectiveDeviceMs, 180);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      output.dispose();
      await tester.runAsync(output.releaseResources);
      settings.dispose();
      playlist.dispose();
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(MethodChannel(events.name), null);
    },
  );
  test(
    'device delay uses wall time, song offset is independent and inverse seek is exact',
    () async {
      final sync = LyricSyncPreferences();
      await sync.initializationFuture;
      await sync.setGlobal(50);
      sync.useDevice('one', persistent: true);
      await sync.setDevice(180);
      sync.useSong('A.mp3');
      await sync.setSong(30);
      expect(
        sync.visualPosition(const Duration(seconds: 1), rate: 2),
        const Duration(milliseconds: 610),
      );
      expect(
        sync.mediaPosition(const Duration(milliseconds: 610), rate: 2),
        const Duration(seconds: 1),
      );
      sync.useDevice('two', persistent: true);
      await sync.setDevice(260);
      sync.useDevice('one', persistent: true);
      expect(sync.effectiveDeviceMs, 180);
      sync.useDevice('anonymous-connection', persistent: false);
      await sync.setDevice(90);
      final restored = LyricSyncPreferences();
      await restored.initializationFuture;
      restored.useDevice('one', persistent: true);
      expect(restored.effectiveDeviceMs, 180);
      restored.useDevice('two', persistent: true);
      expect(restored.effectiveDeviceMs, 260);
      restored.useDevice('anonymous-connection', persistent: false);
      expect(restored.effectiveDeviceMs, 50);
      restored.useSong('a.mp3');
      expect(restored.songDelayMs, 30);
      sync.dispose();
      restored.dispose();
    },
  );
  test(
    'timeline remains monotone with native jitter, snaps seeks and freezes pause',
    () {
      final timeline = LyricVisualTimeline();
      var previous = Duration.zero;
      for (var i = 1; i <= 500; i++) {
        final source = Duration(milliseconds: i * 20 + (i.isEven ? -7 : 7));
        final value = timeline.sample(
          source,
          Duration(milliseconds: i * 20),
          running: true,
          rate: 1,
          automatic: true,
        );
        expect(value, greaterThanOrEqualTo(previous));
        expect((value - source).inMilliseconds.abs(), lessThan(100));
        previous = value;
      }
      timeline.reset();
      expect(
        timeline.sample(
          const Duration(milliseconds: 100),
          const Duration(seconds: 11),
          running: true,
          rate: 1,
          automatic: true,
        ),
        const Duration(milliseconds: 100),
      );
      expect(
        timeline.sample(
          const Duration(milliseconds: 100),
          const Duration(seconds: 12),
          running: false,
          rate: 1,
          automatic: true,
        ),
        const Duration(milliseconds: 100),
      );
      expect(
        timeline.sample(
          const Duration(seconds: 2),
          const Duration(seconds: 13),
          running: true,
          rate: 2,
          automatic: false,
        ),
        const Duration(seconds: 2),
      );
    },
  );
  test(
    'mixer preference without actual hardware match never confirms Bit-Perfect',
    () {
      const format = OutputPcmFormat(44100, 2, 2, bitPerfect: true);
      expect(
        AudioOutputSnapshot.fromMap(
          report(current: 30, mixer: true),
        ).matches(format),
        isTrue,
      );
      expect(
        AudioOutputSnapshot.fromMap(
          report(current: 30, mixer: true, hardware: false),
        ).matches(format),
        isFalse,
      );
      expect(
        AudioOutputSnapshot.fromMap(
          report(current: 20, mixer: true, sharing: 0),
        ).exclusiveConfirmed,
        isFalse,
      );
      expect(
        AudioOutputSnapshot.fromMap(report(current: 30)).exclusiveConfirmed,
        isFalse,
      );
      expect(const OutputPcmFormat(44100, 21, 2).mpvFormat, isNull);
    },
  );
  Future<void> scenario(
    WidgetTester tester, {
    required bool routeAllowed,
    required bool exclusiveAllowed,
  }) async {
    final channel = MethodChannel(
      'output-test-${routeAllowed ? 1 : 0}-${exclusiveAllowed ? 1 : 0}',
    );
    final events = EventChannel('${channel.name}-events');
    final player = _Player();
    var mixer = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      MethodChannel(events.name),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'clearMixer') {
        mixer = false;
        return true;
      }
      if (call.method == 'requestMixer') {
        mixer = true;
      }
      return report(
        current: routeAllowed
            ? (player.requested == 0 ? 1 : player.requested)
            : 1,
        sharing: player.exclusive && exclusiveAllowed ? 0 : 1,
        mixer: mixer,
      );
    });
    await tester.runAsync(() async {
      final output = AudioOutputController(
        player: player,
        android: true,
        channel: channel,
        events: events,
      );
      await output.initializationFuture;
      await output.selectDevice(30);
      if (routeAllowed) {
        expect(output.current?.id, 30);
        await output.setMode(AudioOutputMode.bitPerfect);
        expect(player.transparent, isTrue);
        expect(output.bitPerfectReported, isTrue);
        await output.setMode(AudioOutputMode.exclusive);
        expect(output.exclusiveReported, exclusiveAllowed);
        if (!exclusiveAllowed) expect(output.mode, AudioOutputMode.standard);
      } else {
        expect(output.current?.id, 1);
        expect(output.requestedDeviceId, isNull);
        expect(output.message, contains('未完成'));
      }
      await output.useAutomatic();
      expect(output.mode, AudioOutputMode.standard);
      expect(player.transparent, isFalse);
      expect(player.exclusive, isFalse);
      output.dispose();
      await output.releaseResources();
      await player.events.params.close();
    });
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(MethodChannel(events.name), null);
  }

  testWidgets(
    'actual route and exclusive replies determine success',
    (tester) => scenario(tester, routeAllowed: true, exclusiveAllowed: true),
  );
  testWidgets(
    'shared reply to exclusive request safely restores normal output',
    (tester) => scenario(tester, routeAllowed: true, exclusiveAllowed: false),
  );
  testWidgets(
    'accepted routing request without real route change reports failure',
    (tester) => scenario(tester, routeAllowed: false, exclusiveAllowed: false),
  );
}
