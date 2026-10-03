import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/karaoke_sweep_timeline.dart';

void main() {
  for (final hz in [60, 90, 120]) {
    test('equal Chinese cadence has no boundary slowdown at $hz Hz', () {
      final timeline = KaraokeSweepTimeline([
        for (var i = 0; i < 8; i++)
          (startUs: i * 250000, endUs: (i + 1) * 250000, advance: 30.0),
      ]);
      var previous = 0.0;
      for (var frame = 1; frame <= hz * 2; frame++) {
        final time = (frame * 1000000 / hz).round();
        final phase = timeline.phaseAt(time);
        expect(phase, closeTo(time / 2000000, .000001));
        expect(phase - previous, closeTo(1 / (hz * 2), .000001));
        expect(
          timeline.phaseAt(time),
          phase,
          reason: 'seek and continuous playback use the same function',
        );
        previous = phase;
      }
    });
    test('mixed cadence stays monotonic without empty frames at $hz Hz', () {
      final timeline = KaraokeSweepTimeline([
        (startUs: 1000000, endUs: 1250000, advance: 30.0),
        (startUs: 1250000, endUs: 1750000, advance: 48.0),
        (startUs: 1750000, endUs: 2000000, advance: 32.0),
        (startUs: 2000000, endUs: 3000000, advance: 30.0),
      ]);
      expect(timeline.phaseAt(1250000), closeTo(30 / 140, .000001));
      expect(timeline.phaseAt(1750000), closeTo(78 / 140, .000001));
      var previous = 0.0;
      for (var frame = 1; frame < hz * 2; frame++) {
        final phase = timeline.phaseAt(
          1000000 + (frame * 1000000 / hz).round(),
        );
        expect(phase, greaterThan(previous));
        expect(phase - previous, lessThan(.04));
        previous = phase;
      }
      expect(timeline.phaseAt(999999), 0);
      expect(timeline.phaseAt(3000000), 1);
    });
  }
  test('real gaps cannot be accidentally fused into a synthetic relay', () {
    expect(
      () => KaraokeSweepTimeline([
        (startUs: 0, endUs: 100000, advance: 30.0),
        (startUs: 200000, endUs: 300000, advance: 30.0),
      ]),
      throwsArgumentError,
    );
  });
}
