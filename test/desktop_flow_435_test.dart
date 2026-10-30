import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myune_music/models/song_playlist_draft.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/page/setting/tabs/custom_theme_settings_section.dart';
import 'package:myune_music/theme/theme_provider.dart';
import 'package:myune_music/widgets/custom_theme_background.dart';
import 'package:myune_music/widgets/playback_control_sheet_surface.dart';
import 'package:myune_music/widgets/side_selection_menu.dart';
import 'package:myune_music/widgets/song_playlist_sheet.dart';
import 'playback_pages_402_test.dart' as fixture;

class _Library extends fixture.PlaylistWindowFixture408 {
  int adds = 0, removes = 0;
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<int> addSongsToPlaylistById(String id, List<String> paths) async {
    adds++;
    await gate?.future;
    if (fail) throw StateError('save failed');
    return super.addSongsToPlaylistById(id, paths);
  }

  @override
  Future<int> removeSongsFromPlaylistById(String id, List<String> paths) async {
    removes++;
    await gate?.future;
    if (fail) throw StateError('save failed');
    return super.removeSongsFromPlaylistById(id, paths);
  }
}

final _song = Song(title: '当前歌曲', artist: '歌手', filePath: 'current.mp3');
const _preview = String.fromEnvironment('PREVIEW435');
GlobalKey? _windowCapture;
Future<void> _fonts(WidgetTester tester) async {
  if (_preview.isEmpty) return;
  await tester.runAsync(() async {
    await (FontLoader(
      'Preview435',
    )..addFont(rootBundle.load('assets/fonts/MiSansVF.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (_preview.isEmpty) return;
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_preview).create(recursive: true);
    await File('$_preview/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _open(WidgetTester tester, _Library model) async {
  await _fonts(tester);
  _windowCapture = GlobalKey();
  await tester.pumpWidget(
    ChangeNotifierProvider<PlaylistContentNotifier>.value(
      value: model,
      child: MaterialApp(
        theme: ThemeData(fontFamily: _preview.isEmpty ? null : 'Preview435'),
        builder: (_, child) =>
            RepaintBoundary(key: _windowCapture, child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showSongPlaylistWindow(context, _song, fluid: true),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'theme configuration keeps transparent card shells, a forty percent mask and theme foreground',
    (tester) async {
      late Directory temporary;
      late File background;
      await tester.runAsync(() async {
        temporary = await Directory.systemTemp.createTemp('myune435-theme-');
        background = File('${temporary.path}/background.png');
        final bytes = await rootBundle.load('assets/images/icon/logo.png');
        await background.writeAsBytes(bytes.buffer.asUint8List());
      });
      SharedPreferences.setMockInitialValues({
        'homeThemeImageEnabled': true,
        'homeThemeImagePath': background.path,
        'homeThemeImageDim': .8,
      });
      final settings = SettingsProvider();
      await settings.initializationFuture;
      final theme = ThemeProvider();
      await _fonts(tester);
      final capture = GlobalKey();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: theme),
          ],
          child: MaterialApp(
            theme: ThemeData(
              brightness: Brightness.light,
              fontFamily: _preview.isEmpty ? null : 'Preview435',
            ),
            builder: (_, child) => RepaintBoundary(key: capture, child: child!),
            home: const ThemeConfigurationPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final surface = tester.widget<CustomThemeBackground>(
        find.byType(CustomThemeBackground),
      );
      expect(surface.dim, .4);
      expect(surface.brightnessOverride, Brightness.dark);
      expect(
        tester
            .widgetList<Card>(find.byType(Card))
            .every((c) => c.color == Colors.transparent),
        isTrue,
      );
      expect(
        Theme.of(tester.element(find.text('背景风格跟随音乐封面'))).colorScheme.onSurface,
        ThemeData(brightness: Brightness.light).colorScheme.onSurface,
      );
      expect(settings.homeThemeImageDim, .8);
      await _capture(tester, capture, 'theme-configuration');
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
      theme.dispose();
      await tester.runAsync(() async {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        for (var attempt = 0; attempt < 4; attempt++) {
          try {
            await background.delete();
            await temporary.delete();
            break;
          } on FileSystemException catch (error) {
            if (error.osError?.errorCode != 32) rethrow;
            // Windows can retain the decoded file mapping until raster cleanup.
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }
      });
    },
  );

  test(
    'draft undo writes nothing and new playlists are local until commit',
    () {
      final p = Playlist(name: '歌单');
      final draft = SongPlaylistDraft(_song);
      draft.setIncluded(p, true);
      expect(draft.includes(p), isTrue);
      expect(p.songFilePaths, isEmpty);
      draft.setIncluded(p, false);
      expect(draft.changes, isEmpty);
      draft.create('新歌单');
      expect(draft.created.single.name, '新歌单');
      expect(draft.includes(draft.created.single), isTrue);
      draft.setIncluded(draft.created.single, false);
      expect(draft.includes(draft.created.single), isFalse);
    },
  );

  test(
    'desktop multiline limits and transition persist independently',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = SettingsProvider();
      await first.initializationFuture;
      expect(first.desktopLyricsMaxLines, 3);
      expect(first.desktopLyricsMinFontSize, 12);
      expect(first.desktopLyricsTransition, isTrue);
      await first.setDesktopLyricsMaxLines(5);
      await first.setDesktopLyricsMinFontSize(13.7);
      await first.setDesktopLyricsTransition(false);
      final restored = SettingsProvider();
      await restored.initializationFuture;
      expect(restored.desktopLyricsMaxLines, 5);
      expect(restored.desktopLyricsMinFontSize, 14);
      expect(restored.desktopLyricsTransition, isFalse);
      expect(restored.desktopLyricsKaraoke, isFalse);
      await restored.setDesktopLyricsMaxLines(100);
      await restored.setDesktopLyricsMinFontSize(-100);
      expect(restored.desktopLyricsMaxLines, 6);
      expect(restored.desktopLyricsMinFontSize, 8);
      await restored.setDesktopLyricsMinFontSize(double.nan);
      expect(restored.desktopLyricsMinFontSize, 8);
      first.dispose();
      restored.dispose();
    },
  );

  testWidgets(
    'membership waits until reverse transition finishes and commits final intent once',
    (tester) async {
      final model = _Library()..gate = Completer<void>();
      await _open(tester, model);
      await tester.tap(
        find.byKey(const ValueKey('song-playlist-selection-favorite')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('song-playlist-selection-other')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('song-playlist-selection-other')),
      );
      await tester.pump();
      expect(model.adds, 0);
      expect(model.playlists[1].songFilePaths, isEmpty);
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(const ValueKey('song-playlist-selection-favorite')),
            )
            .value,
        isTrue,
      );
      await _capture(tester, _windowCapture!, 'playlist-draft');
      await tester.tap(find.text('完成'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(model.adds, 0);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('song-playlist-floating-window')),
        findsNothing,
      );
      expect(model.adds, 1);
      model.gate!.complete();
      await tester.pumpAndSettle();
      expect(model.playlists[1].songFilePaths, ['current.mp3']);
      expect(model.playlists[2].songFilePaths, isEmpty);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );

  testWidgets(
    'back dismissal commits removals and storage failure is reported after close',
    (tester) async {
      final model = _Library()..fail = true;
      model.playlists[1].songFilePaths.add('current.mp3');
      await _open(tester, model);
      await tester.tap(
        find.byKey(const ValueKey('song-playlist-selection-favorite')),
      );
      await tester.pump();
      expect(model.removes, 0);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      expect(model.removes, 1);
      expect(model.playlists[1].songFilePaths, ['current.mp3']);
      expect(find.text('部分歌单未能更新，请重新打开检查'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );

  testWidgets(
    'choice menu has bounded width, rounded options and preserves playback background',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = 1;
      await _fonts(tester);
      final capture = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: _preview.isEmpty ? null : 'Preview435'),
          builder: (_, child) => RepaintBoundary(key: capture, child: child!),
          home: Scaffold(
            body: PlaybackControlSheetSurface(
              fluid: true,
              child: SideSelectionMenu<int>(
                title: '对齐',
                selected: {selected},
                segments: const [
                  ButtonSegment(value: 1, label: Text('左对齐')),
                  ButtonSegment(value: 2, label: Text('右对齐')),
                ],
                onSelectionChanged: (v) => selected = v.first,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(SideSelectionMenu<int>));
      await tester.pumpAndSettle();
      final surface = find.byType(PlaybackControlSheetSurface).last;
      expect(tester.getRect(surface).left, greaterThan(0));
      expect(tester.getRect(surface).right, lessThanOrEqualTo(320));
      expect(tester.widget<PlaybackControlSheetSurface>(surface).fluid, isTrue);
      expect(
        tester.widget<PlaybackControlSheetSurface>(surface).borderRadius,
        BorderRadius.circular(8),
      );
      final option = find.byKey(const ValueKey('side-selection-2'));
      final button = tester.widget<OutlinedButton>(option);
      final shape = button.style!.shape!.resolve({})! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(8));
      await _capture(tester, capture, 'side-drawer');
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(selected, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
