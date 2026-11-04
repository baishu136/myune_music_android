import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/now_playing_route.dart';

void main() {
  testWidgets(
    'player entry scales both pages and reverses without replacing home',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Text('home')),
        ),
      );
      final home = tester.element(find.text('home'));
      nav.currentState!.push(
        NowPlayingRoute(builder: (_) => const Scaffold(body: Text('player'))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      final incoming = tester.widget<ScaleTransition>(
        find.byKey(const ValueKey('player-entry-scale')),
      );
      final outgoing = tester.widget<ScaleTransition>(
        find.byKey(const ValueKey('player-home-scale')),
      );
      expect(incoming.scale.value, inExclusiveRange(1, 1.035));
      expect(outgoing.scale.value, inExclusiveRange(.965, 1));
      for (final key in ['player-entry-scale', 'player-home-scale']) {
        final fades = find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(FadeTransition),
        );
        if (key == 'player-entry-scale') expect(fades, findsNothing);
        // Material's underlying route retains inert framework fade wrappers.
        // Their opacity must stay at one; the player adds no fading layer.
        for (final fade in tester.widgetList<FadeTransition>(fades)) {
          expect(fade.opacity.value, 1);
        }
      }
      final scale = incoming.scale.value;
      nav.currentState!.pop();
      await tester.pump();
      expect(
        tester
            .widget<ScaleTransition>(
              find.byKey(const ValueKey('player-entry-scale')),
            )
            .scale
            .value,
        closeTo(scale, .0001),
      );
      await tester.pumpAndSettle();
      expect(tester.element(find.text('home')), same(home));
      expect(find.text('player'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion skips the new scale and fade layers', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(body: Text('home')),
      ),
    );
    nav.currentState!.push(
      NowPlayingRoute(builder: (_) => const Scaffold(body: Text('player'))),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('player-entry-scale')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
