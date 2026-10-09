import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/theme/home_background_policy.dart';
import 'package:myune_music/theme/home_theme_scope.dart';
import 'package:myune_music/widgets/custom_theme_background.dart';
import 'package:myune_music/widgets/home_glass_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('bottom frost keeps a flat edge and a single 70% fill', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeThemeScope(
          disabled: true,
          builder: (_) => const Scaffold(
            body: HomeGlassMaterial(child: SizedBox(width: 390, height: 72)),
          ),
        ),
      ),
    );
    final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
    expect(clip.borderRadius, BorderRadius.zero);
    final box =
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: find.byType(HomeGlassMaterial),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(box.gradient, isNull);
    expect(box.color!.a, closeTo(.70, .001));
    expect(box.border, isNull);
  });

  test('footer strengths are independent and filters have a fixed bound', () {
    expect(HomeGlassProfile.blurStrength(HomeGlassRole.navigation), .70);
    expect(HomeGlassProfile.blurStrength(HomeGlassRole.playback), .20);
    expect(HomeGlassProfile.sigma(HomeGlassRole.navigation), 14);
    expect(HomeGlassProfile.sigma(HomeGlassRole.playback), 4);
    expect(HomeGlassProfile.blurStrength(HomeGlassRole.controls), .20);
    expect(
      HomeGlassProfile.filter(HomeGlassRole.controls),
      same(HomeGlassProfile.filter(HomeGlassRole.playback)),
    );
    for (final role in HomeGlassRole.values) {
      final filter = HomeGlassProfile.filter(role);
      for (var frame = 0; frame < 120; frame++) {
        expect(HomeGlassProfile.filter(role), same(filter));
      }
    }
  });

  testWidgets(
    'footer toggle preserves bounds, inset, text positions and State',
    (tester) async {
      final enabled = ValueNotifier(false);
      addTearDown(enabled.dispose);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      const playerKey = ValueKey('player-content');
      const navigationKey = ValueKey('navigation-content');
      var taps = 0;
      for (final brightness in Brightness.values) {
        for (final size in [const Size(390, 844), const Size(960, 800)]) {
          for (final textScale in [1.0, 1.4]) {
            tester.view.physicalSize = size;
            enabled.value = false;
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData(brightness: brightness),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    padding: const EdgeInsets.only(bottom: 24),
                    textScaler: TextScaler.linear(textScale),
                  ),
                  child: ValueListenableBuilder<bool>(
                    valueListenable: enabled,
                    builder: (_, value, _) => HomeThemeScope(
                      disabled: value,
                      builder: (_) => Scaffold(
                        body: const Text('page'),
                        bottomNavigationBar: SafeArea(
                          top: false,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              HomeGlassMaterial(
                                child: size.width < 600
                                    ? ListTile(
                                        key: playerKey,
                                        leading: const SizedBox(
                                          width: 48,
                                          height: 48,
                                          child: Icon(Icons.album),
                                        ),
                                        title: const Text('After Hours'),
                                        subtitle: const Text('The Weeknd'),
                                        trailing: _StateProbe(
                                          onTap: () => taps++,
                                        ),
                                      )
                                    : SizedBox(
                                        key: playerKey,
                                        height: 88,
                                        child: Row(
                                          children: [
                                            const Text('After Hours'),
                                            _StateProbe(onTap: () => taps++),
                                          ],
                                        ),
                                      ),
                              ),
                              HomeGlassSurface(
                                child: NavigationBar(
                                  key: navigationKey,
                                  backgroundColor: Colors.transparent,
                                  selectedIndex: 1,
                                  onDestinationSelected: (_) => taps++,
                                  destinations: const [
                                    NavigationDestination(
                                      icon: Icon(Icons.library_music),
                                      label: '音乐库',
                                    ),
                                    NavigationDestination(
                                      icon: Icon(Icons.playlist_play),
                                      label: '歌单',
                                    ),
                                    NavigationDestination(
                                      icon: Icon(Icons.person),
                                      label: '歌手',
                                    ),
                                    NavigationDestination(
                                      icon: Icon(Icons.album),
                                      label: '专辑',
                                    ),
                                    NavigationDestination(
                                      icon: Icon(Icons.settings),
                                      label: '设置',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final player = tester.getRect(find.byKey(playerKey));
            final navigation = tester.getRect(find.byKey(navigationKey));
            final title = tester.getRect(find.text('After Hours'));
            final label = tester.getRect(find.text('歌单'));
            final state = tester.state(find.byType(_StateProbe));
            expect(player.width, size.width);
            expect(player.left, 0);
            expect(player.bottom, navigation.top);
            expect(navigation.width, size.width);
            expect(navigation.bottom, size.height - 24);
            for (final value in [true, false, true]) {
              enabled.value = value;
              // Check successive animation frames, not just final layout.
              for (var frame = 0; frame < 15; frame++) {
                await tester.pump(const Duration(milliseconds: 16));
                expect(tester.getRect(find.byKey(playerKey)), player);
                expect(tester.getRect(find.byKey(navigationKey)), navigation);
                expect(tester.getRect(find.text('After Hours')), title);
                expect(tester.getRect(find.text('歌单')), label);
                expect(tester.state(find.byType(_StateProbe)), same(state));
              }
              final before = taps;
              await tester.tap(find.text('tap'));
              await tester.tap(find.text('设置'));
              expect(taps, before + 2);
            }
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          }
        }
      }
    },
  );

  test(
    'background policy ignores theme-colour override and preserves strengths',
    () async {
      for (final cover in [false, true]) {
        SharedPreferences.setMockInitialValues({
          'homeThemeImageEnabled': true,
          'homeThemeImagePath': 'test/fixtures/expected-cover.png',
          'homeThemeImageDim': .27,
          'homeThemeImageBlur': 18.0,
          'followAlbumArtOnHome': cover,
        });
        final settings = SettingsProvider();
        await settings.initializationFuture;
        final before = homeBackgroundPolicy(settings, hasSong: true);
        await settings.setDisableHomeThemeColor(true);
        final after = homeBackgroundPolicy(settings, hasSong: true);
        expect(after, before);
        expect(after.customImage, isTrue);
        expect(after.albumCover, cover);
        expect(after.hasBackground, isTrue);
        expect(settings.homeThemeImageDim, .27);
        expect(settings.homeThemeImageBlur, 18);
        final restored = SettingsProvider();
        await restored.initializationFuture;
        expect(homeBackgroundPolicy(restored, hasSong: true), before);
        expect(restored.disableHomeThemeColor, isTrue);
        await settings.setDisableHomeThemeColor(false);
        expect(
          homeBackgroundPolicy(settings, hasSong: false).customImage,
          isTrue,
        );
        restored.dispose();
        settings.dispose();
      }
    },
  );

  testWidgets('custom background remains rendered in neutral mode', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'homeThemeImageEnabled': true,
      'homeThemeImagePath': File(
        'test/fixtures/expected-cover.png',
      ).absolute.path,
      'homeThemeImageDim': .23,
      'homeThemeImageBlur': 0.0,
      'disableHomeThemeColor': true,
    });
    final settings = SettingsProvider();
    await settings.initializationFuture;
    addTearDown(settings.dispose);
    final policy = homeBackgroundPolicy(settings, hasSong: false);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink),
        ),
        home: HomeThemeScope(
          disabled: settings.disableHomeThemeColor,
          builder: (_) => CustomThemeBackground(
            path: settings.homeThemeImagePath,
            enabled: policy.customImage,
            dim: settings.homeThemeImageDim,
            blurSigma: settings.homeThemeImageBlur,
            child: const Scaffold(
              backgroundColor: Colors.transparent,
              body: Text('neutral content'),
            ),
          ),
        ),
      ),
    );
    expect(
      find.byKey(
        ValueKey('custom-theme-background-${settings.homeThemeImagePath}'),
      ),
      findsOneWidget,
    );
    final overlay = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect((overlay.decoration! as BoxDecoration).color?.a, closeTo(.23, .001));
    expect(
      tester.widget<ImageFiltered>(find.byType(ImageFiltered)).enabled,
      isFalse,
    );
    expect(
      Theme.of(
        tester.element(find.text('neutral content')),
      ).extension<HomeChromeStyle>(),
      isNotNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disabled frost retains fill, bounds, tap targets and State', (
    tester,
  ) async {
    final enabled = ValueNotifier(true);
    addTearDown(enabled.dispose);
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: enabled,
          builder: (_, value, _) => HomeThemeScope(
            disabled: value,
            builder: (_) => Scaffold(
              body: Column(
                children: [
                  HomeGlassMaterial(child: _StateProbe(onTap: () => taps++)),
                  HomeGlassSurface(
                    child: IconButton(
                      onPressed: () => taps++,
                      icon: const Icon(Icons.search),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final before = tester.state(find.byType(_StateProbe));
    final first = tester
        .widgetList<BackdropFilter>(find.byType(BackdropFilter))
        .toList();
    expect(first, hasLength(2));
    expect(first.every((filter) => !filter.enabled), isTrue);
    expect(identical(first[0].filter, first[1].filter), isFalse);
    expect(
      first[0].filter,
      same(HomeGlassProfile.filter(HomeGlassRole.playback)),
    );
    expect(
      first[1].filter,
      same(HomeGlassProfile.filter(HomeGlassRole.navigation)),
    );
    final renders = tester
        .renderObjectList<RenderBackdropFilter>(find.byType(BackdropFilter))
        .toList();
    expect(renders.every((render) => render.backdropKey == null), isTrue);
    expect(find.byType(ClipRRect), findsNWidgets(2));
    final clipped = tester.getRect(find.byType(ClipRRect).first);
    expect(clipped.height, lessThan(100));
    expect(
      tester
          .widget<Material>(
            find
                .descendant(
                  of: find.byType(HomeGlassMaterial),
                  matching: find.byType(Material),
                )
                .first,
          )
          .color,
      Colors.transparent,
    );
    await tester.tap(find.text('tap'));
    await tester.tap(find.byIcon(Icons.search));
    expect(taps, 2);
    enabled.value = false;
    await tester.pump();
    expect(tester.state(find.byType(_StateProbe)), same(before));
    expect(
      tester
          .widgetList<BackdropFilter>(find.byType(BackdropFilter))
          .every((filter) => !filter.enabled),
      isTrue,
    );
    final fallback = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(HomeGlassMaterial),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(fallback.color, Colors.transparent);
    enabled.value = true;
    await tester.pump();
    expect(tester.state(find.byType(_StateProbe)), same(before));
    expect(
      tester.widget<BackdropFilter>(find.byType(BackdropFilter).first).filter,
      same(first[0].filter),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass renders light/dark content over a coloured backdrop', (
    tester,
  ) async {
    const directory = String.fromEnvironment('HOME_ARTIFACT_DIRECTORY');
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (directory.isNotEmpty) {
      await tester.runAsync(() async {
        final fonts = FontLoader('Misans')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                await File('assets/fonts/MiSansVF.ttf').readAsBytes(),
              ),
            ),
          );
        await fonts.load().timeout(const Duration(seconds: 10));
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load().timeout(const Duration(seconds: 10));
      });
    }
    for (final neutral in [false, true]) {
      for (final brightness in Brightness.values) {
        for (final background in [false, true]) {
          final captureKey = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                fontFamily: directory.isEmpty ? null : 'Misans',
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.pink,
                  brightness: brightness,
                ),
              ),
              home: HomeThemeScope(
                disabled: neutral,
                builder: (context) {
                  final scheme = Theme.of(context).colorScheme;
                  return RepaintBoundary(
                    key: captureKey,
                    child: Stack(
                      children: [
                        ColoredBox(
                          color: scheme.surface,
                          child: const SizedBox.expand(),
                        ),
                        if (background)
                          const Positioned.fill(
                            child: CustomPaint(painter: _BackdropPainter()),
                          ),
                        Scaffold(
                          backgroundColor: Colors.transparent,
                          appBar: AppBar(
                            backgroundColor: Colors.transparent,
                            title: const Text('音乐库'),
                            actions: [
                              HomeGlassControls(
                                enabled: false,
                                child: Row(
                                  children: [
                                    IconButton(
                                      onPressed: () {},
                                      icon: const Icon(Icons.sort),
                                    ),
                                    IconButton(
                                      onPressed: () {},
                                      icon: const Icon(Icons.search),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          floatingActionButton: HomeGlassControls(
                            cornerRadius: 16,
                            child: FloatingActionButton.extended(
                              backgroundColor: Colors.transparent,
                              foregroundColor: scheme.onSurface,
                              elevation: 0,
                              onPressed: () {},
                              icon: const Icon(Icons.add),
                              label: const Text('添加歌曲'),
                            ),
                          ),
                          body: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: List.generate(
                                4,
                                (i) => i == 0
                                    ? const HomePlaylistSurface(
                                        selected: true,
                                        child: ListTile(
                                          leading: Icon(Icons.queue_music),
                                          title: Text('我的歌单'),
                                          subtitle: Text('32 首歌曲'),
                                        ),
                                      )
                                    : ListTile(
                                        leading: Icon(
                                          Icons.album,
                                          color: scheme.onSurface,
                                        ),
                                        title: Text('Song ${i + 1}'),
                                        subtitle: const Text('Artist · Album'),
                                      ),
                              ),
                            ),
                          ),
                          bottomNavigationBar: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              HomeGlassMaterial(
                                child: ListTile(
                                  leading: const Icon(Icons.album),
                                  title: const Text('After Hours'),
                                  subtitle: const Text('The Weeknd'),
                                  trailing: IconButton(
                                    onPressed: () {},
                                    icon: const Icon(Icons.pause),
                                  ),
                                ),
                              ),
                              HomeGlassSurface(
                                child: NavigationBar(
                                  backgroundColor: Colors.transparent,
                                  surfaceTintColor: Colors.transparent,
                                  elevation: 0,
                                  destinations: const [
                                    NavigationDestination(
                                      icon: Icon(Icons.library_music),
                                      label: '音乐库',
                                    ),
                                    NavigationDestination(
                                      icon: Icon(Icons.playlist_play),
                                      label: '歌单',
                                    ),
                                    NavigationDestination(
                                      icon: Icon(Icons.person),
                                      label: '歌手',
                                    ),
                                    NavigationDestination(
                                      icon: Icon(Icons.album),
                                      label: '专辑',
                                    ),
                                    NavigationDestination(
                                      icon: Icon(Icons.settings),
                                      label: '设置',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          final boundary =
              captureKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final shot = await boundary
                .toImage(pixelRatio: 1)
                .timeout(const Duration(seconds: 10));
            try {
              final bytes = await shot
                  .toByteData(format: ui.ImageByteFormat.rawRgba)
                  .timeout(const Duration(seconds: 10));
              expect(bytes, isNotNull);
              // The material and its texts must remain visible, not an opaque
              // placeholder/empty layer. Surface/foreground retain neutral contrast.
              const surfaceY = (720 - 125) * 390 * 4;
              expect(bytes!.getUint8(surfaceY + 195 * 4 + 3), 255);
              expect(
                schemeContrast(
                  Theme.of(
                    tester.element(find.text('After Hours')),
                  ).colorScheme,
                ),
                greaterThan(7),
              );
              if (directory.isNotEmpty) {
                final png = await shot
                    .toByteData(format: ui.ImageByteFormat.png)
                    .timeout(const Duration(seconds: 10));
                await Directory(directory).create(recursive: true);
                await File(
                  '$directory/${neutral ? 'neutral' : 'theme'}-${brightness.name}-${background ? 'image' : 'plain'}.png',
                ).writeAsBytes(png!.buffer.asUint8List());
              }
            } finally {
              shot.dispose();
            }
          });
          expect(tester.takeException(), isNull);
        }
      }
    }
  });
}

double schemeContrast(ColorScheme scheme) =>
    (scheme.onSurface.computeLuminance() + .05) >
        (scheme.surface.computeLuminance() + .05)
    ? (scheme.onSurface.computeLuminance() + .05) /
          (scheme.surface.computeLuminance() + .05)
    : (scheme.surface.computeLuminance() + .05) /
          (scheme.onSurface.computeLuminance() + .05);

class _StateProbe extends StatefulWidget {
  const _StateProbe({required this.onTap});
  final VoidCallback onTap;
  @override
  State<_StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<_StateProbe> {
  @override
  Widget build(BuildContext context) =>
      TextButton(onPressed: widget.onTap, child: const Text('tap'));
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var x = 0.0; x < size.width; x += 12) {
      paint.color = (x / 12).round().isEven
          ? const Color(0xFF50737B)
          : const Color(0xFF8C716A);
      canvas.drawRect(Rect.fromLTWH(x, 0, 12, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) => false;
}
