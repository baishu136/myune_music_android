import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/karaoke_sweep_path.dart';
import 'package:myune_music/services/lyric_seek_notifier.dart';

void main() {
  test('blank advance consumes no sweep time, including RTL and overlaps', () {
    final path = KaraokeSweepPath([
      (start: 100.0, end: 110.0),
      (start: 0.0, end: 10.0),
      (start: 3.0, end: 8.0), // cluster overlaps must not double count
    ]);
    expect(path.length, 20);
    expect(path.frontAt(.25, 0), 5);
    expect(path.frontAt(.75, 0), 105);
    expect(path.frontAt(.25, 0, rtl: true), 105);
    expect(path.frontAt(.75, 0, rtl: true), 5);
    expect(path.distanceBefore(50), 10);
    expect(path.frontAt(0, 12), -6);
    expect(path.frontAt(1, 12), 116);
  });
  for (final hz in [60, 90, 120]) {
    test(
      'front moves deterministically at $hz Hz; jumps only over blank ink',
      () {
        final path = KaraokeSweepPath([
          (start: 0.0, end: 20.0),
          (start: 50.0, end: 70.0),
          (start: 90.0, end: 150.0),
        ]);
        var previous = path.frontAt(0, 14);
        for (var frame = 1; frame <= hz; frame++) {
          final phase = frame / hz;
          final front = path.frontAt(phase, 14);
          expect(front, path.frontAt(phase, 14));
          expect(front, greaterThanOrEqualTo(previous));
          // Account only for actual skipped blank intervals, not a time jump.
          var gap = 0.0;
          if (previous <= 20 && front >= 50) gap += 30;
          if (previous <= 70 && front >= 90) gap += 20;
          expect(front - previous - gap, closeTo(114 / hz, .00001));
          previous = front;
        }
      },
    );
  }
  test('repeated seeks/replays to zero always publish a new reset event', () {
    final seek = LyricSeekNotifier();
    addTearDown(seek.dispose);
    final targets = <Duration?>[];
    seek.addListener(() => targets.add(seek.value));
    seek.publish(Duration.zero);
    seek.publish(Duration.zero);
    seek.publish(const Duration(seconds: 10));
    seek.publish(Duration.zero);
    expect(targets, [
      Duration.zero,
      Duration.zero,
      const Duration(seconds: 10),
      Duration.zero,
    ]);
  });
}
