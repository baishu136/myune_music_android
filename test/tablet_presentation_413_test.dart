import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/widgets/lyrics_settings_drawer.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myune_music/mobile/mobile_shell.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/services/notification_service.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';

class _Library extends ChangeNotifier implements PlaylistContentNotifier {
  final songs = List.generate(
    24,
    (i) => Song(
      title: 'Song $i',
      artist: 'Artist',
      album: 'Album',
      filePath: '$i.mp3',
    ),
  );
  final cover = ValueNotifier(0);
  final target = ValueNotifier<String?>(null);
  final skipping = ValueNotifier(false);
  @override
  dynamic noSuchMethod(Invocation call) {
    switch (call.memberName) {
      case #currentSong:
        return songs.first;
      case #allSongsLoaded:
        return true;
      case #isAppForeground:
        return false;
      case #totalDuration:
        return const Duration(minutes: 3);
      case #playbackArtworkTargetListenable:
        return target;
      case #continuousSkipListenable:
        return skipping;
      case #playbackArtworkPrewarmPaths:
        return <String>[];
      case #playbackArtworkPrewarmListenable:
        return cover;
      case #prefetchSongCovers:
        return Future<void>.value();
      case #ensureSongThumbnail:
        return Future<Uint8List?>.value();
      case #artworkResolutionStateForPath:
        return ArtworkResolutionState.unavailable;
      case #beginArtworkPrefetchWindow:
        return null;
      case #allSongs:
      case #currentPlaylistSongs:
        return songs;
      case #selectedSongPaths:
        return <String>{};
      case #errorStream:
      case #infoStream:
        return const Stream<String>.empty();
      case #isContinuousSkipping:
      case #isLibraryPlaylistSelected:
      case #hasHiddenLibrarySongs:
      case #showHiddenLibrarySongs:
      case #isMultiSelectMode:
      case #isPlaying:
      case #isPinned:
        return false;
      case #libraryRevision:
      case #playlistRevision:
      case #artworkImageCacheGeneration:
        return 0;
      case #coverListenableForSongPath:
      case #artworkRecoveryListenable:
        return cover;
      case #allSongsVirtualPlaylist:
        return Playlist(id: 'library', name: 'Library');
      case #pinnedFirst:
        return call.positionalArguments[1];
      case #coverForSongPath:
      case #displayCoverForSong:
      case #displayThumbnailForSong:
      case #requestSongCover:
      case #releaseSongCover:
      case #recoverSongCover:
        return null;
      default:
        throw UnimplementedError('${call.memberName}');
    }
  }
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
      'misans',
    )..addFont(rootBundle.load('assets/fonts/MiSansVF.ttf'))).load();
  });
  testWidgets('50 point multiline lyrics reuse layout while scrolling', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1280);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = MobileLyricsListController();
    final active = ValueNotifier(2);
    final lines = List.generate(
      30,
      (i) => LyricLine(
        timestamp: Duration(seconds: i * 3),
        texts: ['较长的平板歌词行，包含英文字母 y g p $i', 'A translated line that wraps $i'],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: active,
            builder: (_, index, _) => MobileLyricsList(
              controller: controller,
              lines: lines,
              active: index,
              activeColor: Colors.white,
              position: Duration(seconds: index * 3),
              fontSize: 50,
              fontFamily: 'misans',
              karaokeLyricsEnabled: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    final layouts = controller.fullTextLayoutCount;
    for (var i = 3; i <= 6; i++) {
      active.value = i;
      for (var frame = 0; frame < 50; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }
    expect(controller.fullTextLayoutCount, layouts);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    active.dispose();
  });
  for (final size in [
    const Size(390, 844),
    const Size(800, 1280),
    const Size(1280, 800),
    const Size(900, 1400),
  ]) {
    testWidgets('tablet home uses phone navigation and single list $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      await settings.initializationFuture;
      final library = _Library();
      final notices = NotificationService();
      final capture = GlobalKey();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider<PlaylistContentNotifier>.value(
              value: library,
            ),
            ChangeNotifierProvider.value(value: notices),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'misans'),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(size.width == 900 ? 1.6 : 1),
              ),
              child: child!,
            ),
            home: RepaintBoundary(key: capture, child: const MobileShell()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
      final first = find.text('Song 0').first;
      final second = find.text('Song 1');
      expect(tester.getTopLeft(first).dx, tester.getTopLeft(second).dx);
      expect(
        tester.getTopLeft(second).dy,
        greaterThan(tester.getTopLeft(first).dy),
      );
      final output = Platform.environment['TABLET_PREVIEW_DIR'];
      if (output != null) {
        await tester.runAsync(() async {
          final image =
              await (capture.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$output/home-${size.width.toInt()}x${size.height.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      settings.dispose();
      library.cover.dispose();
      library.target.dispose();
      library.skipping.dispose();
      library.dispose();
      notices.dispose();
    });
  }

  test(
    'viewport limits and tablet size survive phone preview without mutation',
    () async {
      SharedPreferences.setMockInitialValues({'fontSize': 50.0});
      final settings = SettingsProvider();
      await settings.initializationFuture;
      expect(settings.lyricFontSizeFor(const Size(800, 1280)), 50);
      expect(settings.lyricFontSizeFor(const Size(1280, 800)), 50);
      expect(settings.lyricFontSizeFor(const Size(599, 1000)), 40);
      expect(settings.fontSize, 50);
      settings.previewFontSize(90, maximum: 50);
      expect(settings.fontSize, 50);
      settings.previewFontSize(double.nan, maximum: 50);
      expect(settings.fontSize, SettingsProvider.defaultLyricFontSize);
      settings.dispose();
    },
  );
  testWidgets('tablet lyric controls reach 50 and restore it after restart', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.initializationFuture;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: const MaterialApp(home: Scaffold(body: LyricsSettingsDrawer())),
      ),
    );
    final slider = tester.widget<Slider>(find.byType(Slider).first);
    expect(slider.max, 50);
    slider.onChanged!(50);
    await tester.pump();
    expect(settings.fontSize, 50);
    // A smaller app window clamps presentation without rewriting the tablet preference.
    tester.view.physicalSize = const Size(390, 1400);
    await tester.pump();
    final phone = tester.widget<Slider>(find.byType(Slider).first);
    expect(phone.max, 40);
    expect(phone.value, 40);
    expect(settings.fontSize, 50);
    tester.view.physicalSize = const Size(800, 1400);
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider).first).value, 50);
    final restored = SettingsProvider();
    await restored.initializationFuture;
    expect(restored.fontSize, 50);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
    restored.dispose();
  });
}
