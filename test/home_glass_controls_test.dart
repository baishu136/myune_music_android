import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/theme/home_theme_scope.dart';
import 'package:myune_music/widgets/home_glass_surface.dart';

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
}

void main() {
  test(
    'neutral foregrounds remain legible over 70% glass, not only opaque fill',
    () {
      for (final brightness in Brightness.values) {
        final home = neutralHomeTheme(ThemeData(brightness: brightness));
        final scheme = home.colorScheme;
        final glass = scheme.surfaceContainerHigh.withValues(alpha: .70);
        for (final backdrop in [
          Colors.black,
          Colors.white,
          Colors.pink,
          Colors.yellow,
          Colors.cyan,
          const Color(0xFF50737B),
        ]) {
          final composed = Color.alphaBlend(glass, backdrop);
          expect(
            _contrast(scheme.onSurface, composed),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            _contrast(scheme.onSurfaceVariant, composed),
            greaterThanOrEqualTo(3),
          );
        }
        expect(
          _contrast(scheme.onSecondaryContainer, scheme.secondaryContainer),
          greaterThanOrEqualTo(7),
        );
        final style = home.iconButtonTheme.style!;
        expect(style.foregroundColor!.resolve({}), scheme.onSurface);
        expect(
          style.foregroundColor!.resolve({WidgetState.disabled})!.a,
          closeTo(.38, .001),
        );
        expect(
          home.scaffoldBackgroundColor,
          brightness == Brightness.light
              ? Colors.white
              : const Color(0xFF121212),
        );
      }
    },
  );

  testWidgets(
    'controls and playback retain fill and hit targets without active blur',
    (tester) async {
      tester.view.physicalSize = const Size(390, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final enabled = ValueNotifier(false);
      final selection = ValueNotifier(false);
      addTearDown(enabled.dispose);
      addTearDown(selection.dispose);
      const sortKey = ValueKey('sort');
      const actionsKey = ValueKey('actions');
      const addKey = ValueKey('add');
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: enabled,
            builder: (_, value, _) => HomeThemeScope(
              disabled: value,
              builder: (context) => Scaffold(
                appBar: AppBar(
                  leading: HomeGlassControls(
                    cornerRadius: 28,
                    child: IconButton(
                      onPressed: () => taps++,
                      icon: const Icon(Icons.close),
                    ),
                  ),
                  actions: [
                    HomeGlassControls(
                      key: actionsKey,
                      enabled: false,
                      child: ValueListenableBuilder<bool>(
                        valueListenable: selection,
                        builder: (_, selecting, _) => AnimatedSwitcher(
                          duration: const Duration(milliseconds: 380),
                          reverseDuration: const Duration(milliseconds: 320),
                          child: Row(
                            key: ValueKey(selecting),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (selecting)
                                IconButton(
                                  onPressed: () => taps++,
                                  icon: const Icon(Icons.select_all),
                                ),
                              IconButton(
                                key: sortKey,
                                onPressed: () => taps++,
                                icon: const Icon(Icons.sort),
                              ),
                              IconButton(
                                onPressed: () => taps++,
                                icon: const Icon(Icons.search),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                body: const Text('page'),
                floatingActionButton: HomeGlassControls(
                  cornerRadius: 16,
                  child: FloatingActionButton.extended(
                    key: addKey,
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    onPressed: () => taps++,
                    icon: const Icon(Icons.add),
                    label: const Text('添加歌曲'),
                  ),
                ),
                bottomNavigationBar: const HomeGlassMaterial(
                  child: SizedBox(height: 72, child: Text('playing')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final sortRect = tester.getRect(find.byKey(sortKey));
      final addRect = tester.getRect(find.byKey(addKey));
      final sortElement = tester.element(find.byKey(sortKey));
      final filters = tester
          .widgetList<BackdropFilter>(find.byType(BackdropFilter))
          .toList();
      expect(filters, hasLength(4));
      final filter = HomeGlassProfile.filter(HomeGlassRole.playback);
      for (final value in [true, false, true]) {
        enabled.value = value;
        for (var frame = 0; frame < 15; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.getRect(find.byKey(sortKey)), sortRect);
          expect(tester.getRect(find.byKey(addKey)), addRect);
          expect(tester.element(find.byKey(sortKey)), same(sortElement));
        }
        for (final current in tester.widgetList<BackdropFilter>(
          find.byType(BackdropFilter),
        )) {
          expect(current.filter, same(filter));
        }
        for (final controls in tester.elementList(
          find.byType(HomeGlassControls),
        )) {
          final boxes = find.descendant(
            of: find.byElementPredicate((e) => identical(e, controls)),
            matching: find.byType(DecoratedBox),
          );
          final decoration =
              tester.widget<DecoratedBox>(boxes.first).decoration
                  as BoxDecoration;
          expect(decoration.gradient, isNull);
          expect(decoration.border, isNull);
          final widget = controls.widget as HomeGlassControls;
          expect(
            decoration.color?.a,
            widget.enabled ? closeTo(.70, .001) : isNull,
          );
        }
        final before = taps;
        await tester.tap(find.byKey(sortKey));
        await tester.tap(find.byKey(addKey));
        expect(taps, before + 2);
      }
      selection.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        find.descendant(of: find.byKey(actionsKey), matching: find.byType(Row)),
        findsNWidgets(2),
      );
      expect(
        find.descendant(
          of: find.byKey(actionsKey),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );
      final actionsFilter = tester.widget<BackdropFilter>(
        find.descendant(
          of: find.byKey(actionsKey),
          matching: find.byType(BackdropFilter),
        ),
      );
      expect(actionsFilter.enabled, isFalse);
      expect(
        tester
            .widgetList<BackdropFilter>(find.byType(BackdropFilter))
            .where((filter) => filter.enabled),
        isEmpty,
      );
      for (final render in tester.renderObjectList<RenderBackdropFilter>(
        find.byType(BackdropFilter),
      )) {
        expect(render.backdropKey, isNull);
        expect(render.size.height, lessThanOrEqualTo(72));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
