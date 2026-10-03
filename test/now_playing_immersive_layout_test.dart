import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/widgets/now_playing_immersive_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('immersive preference defaults off and survives reloading', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.initializationFuture;
    expect(settings.playbackImmersiveEnabled, isFalse);
    await settings.setPlaybackImmersiveEnabled(true);
    final restored = SettingsProvider();
    await restored.initializationFuture;
    expect(restored.playbackImmersiveEnabled, isTrue);
    expect(restored.enableKaraokeLyrics, settings.enableKaraokeLyrics);
    await restored.setPlaybackImmersiveEnabled(false);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'playbackImmersiveEnabled',
      ),
      isFalse,
    );
    settings.dispose();
    restored.dispose();
  });

  for (final split in [false, true]) {
    testWidgets(
      'chrome fades, frees the entire viewport and returns in place (split=$split)',
      (tester) async {
        tester.view.physicalSize = split
            ? const Size(1100, 800)
            : const Size(420, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final immersive = ValueNotifier(false);
        final visualKey = GlobalKey();
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: immersive,
                builder: (_, hide, _) => NowPlayingImmersiveLayout(
                  immersive: hide,
                  split: split,
                  tablet: split,
                  header: TextButton(
                    onPressed: () => taps++,
                    child: const Text('header'),
                  ),
                  visual: GestureDetector(
                    key: visualKey,
                    onTap: () => immersive.value = false,
                    child: const ColoredBox(
                      color: Colors.black,
                      child: Center(child: Text('lyrics')),
                    ),
                  ),
                  controls: SizedBox(
                    key: const ValueKey('controls'),
                    height: 170,
                    child: TextButton(
                      onPressed: () => taps++,
                      child: const Text('controls'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final element = visualKey.currentContext;
        final normalVisual = tester.getRect(find.byKey(visualKey));
        final normalControls = tester.getRect(
          find.byKey(const ValueKey('controls')),
        );
        immersive.value = true;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 140));
        final intermediate = tester.getRect(find.byKey(visualKey));
        expect(intermediate.height, greaterThan(normalVisual.height));
        final opacity = tester.widget<FadeTransition>(
          find
              .ancestor(
                of: find.text('header'),
                matching: find.byType(FadeTransition),
              )
              .first,
        );
        expect(opacity.opacity.value, inExclusiveRange(0, 1));
        await tester.pumpAndSettle();
        final full = tester.getRect(find.byKey(visualKey));
        expect(full.top, split ? 20 : 8);
        expect(full.bottom, split ? 778 : 788);
        if (split) expect(full.width, closeTo(1044, .01));
        expect(visualKey.currentContext, same(element));
        await tester.tapAt(normalControls.center);
        expect(taps, 0);
        // The fullscreen lyrics surface remains the escape gesture.
        await tester.tap(find.text('lyrics'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          tester
              .widget<FadeTransition>(
                find
                    .ancestor(
                      of: find.text('header'),
                      matching: find.byType(FadeTransition),
                    )
                    .first,
              )
              .opacity
              .value,
          inExclusiveRange(0, 1),
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byKey(visualKey)), normalVisual);
        expect(
          tester.getRect(find.byKey(const ValueKey('controls'))),
          normalControls,
        );
        expect(visualKey.currentContext, same(element));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        immersive.dispose();
      },
    );
  }

  testWidgets('rapidly reversing immersive transition retains the visual', (
    tester,
  ) async {
    final immersive = ValueNotifier(false);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: immersive,
            builder: (_, value, _) => NowPlayingImmersiveLayout(
              immersive: value,
              header: const Text('header'),
              visual: SizedBox.expand(key: key),
              controls: const SizedBox(height: 150),
            ),
          ),
        ),
      ),
    );
    final element = key.currentContext;
    final original = tester.getRect(find.byKey(key));
    for (var i = 0; i < 8; i++) {
      immersive.value = !immersive.value;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(key.currentContext, same(element));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(key)), original);
    await tester.pumpWidget(const SizedBox.shrink());
    immersive.dispose();
  });
}
