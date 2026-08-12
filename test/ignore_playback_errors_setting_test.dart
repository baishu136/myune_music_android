import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('ignore playback error warnings preference is persisted', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.initializationFuture;

    settings.setIgnorePlaybackErrors(true);
    await Future<void>.delayed(Duration.zero);

    expect(settings.ignorePlaybackErrors, isTrue);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('ignorePlaybackErrors'), isTrue);
  });
}
