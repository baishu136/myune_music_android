import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:myune_music/services/audio/audio_service.dart';
import 'music_dsp_387_test.dart' as fixture;

class _Stream extends Fake implements PlayerStream {
  final params = StreamController<AudioParams>.broadcast();
  @override
  Stream<AudioParams> get audioParams => params.stream;
}

class _Player extends Fake implements PlayerApi {
  final events = _Stream();
  var current = const PlayerState(playing: true);
  var dsp = const MusicDspSettings();
  final history = <MusicDspSettings>[];
  final rewrites = <String>[];
  final aoGains = <double>[];
  bool disposed = false;
  @override
  PlayerState get state => current;
  @override
  PlayerStream get stream => events;
  @override
  MusicDspSettings get musicDsp => dsp;
  @override
  Future<void> updateMusicDsp(
    MusicDspSettings Function(MusicDspSettings) mapper,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    if (disposed) throw StateError('write after disposal');
    final next = mapper(dsp), chain = current.audioEffects.toAfChain();
    if (next.diff(dsp, chain) == null) rewrites.add(next.afChain(chain));
    dsp = next;
    history.add(next);
  }

  @override
  Future<void> updateAudioEffects(
    AudioEffects Function(AudioEffects) mapper,
  ) async {
    current = current.copyWith(audioEffects: mapper(current.audioEffects));
  }

  @override
  Future<void> setVolumeGain(double gainDb) async {
    aoGains.add(gainDb);
  }

  @override
  Future<void> setAudioClientName(String name) async {}
  @override
  Future<void> setRawProperty(String name, String value) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {
    disposed = true;
    await events.params.close();
  }
}

void main() {
  test(
    'burst EQ previews converge to latest target without repeated chain rebuilds',
    () async {
      final p = _Player();
      final audio = AudioService(player: p);
      await audio.applyEqualizer(
        gains: List.filled(10, 0),
        frequencies: fixture.frequencies,
      );
      final count = p.history.length;
      final a = audio.applyEqualizer(
        gains: List.filled(10, 12),
        frequencies: fixture.frequencies,
      );
      await Future<void>.delayed(const Duration(milliseconds: 3));
      final b = audio.applyEqualizer(
        gains: List.filled(10, -8),
        frequencies: fixture.frequencies,
      );
      final c = audio.applyEqualizer(
        gains: List.filled(10, 3),
        frequencies: fixture.frequencies,
      );
      await Future.wait([a, b, c]);
      expect(p.dsp.gains, List.filled(10, 3));
      final samples = p.history.sublist(count);
      for (var i = 1; i < samples.length; i++) {
        expect(
          (samples[i].gain(0) - samples[i - 1].gain(0)).abs(),
          lessThanOrEqualTo(1),
        );
      }
      expect(p.rewrites.where((s) => s.isNotEmpty), hasLength(1));
      await audio.dispose();
    },
  );
  test(
    'normalization and EQ updates preserve each other and avoid AO boosts',
    () async {
      final p = _Player();
      final audio = AudioService(player: p);
      await audio.applyEqualizer(
        gains: List.filled(10, 0),
        frequencies: fixture.frequencies,
      );
      await Future.wait([
        audio.applyEqualizer(
          gains: List.filled(10, 6),
          frequencies: fixture.frequencies,
        ),
        audio.setNormalizationGain(9),
      ]);
      expect(p.dsp.gains, List.filled(10, 6));
      expect(p.dsp.outputDb, 9);
      expect(p.aoGains, [0]);
      await audio.setNormalizationGain(0);
      expect(p.dsp.gains, List.filled(10, 6));
      await audio.dispose();
    },
  );
  test('effects enable the guarded graph even before first EQ setup', () async {
    final p = _Player();
    final audio = AudioService(player: p);
    await audio.applyEffect('acompressor', true);
    expect(p.dsp.enabled, isTrue);
    expect(
      p.dsp.afChain(p.state.audioEffects.toAfChain()),
      contains('myune_guard'),
    );
    await audio.dispose();
  });
}
