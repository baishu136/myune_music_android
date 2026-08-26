import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/services/audio/audio_interruption_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'audio occupation auto-pause defaults to enabled and persists',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      await settings.initializationFuture;

      expect(settings.pauseOnAudioInterruption, isTrue);

      await settings.setPauseOnAudioInterruption(false);

      expect(settings.pauseOnAudioInterruption, isFalse);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool('pauseOnAudioInterruption'), isFalse);
    },
  );

  test('audio occupation preference maps to the expected focus policy', () {
    expect(
      audioInterruptionPolicy(autoPause: true),
      InterruptionPolicy.pauseOnly,
    );
    expect(
      audioInterruptionPolicy(autoPause: false),
      InterruptionPolicy.keepPlaying,
    );
  });
}
