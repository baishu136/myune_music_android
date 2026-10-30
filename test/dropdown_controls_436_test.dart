import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/side_selection_menu.dart';
import 'package:myune_music/widgets/playback_control_sheet_surface.dart';
import 'package:myune_music/widgets/song_playback_label.dart';
import 'package:myune_music/theme/home_theme_scope.dart';

void main() {
  test(
    'home and playback resolve the same source accent despite neutral home chrome',
    () {
      for (final b in Brightness.values) {
        final source = ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.orange,
            brightness: b,
          ),
        );
        final home = neutralHomeTheme(source);
        expect(songPlaybackAccent(home), source.colorScheme.primary);
        expect(songPlaybackAccent(source), source.colorScheme.primary);
      }
    },
  );

  test(
    'menu clamps wide labels and keyboard edges without exceeding its overlay',
    () {
      for (final size in [
        const Size(280, 600),
        const Size(390, 844),
        const Size(900, 1200),
      ]) {
        for (final bottom in [24.0, 280.0]) {
          final safe = EdgeInsets.fromLTRB(8, 32, 8, bottom);
          for (final y in [80.0, size.height - bottom - 12]) {
            final delegate = SelectionMenuLayout(
              anchor: Rect.fromLTWH(size.width - 80, y, 72, 36),
              safe: safe,
              width: 2000,
            );
            final constraints = delegate.getConstraintsForChild(
              BoxConstraints.tight(size),
            );
            final child = Size(
              constraints.maxWidth,
              constraints.maxHeight.clamp(1, 400),
            );
            final at = delegate.getPositionForChild(size, child);
            expect(at.dx, greaterThanOrEqualTo(safe.left));
            expect(at.dy, greaterThanOrEqualTo(safe.top));
            expect(
              at.dx + child.width,
              lessThanOrEqualTo(size.width - safe.right),
            );
            expect(
              at.dy + child.height,
              lessThanOrEqualTo(size.height - safe.bottom),
            );
          }
        }
      }
    },
  );

  testWidgets(
    'setting button is compact and right aligned; choices drop below on the root overlay',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorSchemeSeed: Colors.red),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: SideSelectionMenu<int>(
                title: '主题模式',
                segments: const [
                  ButtonSegment(value: 0, label: Text('深色')),
                  ButtonSegment(value: 1, label: Text('跟随系统')),
                ],
                selected: {selected},
                onSelectionChanged: (v) => selected = v.first,
              ),
            ),
          ),
        ),
      );
      final entry = find.descendant(
        of: find.byType(SideSelectionMenu<int>),
        matching: find.byType(OutlinedButton),
      );
      final trigger = tester.getRect(entry);
      expect(trigger.right, closeTo(374, .01));
      expect(trigger.width, lessThan(150));
      final label = tester.getRect(find.text('主题模式'));
      expect(label.center.dy, closeTo(trigger.center.dy, .01));
      await tester.tap(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 45));
      final panel = find.byKey(const ValueKey('selection-menu-panel'));
      expect(tester.getRect(panel).top, closeTo(trigger.bottom + 4, .01));
      expect(tester.getRect(panel).right, closeTo(trigger.right, .01));
      final earlyClips = tester
          .widgetList<ClipRect>(
            find.ancestor(of: panel, matching: find.byType(ClipRect)),
          )
          .where((w) => w.clipper != null);
      expect(earlyClips, isNotEmpty);
      final rect = earlyClips.first.clipper!.getClip(tester.getSize(panel));
      expect(rect.height, inExclusiveRange(0, tester.getSize(panel).height));
      await tester.pumpAndSettle();
      final option = find.byKey(const ValueKey('side-selection-1'));
      final text = tester.widget<Text>(
        find.descendant(of: option, matching: find.byType(Text)),
      );
      expect(text.style!.color, Colors.black);
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'menu escapes a clipping playback surface and retains its original background',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const clippedKey = ValueKey('clipped-controls');
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                key: clippedKey,
                height: 70,
                child: ClipRect(
                  child: PlaybackControlSheetSurface(
                    fluid: true,
                    child: SideSelectionMenu<int>(
                      title: '歌词设置',
                      segments: const [
                        ButtonSegment(value: 0, label: Text('左对齐')),
                        ButtonSegment(value: 1, label: Text('居中')),
                        ButtonSegment(value: 2, label: Text('右对齐')),
                      ],
                      selected: const {0},
                      onSelectionChanged: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(SideSelectionMenu<int>));
      await tester.pumpAndSettle();
      final panel = find.byKey(const ValueKey('selection-menu-panel'));
      expect(
        tester.getRect(panel).bottom,
        greaterThan(tester.getRect(find.byKey(clippedKey)).bottom),
      );
      expect(tester.widget<PlaybackControlSheetSurface>(panel).fluid, isTrue);
      final option = find.byKey(const ValueKey('side-selection-2'));
      expect(
        tester
            .widget<Text>(
              find.descendant(of: option, matching: find.byType(Text)),
            )
            .style!
            .color,
        Colors.white,
      );
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
