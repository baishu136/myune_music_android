import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/theme/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'cover primary stays identical across light dark and system modes',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final provider = ThemeProvider();
      await provider.initialize();
      addTearDown(provider.dispose);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      for (final source in [
        const Color(0xFF101820),
        const Color(0xFF2471A3),
        const Color(0xFFF5F1E8),
        Colors.pink,
        Colors.teal,
        Colors.black,
        Colors.white,
      ]) {
        await provider.setThemeMode(ThemeMode.dark);
        provider.prewarmDynamicSeedColor(source);
        await provider.setDynamicSeedColor(source);
        final dark = provider.currentSeedColor;
        final cachedLight = provider.lightThemeData;
        final cachedDark = provider.darkThemeData;
        await provider.setThemeMode(ThemeMode.light);
        expect(provider.currentSeedColor, dark);
        expect(provider.lightThemeData.colorScheme.primary, dark);
        expect(provider.darkThemeData.colorScheme.primary, dark);
        expect(identical(provider.lightThemeData, cachedLight), isTrue);
        expect(identical(provider.darkThemeData, cachedDark), isTrue);
        expect(
          provider.lightThemeData.colorScheme.surface,
          isNot(provider.darkThemeData.colorScheme.surface),
        );
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        await provider.setThemeMode(ThemeMode.system);
        expect(provider.currentSeedColor, dark);
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        await provider.setDynamicSeedColor(source);
        expect(provider.currentSeedColor, dark);
      }
    },
  );
}
