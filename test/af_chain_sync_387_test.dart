import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/src/dsp/af_chain_write.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

void main() {
  test(
    'late full-write reply keeps newer EQ and normalization armed for reload',
    () async {
      final old = MusicDspSettings(
        enabled: true,
        gains: List.filled(10, 6),
        frequencies: const [
          31,
          62,
          125,
          250,
          500,
          1000,
          2000,
          4000,
          8000,
          16000,
        ],
      );
      var current = old;
      var stale = false;
      final response = Completer<int>();
      final pending = synchronizeAfChain(
        chain: old.afChain(''),
        write: (_) => response.future,
        currentChain: () => current.afChain(''),
        markStale: (v) => stale = v,
        rejection: (rc) => StateError('$rc'),
      );
      expect(stale, isTrue);
      current = old.copyWith(gains: List.filled(10, 3), normalizationGainDb: 4);
      response.complete(0);
      await pending;
      expect(
        stale,
        isTrue,
        reason: 'old native reply cannot mark newer parameters synchronized',
      );
      String? written;
      await synchronizeAfChain(
        chain: current.afChain(''),
        write: (chain) async {
          written = chain;
          return 0;
        },
        currentChain: () => current.afChain(''),
        markStale: (v) => stale = v,
        rejection: (rc) => StateError('$rc'),
      );
      expect(written, current.afChain(''));
      expect(stale, isFalse);
    },
  );
  test(
    'rejected and throwing native writes keep reload recovery armed',
    () async {
      for (final throwing in [false, true]) {
        var stale = false;
        final result = synchronizeAfChain(
          chain: 'new',
          write: (_) async {
            if (throwing) throw StateError('native transport closed');
            return -12;
          },
          currentChain: () => 'new',
          markStale: (v) => stale = v,
          rejection: (rc) => StateError('$rc'),
        );
        await expectLater(result, throwsStateError);
        expect(stale, isTrue);
      }
    },
  );
}
