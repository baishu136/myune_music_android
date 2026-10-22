import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

void main() {
  test(
    'boosts no longer reduce input volume while normalization stays independent',
    () {
      const flat = MusicDspSettings(
        enabled: true,
        keepAlive: true,
        gains: [0, 0],
        frequencies: [1000, 2000],
      );
      final boost = flat.copyWith(gains: [12, 12]);
      expect(boost.filterGraph(''), isNot(contains('myune_pre')));
      expect(
        boost.diff(flat, '')!.map((c) => c.filterName),
        everyElement(isNot('biquad@myune_pre')),
      );
      expect(
        boost.filterGraph(''),
        contains('alimiter@myune_guard=limit=1:level=false'),
      );
      expect(
        boost.copyWith(normalizationGainDb: -6).filterGraph(''),
        contains('biquad@myune_output=b0=0.501187234'),
      );
    },
  );
}
