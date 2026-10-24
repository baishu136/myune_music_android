import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/theme/home_theme_scope.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/page/setting/tabs/theme_settings_section.dart';
import 'package:myune_music/theme/theme_provider.dart';
import 'package:myune_music/widgets/home_glass_surface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'light home paints pure white while keeping its coloured accent',
    (tester) async {
      for (final brightness in Brightness.values) {
        for (final disabled in [false, true]) {
          final source = ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.pink,
              brightness: brightness,
            ),
          );
          final capture = GlobalKey();
          late ThemeData home;
          await tester.pumpWidget(
            MaterialApp(
              theme: source,
              home: HomeThemeScope(
                disabled: disabled,
                builder: (context) {
                  home = Theme.of(context);
                  return RepaintBoundary(
                    key: capture,
                    child: Scaffold(
                      appBar: AppBar(title: const Text('音乐库')),
                      body: const SizedBox.expand(),
                      bottomNavigationBar: const HomeNavigationSurface(
                        child: SizedBox(height: 64),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (brightness == Brightness.light) {
            expect(home.scaffoldBackgroundColor, Colors.white);
            expect(home.colorScheme.surface, Colors.white);
            expect(home.colorScheme.surfaceContainerHigh, Colors.white);
            expect(home.colorScheme.surfaceContainer, Colors.white);
            await tester.runAsync(() async {
              final image =
                  await (capture.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage();
              final pixels = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              for (final y in [5, image.height ~/ 2, image.height - 5]) {
                expect(pixels.getUint32((y * image.width + 5) * 4), 0xFFFFFFFF);
              }
              final output = Platform.environment['HOME_WHITE_PREVIEW_DIR'];
              if (output != null) {
                final png = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  '$output/white-neutral-$disabled.png',
                ).writeAsBytes(png!.buffer.asUint8List());
              }
              image.dispose();
            });
            if (!disabled) {
              expect(home.colorScheme.primary, source.colorScheme.primary);
            }
          } else if (!disabled) {
            expect(
              home.scaffoldBackgroundColor,
              source.scaffoldBackgroundColor,
            );
            expect(home.colorScheme, source.colorScheme);
          }
        }
      }
    },
  );
  test('neutral home foreground does not retain the artwork seed tint', () {
    for (final brightness in Brightness.values) {
      final original = ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.pink,
          brightness: brightness,
        ),
        fontFamily: 'TestFont',
      );
      final home = neutralHomeTheme(original);
      expect(home.textTheme.bodyMedium!.color, home.colorScheme.onSurface);
      expect(home.iconTheme.color, home.colorScheme.onSurface);
      for (final color in [
        home.textTheme.bodyMedium!.color!,
        home.iconTheme.color!,
        home.colorScheme.onSurfaceVariant,
      ]) {
        expect(color.r, closeTo(color.g, .0001));
        expect(color.g, closeTo(color.b, .0001));
      }
    }
  });

  test('neutral home restores 362 white surfaces without seed tint', () {
    for (final brightness in Brightness.values) {
      final home = neutralHomeTheme(
        ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.pink,
            brightness: brightness,
          ),
        ),
      );
      if (brightness == Brightness.light) {
        expect(home.colorScheme.surfaceContainerHigh, Colors.white);
        expect(home.colorScheme.surfaceContainer, Colors.white);
        expect(home.colorScheme.surfaceContainerHighest, Colors.white);
      }
      expect(
        HSLColor.fromColor(home.colorScheme.primary).saturation,
        lessThan(.02),
      );
    }
  });
  test(
    'home override defaults off, persists, and preserves other preferences',
    () async {
      SharedPreferences.setMockInitialValues({
        'followAlbumArtOnHome': true,
        'homeThemeImageEnabled': true,
        'useDynamicColor': true,
      });
      final settings = SettingsProvider();
      await settings.initializationFuture;
      expect(settings.disableHomeThemeColor, isFalse);
      await settings.setDisableHomeThemeColor(true);
      final restored = SettingsProvider();
      await restored.initializationFuture;
      expect(restored.disableHomeThemeColor, isTrue);
      expect(restored.followAlbumArtOnHome, isTrue);
      expect(restored.homeThemeImageEnabled, isTrue);
      expect(restored.useDynamicColor, isTrue);
      await restored.setDisableHomeThemeColor(false);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'disableHomeThemeColor',
        ),
        isFalse,
      );
      restored.dispose();
      settings.dispose();
    },
  );

  test(
    'home is white/black-grey with neutral surfaces and inherited fonts',
    () {
      for (final brightness in Brightness.values) {
        final original = ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.pink,
            brightness: brightness,
          ),
          fontFamily: 'TestFont',
        );
        final home = neutralHomeTheme(original);
        expect(home.textTheme.bodyMedium?.fontFamily, 'TestFont');
        expect(
          home.textTheme.bodyMedium?.fontSize,
          original.textTheme.bodyMedium?.fontSize,
        );
        expect(
          home.textTheme.bodyMedium?.fontWeight,
          original.textTheme.bodyMedium?.fontWeight,
        );
        expect(home.textTheme.bodyMedium?.color, home.colorScheme.onSurface);
        expect(home.iconTheme.size, original.iconTheme.size);
        expect(home.iconTheme.color, home.colorScheme.onSurface);
        expect(
          home.scaffoldBackgroundColor,
          brightness == Brightness.light
              ? Colors.white
              : const Color(0xFF121212),
        );
        for (final color in [
          home.navigationBarTheme.backgroundColor!,
          home.colorScheme.surfaceContainerHigh,
        ]) {
          expect(color.a, 1);
          expect(color.r, closeTo(color.g, .005));
          expect(color.g, closeTo(color.b, .005));
          if (brightness == Brightness.light) {
            expect(HSLColor.fromColor(color).lightness, greaterThan(.90));
          }
        }
        expect(original.colorScheme.primary, isNot(home.colorScheme.primary));
      }
    },
  );

  testWidgets('toggle preserves page state; pushed route uses app theme', (
    tester,
  ) async {
    final disabled = ValueNotifier(false);
    addTearDown(disabled.dispose);
    final appTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: ValueListenableBuilder<bool>(
          valueListenable: disabled,
          builder: (context, value, _) => HomeThemeScope(
            disabled: value,
            builder: (_) => const _HomeProbe(),
          ),
        ),
      ),
    );
    final before = tester.state(find.byType(_HomeProbe));
    disabled.value = true;
    await tester.pump();
    expect(tester.state(find.byType(_HomeProbe)), same(before));
    expect(
      Theme.of(tester.element(find.byType(_HomeProbe))).scaffoldBackgroundColor,
      Colors.white,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('playback'))).colorScheme.primary,
      appTheme.colorScheme.primary,
    );
    expect(
      Theme.of(
        tester.element(find.text('playback')),
      ).extension<HomeChromeStyle>(),
      isNull,
    );
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    disabled.value = false;
    await tester.pump();
    expect(tester.state(find.byType(_HomeProbe)), same(before));
    expect(
      Theme.of(tester.element(find.byType(_HomeProbe))).colorScheme.primary,
      appTheme.colorScheme.primary,
    );
  });

  testWidgets('personalization provides the functioning home option', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.initializationFuture;
    final theme = ThemeProvider();
    addTearDown(settings.dispose);
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: theme),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ThemeSettingsSection()),
          ),
        ),
      ),
    );
    final option = tester.widget<SwitchListTile>(
      find.ancestor(
        of: find.text('主页禁用主题色'),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(option.subtitle, isNull);
    expect(find.text('主页使用白色或黑灰色；保留自定义背景，不影响播放页'), findsNothing);
    await tester.ensureVisible(find.text('主页禁用主题色'));
    await tester.tap(find.text('主页禁用主题色'));
    await tester.pumpAndSettle();
    expect(settings.disableHomeThemeColor, isTrue);
  });
}

class _HomeProbe extends StatefulWidget {
  const _HomeProbe();
  @override
  State<_HomeProbe> createState() => _HomeProbeState();
}

class _HomeProbeState extends State<_HomeProbe> {
  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextButton(
      child: const Text('open'),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('playback')),
        ),
      ),
    ),
  );
}
