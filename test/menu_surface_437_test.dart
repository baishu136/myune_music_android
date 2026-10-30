import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/page/setting/tabs/theme_settings_section.dart';
import 'package:myune_music/theme/theme_provider.dart';
import 'package:myune_music/widgets/playback_control_sheet_surface.dart';
import 'package:myune_music/widgets/side_selection_menu.dart';

const _preview = String.fromEnvironment('PREVIEW437');

Future<void> _fonts(WidgetTester tester) async {
  if (_preview.isEmpty) return;
  await tester.runAsync(() async {
    await (FontLoader(
      'Preview437',
    )..addFont(rootBundle.load('assets/fonts/MiSansVF.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
}

Future<void> _pixels(
  WidgetTester tester,
  GlobalKey capture,
  Rect panel,
  Color background,
  String name,
) async {
  await tester.runAsync(() async {
    final image =
        await (capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = (await image.toByteData())!;
      for (final point in [
        panel.topLeft + const Offset(1, 1),
        panel.topRight + const Offset(-2, 1),
        panel.bottomLeft + const Offset(1, -2),
        panel.bottomRight + const Offset(-2, -2),
      ]) {
        final at = (point.dy.floor() * image.width + point.dx.floor()) * 4;
        final expected = [background.r, background.g, background.b];
        for (var channel = 0; channel < 3; channel++) {
          expect(
            bytes.getUint8(at + channel),
            closeTo(expected[channel] * 255, 1),
            reason: '$name corner $point channel $channel',
          );
        }
      }
      if (_preview.isNotEmpty) {
        await Directory(_preview).create(recursive: true);
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await File(
          '$_preview/$name.png',
        ).writeAsBytes(png.buffer.asUint8List());
      }
    } finally {
      image.dispose();
    }
  });
}

Future<Finder> _menu(
  WidgetTester tester,
  ThemeData theme,
  GlobalKey capture,
  Color background, {
  required bool fluid,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  await _fonts(tester);
  final menu = SideSelectionMenu<int>(
    title: '歌词对齐方式',
    segments: const [
      ButtonSegment(value: 0, label: Text('左对齐')),
      ButtonSegment(value: 1, label: Text('居中')),
      ButtonSegment(value: 2, label: Text('右对齐')),
    ],
    selected: const {1},
    onSelectionChanged: (_) {},
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      builder: (_, child) => RepaintBoundary(key: capture, child: child!),
      home: Scaffold(
        backgroundColor: background,
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 40, 16, 0),
          child: Align(
            alignment: Alignment.topCenter,
            child: fluid
                ? PlaybackControlSheetSurface(fluid: true, child: menu)
                : menu,
          ),
        ),
      ),
    ),
  );
  return find.descendant(
    of: find.byType(SideSelectionMenu<int>),
    matching: find.byType(OutlinedButton),
  );
}

void main() {
  testWidgets('popup and entry share the same border and corner geometry', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final brightness in Brightness.values) {
      for (final fluid in [false, true]) {
        const side = BorderSide(color: Color(0xff789abc), width: 1.5);
        final theme = ThemeData(
          brightness: brightness,
          outlinedButtonTheme: const OutlinedButtonThemeData(
            style: ButtonStyle(side: WidgetStatePropertyAll(side)),
          ),
        );
        final entry = await _menu(
          tester,
          theme,
          GlobalKey(),
          Colors.white,
          fluid: fluid,
        );
        final button = tester.widget<OutlinedButton>(entry);
        final shape =
            button.style!.shape!.resolve({})! as RoundedRectangleBorder;
        await tester.tap(entry);
        await tester.pumpAndSettle();
        final popup = find.byKey(const ValueKey('selection-menu-panel'));
        if (fluid) {
          final surface = tester.widget<PlaybackControlSheetSurface>(popup);
          expect(surface.borderRadius, shape.borderRadius);
          final decoration =
              tester
                      .widget<DecoratedBox>(
                        find
                            .descendant(
                              of: popup,
                              matching: find.byType(DecoratedBox),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration;
          expect(decoration.border, const Border.fromBorderSide(side));
        } else {
          final panel = tester.widget<Material>(popup);
          final border = panel.shape! as RoundedRectangleBorder;
          expect(border.borderRadius, shape.borderRadius);
          expect(border.side, side);
        }
        await tester.tap(find.byKey(const ValueKey('side-selection-1')));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  for (final brightness in Brightness.values) {
    for (final fluid in [false, true]) {
      testWidgets('$brightness fluid=$fluid has clean animated popup corners', (
        tester,
      ) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final background = brightness == Brightness.light
            ? const Color(0xfffdf9fb)
            : const Color(0xff152d43);
        final capture = GlobalKey();
        final entry = await _menu(
          tester,
          ThemeData(
            brightness: brightness,
            fontFamily: _preview.isEmpty ? null : 'Preview437',
          ),
          capture,
          background,
          fluid: fluid,
        );
        await tester.tap(entry);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        final popup = find.byKey(const ValueKey('selection-menu-panel'));
        await _pixels(
          tester,
          capture,
          tester.getRect(popup),
          background,
          '${brightness.name}-$fluid-entering',
        );
        await tester.pumpAndSettle();
        await _pixels(
          tester,
          capture,
          tester.getRect(popup),
          background,
          '${brightness.name}-$fluid-open',
        );
        await tester.tap(find.byKey(const ValueKey('side-selection-2')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('theme mode has a larger target and still applies its choice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    final field = find.byType(SideSelectionMenu<ThemeMode>);
    final entry = find.descendant(
      of: field,
      matching: find.byType(OutlinedButton),
    );
    final rect = tester.getRect(entry);
    expect(rect.width, greaterThanOrEqualTo(104));
    expect(rect.height, greaterThanOrEqualTo(48));
    expect(rect.right, closeTo(tester.view.physicalSize.width - 16, 1));
    await tester.tap(entry);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('side-selection-ThemeMode.light')),
    );
    await tester.pumpAndSettle();
    expect(theme.themeMode, ThemeMode.light);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
