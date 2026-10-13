import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:myune_music/services/audio/music_effect_policy.dart';

const frequencies = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
const effects = [
  'crossfeed',
  'earwax',
  'widerStereo',
  'haas',
  'vocalBoost',
  'vocalRemover',
  'acompressor',
  'softClip',
  'deNoise',
  'virtualbass',
  'subboost',
  'crystalizer',
  'tilt',
  'vinyl',
  'exciter',
  'echo',
  'deesser',
  'declip',
];
void main() {
  test('overlapping EQ boosts reserve cascade headroom, cuts need none', () {
    final dsp = MusicDspSettings(
      enabled: true,
      gains: List.filled(10, 6),
      frequencies: frequencies,
    );
    expect(dsp.preampDb, lessThan(-10));
    expect(dsp.preampDb, greaterThan(-30));
    expect(dsp.copyWith(gains: List.filled(10, -12)).preampDb, 0);
    expect(dsp.copyWith(gains: List.filled(10, 0)).afChain(''), '');
    expect(dsp.copyWith(sampleRate: 22050).frequency(9), 9922.5);
    expect(dsp.copyWith(gains: List.filled(10, double.nan)).preampDb, 0);
  });
  test('live commands attenuate before boosts and restore after cuts', () {
    final a = MusicDspSettings(
      enabled: true,
      keepAlive: true,
      gains: List.filled(10, 0),
      frequencies: frequencies,
    );
    final b = a.copyWith(gains: List.filled(10, 6));
    final up = b.diff(a, '')!, down = a.diff(b, '')!;
    expect(up.first.filterName, 'biquad@myune_pre');
    expect(down.last.filterName, 'biquad@myune_pre');
    expect(up.where((c) => c.option == 'gain'), hasLength(10));
    expect(up.every((c) => c.label == 'myune_music'), isTrue);
    expect(
      b.copyWith(normalizationGainDb: 6).diff(b, '')!.single.filterName,
      'biquad@myune_output',
    );
  });
  test(
    'effects and normalization precede the single final guard in float graph',
    () {
      const dsp = MusicDspSettings(enabled: true, normalizationGainDb: 6);
      final graph = dsp.filterGraph(
        musicEffectPolicy(const AudioEffects(), 'softClip', true).toAfChain(),
      );
      expect(graph, startsWith('aformat=sample_fmts=fltp'));
      expect(graph.split(',').last, startsWith('alimiter@myune_guard='));
      expect('alimiter@'.allMatches(graph), hasLength(1));
      expect(
        graph.indexOf('asoftclip@'),
        lessThan(graph.indexOf('biquad@myune_output')),
      );
      expect(
        dsp.afChain('').split('%')[1],
        utf8.encode(dsp.filterGraph('')).length.toString(),
      );
    },
  );
  test('export actual production graphs for offline native validation', () {
    final destination = Platform.environment['MYUNE_DSP_GRAPH_OUTPUT'];
    final records = <String, Map<String, String>>{};
    final boost = MusicDspSettings(
      enabled: true,
      gains: List.filled(10, 6),
      frequencies: frequencies,
    );
    void record(String name, MusicDspSettings dsp, AudioEffects e) {
      records[name] = {
        'graph': dsp.filterGraph(e.toAfChain()),
        'af': dsp.afChain(e.toAfChain()),
      };
    }

    record('eq', boost, const AudioEffects());
    for (final id in effects) {
      record(
        id,
        const MusicDspSettings(enabled: true),
        musicEffectPolicy(const AudioEffects(), id, true),
      );
    }
    record(
      'eq_norm',
      boost.copyWith(normalizationGainDb: 12),
      const AudioEffects(),
    );
    for (final id in ['crystalizer', 'subboost', 'exciter', 'acompressor']) {
      record(
        'eq_$id',
        boost,
        musicEffectPolicy(const AudioEffects(), id, true),
      );
    }
    if (destination != null) {
      File(destination).writeAsStringSync(jsonEncode(records));
    }
    expect(records, hasLength(24));
  });
}
