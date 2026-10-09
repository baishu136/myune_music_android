import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/theme/home_theme_scope.dart';
import 'package:myune_music/widgets/home_glass_surface.dart';
import 'package:myune_music/widgets/home_tab_viewport.dart';

void main() {
  testWidgets('glass also works with ordinary coloured themes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink),
        ),
        home: HomeThemeScope(
          disabled: false,
          builder: (_) => const Scaffold(
            body: HomeGlassSurface(child: SizedBox(height: 80, width: 200)),
          ),
        ),
      ),
    );
    expect(
      tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
      isFalse,
    );
  });

  testWidgets('home content has an unconditional outer clip', (tester) async {
    final controller = HomeTabController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeTabViewport(
            controller: controller,
            itemCount: 1,
            onPageChanged: (_) {},
            itemBuilder: (_, _) => const Text('page'),
          ),
        ),
      ),
    );
    final clips = find.ancestor(
      of: find.byType(GestureDetector),
      matching: find.byType(ClipRect),
    );
    expect(clips, findsOneWidget);
    expect(tester.widget<ClipRect>(clips).clipBehavior, Clip.hardEdge);
  });
  testWidgets(
    'playlist glass follows every palette without relayout or lost gestures',
    (tester) async {
      final neutral = ValueNotifier(false);
      final selected = ValueNotifier(false);
      addTearDown(neutral.dispose);
      addTearDown(selected.dispose);
      var taps = 0, longPresses = 0;
      const tileKey = ValueKey('playlist-tile');
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.teal,
                brightness: brightness,
              ),
            ),
            home: ValueListenableBuilder<bool>(
              valueListenable: neutral,
              builder: (_, value, _) => HomeThemeScope(
                disabled: value,
                builder: (_) => Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: selected,
                      builder: (_, value, _) => HomePlaylistSurface(
                        selected: value,
                        cornerRadius: 12,
                        child: InkWell(
                          key: tileKey,
                          onTap: () => taps++,
                          onLongPress: () => longPresses++,
                          child: const SizedBox(
                            width: 120,
                            height: 78,
                            child: Text('歌单'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final element = tester.element(find.byKey(tileKey));
        final rect = tester.getRect(find.byKey(tileKey));
        for (final value in [true, false, true]) {
          neutral.value = value;
          selected.value = value;
          for (var frame = 0; frame < 15; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(tester.element(find.byKey(tileKey)), same(element));
            expect(tester.getRect(find.byKey(tileKey)), rect);
            final filter = tester.widget<BackdropFilter>(
              find.byType(BackdropFilter),
            );
            expect(filter.enabled, isFalse);
            expect(
              filter.filter,
              same(HomeGlassProfile.filter(HomeGlassRole.playback)),
            );
            final scheme = Theme.of(element).colorScheme;
            final decoration =
                tester
                        .widget<DecoratedBox>(find.byType(DecoratedBox).first)
                        .decoration
                    as BoxDecoration;
            expect(
              decoration.color,
              (value ? scheme.secondaryContainer : scheme.surfaceContainer)
                  .withValues(alpha: .70),
            );
            expect(decoration.gradient, isNull);
            expect(
              tester
                  .widget<Material>(
                    find
                        .descendant(
                          of: find.byType(HomePlaylistSurface),
                          matching: find.byType(Material),
                        )
                        .first,
                  )
                  .color,
              Colors.transparent,
            );
          }
          final beforeTap = taps, beforeLong = longPresses;
          await tester.tap(find.byKey(tileKey));
          await tester.longPress(find.byKey(tileKey));
          expect(taps, beforeTap + 1);
          expect(longPresses, beforeLong + 1);
        }
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'overflowing content cannot paint into either footer, even in settled and moving pages',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final tablet in [false, true]) {
        tester.view.physicalSize = tablet
            ? const Size(960, 800)
            : const Size(390, 720);
        final controller = HomeTabController();
        final captureKey = GlobalKey();
        const viewportKey = ValueKey('body');
        final viewport = HomeTabViewport(
          key: viewportKey,
          controller: controller,
          itemCount: 2,
          onPageChanged: (_) {},
          itemBuilder: (_, _) => const CustomPaint(painter: _OverflowPainter()),
        );
        const player = HomeGlassMaterial(
          child: SizedBox(height: 88, width: double.infinity),
        );
        const navigation = HomeGlassSurface(
          child: SizedBox(height: 80, width: double.infinity),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: Brightness.dark),
            home: RepaintBoundary(
              key: captureKey,
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: ColoredBox(color: Color(0xFF0000FF)),
                  ),
                  Scaffold(
                    backgroundColor: Colors.transparent,
                    body: tablet
                        ? Column(
                            children: [
                              Expanded(child: viewport),
                              player,
                            ],
                          )
                        : viewport,
                    bottomNavigationBar: tablet
                        ? null
                        : const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [player, navigation],
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final body = tester.getRect(find.byKey(viewportKey));
        Future<void> checkPixels() async {
          expect(tester.getRect(find.byKey(viewportKey)), body);
          await tester.runAsync(() async {
            final boundary =
                captureKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            try {
              final data = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              for (final dy in [36, if (!tablet) 128]) {
                final pixel =
                    ((body.bottom.round() + dy) * image.width +
                        image.width ~/ 2) *
                    4;
                expect(
                  data.getUint8(pixel + 2),
                  greaterThan(data.getUint8(pixel + 1) + 35),
                  reason:
                      'footer samples the blue backdrop, not overflowing green list pixels',
                );
              }
            } finally {
              image.dispose();
            }
          });
        }

        await checkPixels();
        final slide = controller.animateToPage(
          1,
          duration: homeTabTransitionDuration,
          curve: Curves.easeOutCubic,
        );
        for (var frame = 0; frame < 41; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.getRect(find.byKey(viewportKey)), body);
          if (frame == 0 || frame == 18 || frame == 40) await checkPixels();
        }
        await tester.pumpAndSettle();
        await slide;
        await checkPixels();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );
}

/// Deliberately paints beyond its bounds, modelling a translated entrance row
/// or a nested effect. The production body boundary, not the painter, owns clip.
class _OverflowPainter extends CustomPainter {
  const _OverflowPainter();
  @override
  void paint(Canvas canvas, Size size) => canvas.drawRect(
    Rect.fromLTWH(0, size.height - 50, size.width, 350),
    Paint()..color = Colors.green,
  );
  @override
  bool shouldRepaint(covariant _OverflowPainter oldDelegate) => false;
}
