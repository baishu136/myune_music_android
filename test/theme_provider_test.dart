import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
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

  test(
    'manual color is applied exactly and persisted without preset snapping',
    () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ThemeProvider();
      await Future<void>.delayed(Duration.zero);
      const customColor = Color(0xFF123456);

      await provider.setSeedColor(customColor, isManual: true);

      expect(provider.currentSeedColor, customColor);
      expect(provider.lastManualSeedColor, customColor);
      expect(provider.lightThemeData.colorScheme.primary, customColor);
      expect(provider.darkThemeData.colorScheme.primary, customColor);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getInt('user_seed_color'), customColor.toARGB32());
      expect(
        preferences.getInt('user_last_manual_seed_color'),
        customColor.toARGB32(),
      );
    },
  );

  test('dynamic color stays inside a preset range without exact snapping', () {
    const source = Color(0xFF2471A3);

    final ranged = constrainDynamicSeedToPresetRange(source);
    final rangedHsl = HSLColor.fromColor(ranged);
    final nearestHueDistance = themePresetColors
        .map(
          (color) =>
              (HSLColor.fromColor(color).hue - rangedHsl.hue).abs() % 360,
        )
        .map((distance) => distance > 180 ? 360 - distance : distance)
        .reduce((first, second) => first < second ? first : second);

    expect(nearestHueDistance, lessThanOrEqualTo(7.6));
    expect(themePresetColors, isNot(contains(ranged)));
  });

  test(
    'cover palette ignores black and white padding before choosing color',
    () {
      const artworkGray = Color(0xFF6A7078);
      const minorAccent = Color(0xFF00E676);
      final selected = selectRepresentativeCoverColor(const [
        Colors.black,
        Colors.white,
        artworkGray,
        minorAccent,
      ]);

      expect(selected, artworkGray);
      expect(
        selectRepresentativeCoverColor(const [Colors.black, Colors.white]),
        Colors.black,
      );
    },
  );

  test('cover palette favors a repeated background color family', () {
    const isolatedForeground = Color(0xFFA96F4F);
    const selected = Color(0xFF7E57C2);
    final result = selectRepresentativeCoverColor(const [
      isolatedForeground,
      selected,
      Color(0xFF673AB7),
      Color(0xFF5C6BC0),
    ]);

    expect(result, selected);
  });

  test('dynamic colors are corrected for the active brightness mode', () {
    const darkSource = Color(0xFF101820);
    const lightSource = Color(0xFFF5F1E8);

    final darkAdjusted = adaptDynamicSeedColor(darkSource, Brightness.dark);
    final lightAdjusted = adaptDynamicSeedColor(lightSource, Brightness.light);

    expect(HSLColor.fromColor(darkAdjusted).lightness, closeTo(.62, .005));
    expect(HSLColor.fromColor(lightAdjusted).lightness, closeTo(.38, .005));
    for (final adjusted in [darkAdjusted, lightAdjusted]) {
      final hue = HSLColor.fromColor(adjusted).hue;
      final nearestHueDistance = themePresetColors
          .map((color) => (HSLColor.fromColor(color).hue - hue).abs() % 360)
          .map((distance) => distance > 180 ? 360 - distance : distance)
          .reduce((first, second) => first < second ? first : second);
      expect(nearestHueDistance, lessThanOrEqualTo(7.6));
    }
  });

  test('changing theme mode reapplies the original dynamic color', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = ThemeProvider();
    await Future<void>.delayed(Duration.zero);
    const source = Color(0xFF121212);

    await provider.setThemeMode(ThemeMode.dark);
    await provider.setDynamicSeedColor(source);
    expect(
      HSLColor.fromColor(provider.currentSeedColor).lightness,
      closeTo(.62, .005),
    );

    await provider.setThemeMode(ThemeMode.light);
    expect(provider.currentSeedColor, source);
  });

  test('dynamic theme data is reused after a color is revisited', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = ThemeProvider();
    await Future<void>.delayed(Duration.zero);
    const dynamicSource = Color(0xFF2471A3);

    provider.prewarmDynamicSeedColor(dynamicSource);
    await provider.setDynamicSeedColor(dynamicSource);
    final firstLightTheme = provider.lightThemeData;
    final firstDarkTheme = provider.darkThemeData;

    await provider.setSeedColor(const Color(0xFFE53935));
    await provider.setDynamicSeedColor(dynamicSource);

    expect(identical(provider.lightThemeData, firstLightTheme), isTrue);
    expect(identical(provider.darkThemeData, firstDarkTheme), isTrue);
  });

  test(
    'dynamic cover color does not override the selected theme mode',
    () async {
      SharedPreferences.setMockInitialValues({'user_theme_mode': 'system'});
      final provider = ThemeProvider();
      await provider.initialize();

      await provider.setDynamicSeedColor(const Color(0xFF090B10));
      expect(provider.themeMode, ThemeMode.system);
      expect(provider.effectiveThemeMode, ThemeMode.system);

      await provider.setThemeMode(ThemeMode.light);
      expect(provider.effectiveThemeMode, ThemeMode.light);
    },
  );

  test(
    'dynamic colors hard switch while manual colors retain motion',
    () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ThemeProvider();
      await provider.initialize();

      expect(provider.animateThemeChanges, isTrue);
      await provider.setDynamicSeedColor(const Color(0xFF2471A3));
      expect(provider.animateThemeChanges, isFalse);

      await provider.setSeedColor(const Color(0xFF123456), isManual: true);
      expect(provider.animateThemeChanges, isTrue);
    },
  );
}
