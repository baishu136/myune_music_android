import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';

void main() {
  test('ZeroBit music-style equalizer presets keep their ten-band gains', () {
    final presets = {
      for (final preset in PlaylistContentNotifier.equalizerPresets)
        preset.name: preset.gains,
    };

    expect(presets['舞曲'], [6, 5, 4, 2, 0, -1, 0, 1, 2, 1]);
    expect(presets['蓝调'], [2, 2, 2, 3, 2, 1, 2, 1, 0, -1]);
    expect(presets['慢歌'], [1, 1, 0, 0, 2, 3, 2, 1, 0, -1]);
    expect(presets['乡村'], [0, 0, 0, 1, 2, 2, 3, 2, 1, 0]);
    expect(presets.values.every((gains) => gains.length == 10), isTrue);
  });
}
