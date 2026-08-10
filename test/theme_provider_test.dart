import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/theme/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'lyrics-only font keeps the selected family but resets interface font',
    () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ThemeProvider();
      await Future<void>.delayed(Duration.zero);

      provider.setFontFamily('SelectedLyricsFont');
      expect(provider.currentFontFamily, 'SelectedLyricsFont');
      expect(
        provider.lightThemeData.textTheme.bodyMedium?.fontFamily,
        'SelectedLyricsFont',
      );

      await provider.setFontOnlyLyrics(true);

      expect(provider.currentFontFamily, 'SelectedLyricsFont');
      expect(provider.fontOnlyLyrics, isTrue);
      expect(
        provider.lightThemeData.textTheme.bodyMedium?.fontFamily,
        'Misans',
      );
    },
  );
}
