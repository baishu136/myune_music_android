import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/theme/playback_theme_policy.dart';

void main() {
  test('default playback surface inherits the app theme', () {
    expect(
      shouldForceDarkPlaybackTheme(
        customBackgroundActive: false,
        followAlbumArtEnabled: false,
      ),
      isFalse,
    );
  });

  test('image-backed playback modes keep the dark playback treatment', () {
    expect(
      shouldForceDarkPlaybackTheme(
        customBackgroundActive: true,
        followAlbumArtEnabled: false,
      ),
      isTrue,
    );
    expect(
      shouldForceDarkPlaybackTheme(
        customBackgroundActive: false,
        followAlbumArtEnabled: true,
      ),
      isTrue,
    );
  });
}
