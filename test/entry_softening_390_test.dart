import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'music_dsp_387_test.dart' as fixture;

void main() {
  test(
    'entry-only slot keeps unity peak protection without full EQ processing',
    () {
      const tone = MusicDspSettings(
        enabled: true,
        entrySofteningEnabled: true,
        entrySofteningDb: -6,
      );
      expect(
        tone.filterGraph(''),
        contains('treble@myune_entry=g=-6.000000000'),
      );
      expect(tone.filterGraph(''), contains('myune_guard=limit=1:level=false'));
      expect('alimiter@'.allMatches(tone.filterGraph('')), hasLength(1));
      expect(tone.filterGraph(''), isNot(contains('myune_eq_')));
      expect(tone.copyWith(entrySofteningDb: 0).afChain(''), isNotEmpty);
      expect(tone.copyWith(entrySofteningDb: 4).entryDb, 0);
      expect(tone.copyWith(entrySofteningDb: -100).entryDb, -6);
      expect(tone.copyWith(sampleRate: 8000).entryFrequency, 3200);
    },
  );
  test(
    'live recovery writes only shelf gain while preserving EQ and normalization',
    () {
      final tone = MusicDspSettings(
        enabled: true,
        entrySofteningEnabled: true,
        entrySofteningDb: -6,
        gains: List.filled(10, 6),
        frequencies: fixture.frequencies,
        normalizationGainDb: 3,
      );
      final next = tone.copyWith(entrySofteningDb: -3);
      final command = next.diff(tone, '')!.single;
      expect(command.filterName, 'treble@myune_entry');
      expect(command.option, 'gain');
      expect(command.value, '-3.000000000');
      expect(identical(next.gains, tone.gains), isTrue);
      expect(next.outputDb, 3);
      expect(
        next.filterGraph('').split(',').last,
        startsWith('alimiter@myune_guard='),
      );
      expect(
        tone.copyWith(entrySofteningEnabled: false).diff(tone, ''),
        isNull,
      );
    },
  );
  test(
    'EQ activation and sample-rate changes update the right graph and shelf frequency',
    () {
      const neutral = MusicDspSettings(
        enabled: true,
        entrySofteningEnabled: true,
      );
      final eq = neutral.copyWith(gains: [6], frequencies: [1000]);
      expect(eq.diff(neutral, ''), isNull);
      final lowRate = neutral.copyWith(sampleRate: 8000);
      expect(lowRate.diff(neutral, '')!.single.option, 'frequency');
      expect(lowRate.diff(neutral, '')!.single.value, '3200.000000000');
    },
  );
  test(
    'export actual shelf and combined DSP graphs for offline response checks',
    () {
      final graphs = <String, Map<String, Object>>{};
      for (final rate in [8000, 44100, 48000, 96000]) {
        for (final db in [-6.0, -3.0, 0.0]) {
          final tone = MusicDspSettings(
            enabled: true,
            entrySofteningEnabled: true,
            entrySofteningDb: db,
            sampleRate: rate,
          );
          graphs['$rate-$db'] = {
            'graph': tone.filterGraph(''),
            'af': tone.afChain(''),
            'rate': rate,
            'db': db,
          };
        }
      }
      for (final db in [-6.0, 0.0]) {
        final tone = MusicDspSettings(
          enabled: true,
          entrySofteningEnabled: true,
          entrySofteningDb: db,
          gains: List.filled(10, 6),
          frequencies: fixture.frequencies,
          normalizationGainDb: 6,
        );
        graphs['eq-$db'] = {
          'graph': tone.filterGraph(''),
          'af': tone.afChain(''),
          'rate': 48000,
          'db': db,
        };
      }
      final destination = Platform.environment['MYUNE_ENTRY_GRAPH_OUTPUT'];
      if (destination != null) {
        File(destination).writeAsStringSync(jsonEncode(graphs));
      }
      expect(graphs, hasLength(14));
    },
  );
}
