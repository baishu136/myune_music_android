import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:myune_music/services/audio/audio_service.dart';
import 'package:myune_music/services/audio/music_effect_policy.dart';

const _bands = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
const _pop = [1.0, 2.0, 3.0, 2.0, 0.0, -1.0, 0.0, 2.0, 3.0, 2.0];

class _Events extends Fake implements PlayerStream {
  @override
  Stream<AudioParams> get audioParams => const Stream.empty();
}

class _Player extends Fake implements PlayerApi {
  var dsp = const MusicDspSettings();
  final updates = <MusicDspSettings>[];
  @override
  PlayerState get state => const PlayerState();
  @override
  PlayerStream get stream => _Events();
  @override
  MusicDspSettings get musicDsp => dsp;
  @override
  Future<void> updateMusicDsp(
    MusicDspSettings Function(MusicDspSettings) update,
  ) async {
    dsp = update(dsp);
    updates.add(dsp);
  }

  @override
  Future<void> setRawProperty(String name, String value) async {}
  @override
  Future<void> setAudioClientName(String value) async {}
  @override
  Future<void> setAudioBuffer(Duration value) async {}
  @override
  Future<void> setVolumeGain(double value) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  test(
    'Android bounds DSP workers before EQ without activating a filter',
    () async {
      final player = _Player();
      final service = AudioService(player: player, android: true);
      await service.init();
      expect(player.dsp.afChain(''), isEmpty);
      await service.applyEqualizer(gains: _pop, frequencies: _bands);
      expect(player.dsp.afChain(''), contains('lavfi=o=[threads=1]:graph='));
      expect(player.dsp.gains, _pop);
      expect(player.dsp.outputDb, 0);
      expect(
        player.dsp.filterGraph(''),
        const MusicDspSettings(
          enabled: true,
          gains: _pop,
          frequencies: _bands,
        ).filterGraph(''),
      );
      await service.dispose();
    },
  );

  test(
    'worker policy survives gain and EQ updates without changing the graph',
    () async {
      final player = _Player();
      final service = AudioService(player: player, android: true);
      await service.init();
      await service.applyEqualizer(gains: _pop, frequencies: _bands);
      await service.setNormalizationGain(-3, smooth: false);
      await service.applyEqualizer(
        gains: List.filled(10, 2),
        frequencies: _bands,
      );
      expect(player.dsp.afChain(''), contains('lavfi=o=[threads=1]:graph='));
      expect(player.dsp.outputDb, -3);
      expect(player.dsp.gains, List.filled(10, 2));
      expect(player.dsp.copyWith(enabled: false).afChain(''), isEmpty);
      expect(
        player.dsp.copyWith(enabled: false).copyWith(enabled: true).afChain(''),
        player.dsp.afChain(''),
      );
      await service.dispose();
    },
  );

  test('other platforms keep their existing automatic threading', () async {
    final player = _Player();
    final service = AudioService(player: player, android: false);
    await service.applyEqualizer(gains: _pop, frequencies: _bands);
    expect(player.dsp.afChain(''), startsWith('@myune_music:lavfi=graph='));
    await service.dispose();
  });

  test(
    'thread changes rebuild only active graphs, live EQ commands stay live',
    () {
      const original = MusicDspSettings(
        enabled: true,
        gains: _pop,
        frequencies: _bands,
      );
      final single = original.copyWith(filterThreads: 1);
      expect(single.diff(original, ''), isNull);
      expect(single.copyWith(filterThreads: 0).diff(single, ''), isNull);
      final moved = single.copyWith(gains: [2, ..._pop.skip(1)]);
      final commands = moved.diff(single, '')!;
      expect(commands, hasLength(1));
      expect(commands.single.filterName, 'equalizer@myune_eq_0');
      const idle = MusicDspSettings();
      expect(idle.copyWith(filterThreads: 1).diff(idle, ''), isEmpty);
      expect(idle.copyWith(filterThreads: 1).afChain(''), '');
      expect(single.copyWith(filterThreads: -1).threads, 0);
      expect(single.copyWith(filterThreads: 1000).threads, 32);
    },
  );

  test('export actual scheduling variants for native PCM comparison', () {
    final records = <String, Object>{};
    for (final rate in [44100, 96000]) {
      final base = MusicDspSettings(
        enabled: true,
        gains: _pop,
        frequencies: _bands,
        sampleRate: rate,
      );
      final effects = musicEffectPolicy(
        musicEffectPolicy(const AudioEffects(), 'widerStereo', true),
        'acompressor',
        true,
      ).toAfChain();
      for (final name in ['pop', 'gain', 'effects']) {
        final dsp = name == 'gain'
            ? base.copyWith(normalizationGainDb: -3)
            : base;
        final fx = name == 'effects' ? effects : '';
        final threaded = dsp.copyWith(filterThreads: 1);
        final wire = threaded.afChain(fx);
        final graph = threaded.filterGraph(fx);
        expect(wire.split('%')[1], utf8.encode(graph).length.toString());
        expect(graph, dsp.filterGraph(fx));
        records['${rate}_$name'] = {
          'rate': rate,
          'auto': dsp.afChain(fx),
          'single': wire,
        };
      }
    }
    final destination = Platform.environment['MYUNE_DSP433_OUTPUT'];
    if (destination != null) {
      File(destination).writeAsStringSync(jsonEncode(records));
    }
    expect(records, hasLength(6));
  });
}
