import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/home_expandable_actions.dart';
import 'package:myune_music/widgets/song_selection_actions.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
      'misans',
    )..addFont(rootBundle.load('assets/fonts/MiSansVF.ttf'))).load();
  });

  testWidgets(
    'search stays visible and fixed while other actions expand inline',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calls = <int>[];
      final capture = GlobalKey();
      Future<void> picture(String name) async {
        final path = Platform.environment['HOME_ACTIONS_PREVIEW_DIR'];
        if (path == null) return;
        await tester.runAsync(() async {
          final image =
              await (capture.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$path/$name.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      Widget host(String page) => MaterialApp(
        theme: ThemeData.dark().copyWith(
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'misans'),
        ),
        home: RepaintBoundary(
          key: capture,
          child: Scaffold(
            appBar: AppBar(
              title: const Text(
                '音乐库',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                HomeExpandableActions(
                  key: ValueKey(page),
                  searchAction: IconButton(
                    tooltip: '搜索',
                    icon: const Icon(Icons.search),
                    onPressed: () => calls.add(9),
                  ),
                  children: [
                    for (var i = 0; i < 4; i++)
                      IconButton(
                        tooltip: '功能$i',
                        icon: const Icon(Icons.sort),
                        onPressed: () => calls.add(i),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpWidget(host('library'));
      final search = find.byTooltip('搜索');
      final searchPosition = tester.getCenter(search);
      expect(find.byTooltip('功能0').hitTestable(), findsNothing);
      await picture('collapsed');
      await tester.tap(search);
      expect(calls, [9]);
      await tester.tap(find.byTooltip('展开功能'));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getCenter(search), searchPosition);
        expect(tester.takeException(), isNull);
      }
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byTooltip('功能$i'));
      }
      await tester.pumpAndSettle();
      expect(tester.getSize(find.text('音乐库')).width, greaterThan(20));
      await picture('expanded');
      expect(calls, [9, 0, 1, 2, 3]);
      await tester.tap(find.byTooltip('收起功能'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('功能0').hitTestable(), findsNothing);
      await tester.tap(find.byTooltip('展开功能'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(host('album'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('展开功能'), findsOneWidget);
      expect(find.byTooltip('功能0').hitTestable(), findsNothing);
    },
  );

  testWidgets('five selection actions fit a narrow toolbar with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(
            title: const Text(
              '已选择 100 首',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              SongSelectionActions(
                onSelectAll: () {},
                onDeselectAll: () {},
                onExit: () {},
                onHide: () {},
                onRestore: () {},
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byTooltip('隐藏歌曲').hitTestable(), findsOneWidget);
    expect(find.byTooltip('取消隐藏').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
