import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myune_music/page/setting/settings_provider.dart';

void main() {
  test(
    'new cover choices restore 90 percent and migrate old 60 to 80',
    () async {
      for (final pair in [(0.9, 0.9), (0.8, 0.8), (0.6, 0.8), (1.0, 1.0)]) {
        SharedPreferences.setMockInitialValues({'playbackCoverScale': pair.$1});
        final settings = SettingsProvider();
        await settings.initializationFuture;
        expect(settings.playbackCoverScale, pair.$2);
        await settings.setPlaybackCoverScale(.9);
        expect(
          (await SharedPreferences.getInstance()).getDouble(
            'playbackCoverScale',
          ),
          .9,
        );
        await settings.setPlaybackCoverScale(.6);
        expect(settings.playbackCoverScale, .9);
        settings.dispose();
      }
    },
  );
}
