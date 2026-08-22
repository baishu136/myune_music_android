import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/transparent_chip_surface.dart';

void main() {
  testWidgets('transparent canvas is scoped to the wrapped chip subtree', (
    tester,
  ) async {
    const parentCanvas = Color(0xFF112233);
    const outsideKey = Key('outside');

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(canvasColor: parentCanvas),
        home: const Scaffold(
          body: Column(
            children: [
              TransparentChipSurface(
                enabled: true,
                child: ChoiceChip(
                  label: Text('预设'),
                  selected: false,
                  backgroundColor: Colors.transparent,
                  selectedColor: Colors.transparent,
                  onSelected: _ignoreSelection,
                ),
              ),
              SizedBox(key: outsideKey),
            ],
          ),
        ),
      ),
    );

    final chipLabelContext = tester.element(find.text('预设'));
    expect(Theme.of(chipLabelContext).canvasColor, Colors.transparent);
    expect(Material.of(chipLabelContext).color, Colors.transparent);
    expect(
      Theme.of(tester.element(find.byKey(outsideKey))).canvasColor,
      parentCanvas,
    );
  });

  testWidgets('disabled wrapper preserves the parent chip canvas', (
    tester,
  ) async {
    const parentCanvas = Color(0xFF334455);
    const childKey = Key('child');

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(canvasColor: parentCanvas),
        home: const Scaffold(
          body: TransparentChipSurface(
            enabled: false,
            child: SizedBox(key: childKey),
          ),
        ),
      ),
    );

    expect(
      Theme.of(tester.element(find.byKey(childKey))).canvasColor,
      parentCanvas,
    );
  });

  testWidgets('wrapper clears the internal canvas for every used chip type', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(canvasColor: const Color(0xFF050505)),
        home: Scaffold(
          body: Column(
            children: [
              TransparentChipSurface(
                enabled: true,
                child: ActionChip(
                  label: const Text('播放页预设'),
                  backgroundColor: Colors.transparent,
                  onPressed: () {},
                ),
              ),
              TransparentChipSurface(
                enabled: true,
                child: FilterChip(
                  label: const Text('音频效果'),
                  selected: false,
                  backgroundColor: Colors.transparent,
                  selectedColor: Colors.transparent,
                  onSelected: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );

    for (final label in ['播放页预设', '音频效果']) {
      final context = tester.element(find.text(label));
      expect(Theme.of(context).canvasColor, Colors.transparent);
      expect(Material.of(context).color, Colors.transparent);
    }
  });
}

void _ignoreSelection(bool _) {}
