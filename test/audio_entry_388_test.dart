import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:myune_music/services/audio/audio_service.dart';

class _Stream extends Fake implements PlayerStream {
  final actual = StreamController<bool>.broadcast();
  @override
  Stream<bool> get playing => actual.stream;
  @override
  Stream<AudioParams> get audioParams => const Stream.empty();
}

class _Player extends Fake implements PlayerApi {
  final events = _Stream();
  var current = const PlayerState(playing: false, volume: 72);
  var dsp = const MusicDspSettings();
  final dspWrites = <MusicDspSettings>[];
  bool rejectEntry = false;
  final gains = <double>[];
  final opens = <bool?>[];
  bool failPlay = false;
  Completer<void>? pauseReply;
  @override
  PlayerStream get stream => events;
  @override
  PlayerState get state => current;
  @override
  MusicDspSettings get musicDsp => dsp;
  @override
  Future<void> setAudioClientName(String name) async {}
  @override
  Future<void> setRawProperty(String name, String value) async {}
  @override
  Future<void> setVolumeGain(double gainDb) async => gains.add(gainDb);
  @override
  Future<void> setPitch(double value) async {}
  @override
  Future<void> setRate(double value) async {}
  @override
  Future<void> setAudioExclusive(bool value) async {}
  @override
  Future<void> updateMusicDsp(
    MusicDspSettings Function(MusicDspSettings) mapper,
  ) async {
    final next = mapper(dsp);
    if (rejectEntry && next.entrySofteningEnabled) {
      throw StateError('unsupported tone filter');
    }
    dsp = next;
    dspWrites.add(next);
  }

  @override
  Future<void> open(Media media, {bool? play}) async {
    opens.add(play);
    actual(false);
  }

  @override
  Future<void> openAll(List<Media> media, {int index = 0, bool? play}) async {
    opens.add(play);
    actual(false);
  }

  void actual(bool value) {
    current = current.copyWith(playing: value);
    events.actual.add(value);
  }

  @override
  Future<void> play() async {
    if (failPlay) throw StateError('load failed');
  }

  @override
  Future<void> pause() async {
    actual(false);
    await pauseReply?.future;
  }

  @override
  Future<void> stop() async => actual(false);
  @override
  Future<void> dispose() => events.actual.close();
}

void main() {
  Future<void> load(
    AudioService audio, {
    bool gapless = false,
    bool play = true,
  }) {
    final gains = List<double>.filled(10, 0),
        frequencies = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
    return gapless
        ? audio.playSongGapless(
            'track.wav',
            nextPath: 'next.wav',
            pitch: 1,
            rate: 1,
            eqGains: gains,
            eqFrequencies: frequencies,
            play: play,
          )
        : audio.playSong(
            'track.wav',
            pitch: 1,
            rate: 1,
            eqGains: gains,
            eqFrequencies: frequencies,
            play: play,
          );
  }

  test(
    'both load paths stay paused until prepared and wait for actual audio',
    () async {
      for (final gapless in [false, true]) {
        final player = _Player();
        final service = AudioService(player: player);
        await load(service, gapless: gapless);
        expect(player.opens, [false]);
        expect(player.gains, [0]);
        expect(player.dsp.entryDb, -6);
        await Future<void>.delayed(const Duration(milliseconds: 520));
        expect(player.gains, [0]);
        expect(player.dsp.entryDb, -6);
        player.actual(true);
        await Future<void>.delayed(const Duration(milliseconds: 560));
        expect(player.gains.last, 0);
        expect(player.dsp.entryDb, 0);
        expect(player.current.volume, 72);
        expect(player.dsp.gains, List.filled(10, 0));
        await service.dispose();
      }
    },
  );
  test(
    'old pause reply cannot restore unity during a newer resume fade',
    () async {
      final player = _Player();
      final audio = AudioService(player: player);
      await audio.init();
      player.pauseReply = Completer<void>();
      final paused = audio.pause();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await audio.play();
      expect(player.gains, [0]);
      expect(player.dsp.entryDb, -6);
      player.pauseReply!.complete();
      await paused;
      expect(player.gains, [0]);
      expect(player.dsp.entryDb, -6);
      player.actual(true);
      await Future<void>.delayed(const Duration(milliseconds: 540));
      expect(player.gains.last, 0);
      await audio.dispose();
    },
  );
  test(
    'play failure and paused load restore unity; disposal leaves no gain writes',
    () async {
      final player = _Player();
      final audio = AudioService(player: player);
      await load(audio, play: false);
      expect(player.gains.last, 0);
      player.failPlay = true;
      await expectLater(audio.play(), throwsStateError);
      expect(player.gains.last, 0);
      await audio.dispose();
      final count = player.dspWrites.length;
      await Future<void>.delayed(const Duration(milliseconds: 520));
      expect(player.dspWrites.length, count);
    },
  );
  test(
    'unsupported tone filter falls back without keeping muffling or lowering volume',
    () async {
      final player = _Player()..rejectEntry = true;
      final audio = AudioService(player: player);
      await load(audio);
      expect(player.dsp.entrySofteningEnabled, isFalse);
      expect(player.dsp.entryDb, 0);
      expect(player.gains, [0]);
      await audio.dispose();
    },
  );
  test(
    'EQ and normalization updates during recovery keep both user settings',
    () async {
      final player = _Player();
      final audio = AudioService(player: player);
      await load(audio);
      await audio.applyEqualizer(
        gains: List.filled(10, 6),
        frequencies: [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000],
      );
      await audio.setNormalizationGain(3);
      player.actual(true);
      await Future<void>.delayed(const Duration(milliseconds: 540));
      expect(player.dsp.entryDb, 0);
      expect(player.dsp.gains, List.filled(10, 6));
      expect(player.dsp.outputDb, 3);
      expect(player.gains, [0]);
      expect(player.current.volume, 72);
      await audio.dispose();
    },
  );
}
