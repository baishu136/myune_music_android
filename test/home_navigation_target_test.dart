import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/home_glass_surface.dart';
import 'package:myune_music/widgets/home_tab_viewport.dart';

void main() {
  testWidgets('initial home loads only the selected page', (tester) async {
    final controller = HomeTabController();
    addTearDown(controller.dispose);
    final built = <int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: HomeTabViewport(
          controller: controller,
          itemCount: 5,
          onPageChanged: (_) {},
          itemBuilder: (_, index) {
            built.add(index);
            return Text('page $index');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(built, {0}, reason: 'no unrelated neighbor preloading');
  });

  testWidgets('far navigation never constructs intermediate pages', (
    tester,
  ) async {
    final controller = HomeTabController();
    addTearDown(controller.dispose);
    final built = <int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: HomeTabViewport(
          controller: controller,
          itemCount: 5,
          onPageChanged: (_) {},
          itemBuilder: (_, index) {
            built.add(index);
            return Text('page $index');
          },
        ),
      ),
    );
    controller.animateToPage(
      4,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
    for (var i = 0; i < 42; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(built, {0, 4});
    await tester.pumpAndSettle();
  });

  testWidgets('all home surfaces keep their backdrop filters disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            HomeGlassControls(child: SizedBox(height: 50)),
            HomePlaylistSurface(child: SizedBox(height: 80)),
            HomeGlassMaterial(child: SizedBox(height: 70)),
            HomeGlassSurface(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
    expect(
      tester
          .widgetList<BackdropFilter>(find.byType(BackdropFilter))
          .where((filter) => filter.enabled)
          .length,
      0,
    );
  });
}
