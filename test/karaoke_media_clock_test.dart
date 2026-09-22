import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';

void main() {
  test('clock freezes on pause and buffering then resumes from source', () {
    final clock = KaraokeMediaClock(const Duration(seconds: 5));
    clock.setRunning(true, const Duration(seconds: 5));
    clock.tick(const Duration(milliseconds: 100));
    expect(clock.value, const Duration(milliseconds: 5100));
    clock.setRunning(false, clock.value);
    clock.tick(const Duration(seconds: 3));
    expect(clock.value, const Duration(milliseconds: 5100));
    clock.setRunning(true, const Duration(milliseconds: 5200));
    clock.tick(const Duration(milliseconds: 100));
    expect(clock.value, const Duration(milliseconds: 5300));
    clock.dispose();
  });

  test('rate changes re-anchor, ordinary jitter eases and seeks snap', () {
    final clock = KaraokeMediaClock(const Duration(seconds: 10));
    clock.setRunning(true, const Duration(seconds: 10));
    clock.tick(const Duration(milliseconds: 100));
    final beforeChange = clock.value;
    clock.changeRate(2, beforeChange);
    expect(clock.value, beforeChange);
    clock.tick(const Duration(milliseconds: 200));
    expect(clock.value, const Duration(milliseconds: 10300));
    clock.readSource(const Duration(milliseconds: 10290));
    expect(clock.value, const Duration(milliseconds: 10300));
    clock.seek(const Duration(seconds: 40));
    expect(clock.value, const Duration(seconds: 40));
    clock.seek(const Duration(seconds: 4));
    expect(clock.value, const Duration(seconds: 4));
    clock.dispose();
  });

  test('continuous playback and direct seek resolve the same media time', () {
    final clock = KaraokeMediaClock(Duration.zero, rate: 1.5);
    clock.setRunning(true, Duration.zero);
    for (var i = 1; i <= 120; i++) {
      clock.tick(Duration(microseconds: i * 16667));
    }
    final arrived = clock.value;
    clock.seek(arrived);
    expect(clock.value, arrived);
    clock.dispose();
  });
}
