import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';

void main() {
  test('sleep fade stays full before its final thirty seconds', () {
    expect(playbackSleepFadeFactor(const Duration(seconds: 45)), 1);
    expect(playbackSleepFadeFactor(const Duration(seconds: 30)), 1);
  });

  test('sleep fade decreases linearly to silence', () {
    expect(
      playbackSleepFadeFactor(const Duration(seconds: 15)),
      closeTo(.5, .001),
    );
    expect(
      playbackSleepFadeFactor(const Duration(seconds: 3)),
      closeTo(.1, .001),
    );
    expect(playbackSleepFadeFactor(Duration.zero), 0);
  });
}
