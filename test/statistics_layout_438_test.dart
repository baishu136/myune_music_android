import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myune_music/page/pages/statistics_page.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/page/statistics_page/statistics_manager.dart';
import 'package:myune_music/page/statistics_page/statistics_models.dart';
import 'package:myune_music/theme/theme_provider.dart';
import 'package:myune_music/widgets/single_line_lyrics.dart';
import 'package:myune_music/widgets/balance_rate_control.dart';
import 'package:myune_music/widgets/side_selection_menu.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

class _Player extends Fake implements PlayerApi {}

class _Library extends ChangeNotifier implements PlaylistContentNotifier {
  final songs = List.generate(
    160,
    (i) => Song(
      title: 'Song$i',
      artist: 'Artist$i',
      album: 'Album$i',
      filePath: '/music/$i.mp3',
      duration: const Duration(minutes: 3),
    ),
  );
  final signal = ChangeNotifier();
  final leases = <String, int>{};
  int peak = 0;
  int revision = 0;
  void refreshArtwork() {
    revision++;
    notifyListeners();
    signal.notifyListeners();
  }

  String preset = '默认';
  List<double> gains = List.filled(10, 0);
  @override
  List<EqualizerPreset> get availableEqualizerPresets => [
    ...PlaylistContentNotifier.equalizerPresets,
    const EqualizerPreset('我的预设', [1, 2, 3, 2, 1, 0, -1, 0, 1, 2]),
  ];
  @override
  String get equalizerPresetName => preset;
  @override
  List<double> get equalizerGains => gains;
  @override
  double get currentPitch => 1;
  @override
  double get currentPlaybackRate => 1;
  @override
  bool get isExclusiveModeEnabled => false;
  @override
  Future<void> applyEqualizerPreset(EqualizerPreset value) async {
    preset = value.name;
    gains = value.gains;
    notifyListeners();
  }

  @override
  List<Song> get allSongs => songs;
  @override
  int get libraryRevision => revision;
  @override
  Song? get currentSong => null;
  @override
  List<LyricLine> get currentLyrics => [];
  @override
  int get currentLyricLineIndex => -1;
  @override
  Stream<int> get lyricLineIndexStream => const Stream.empty();
  @override
  Listenable coverListenableForSongPath(String path) => signal;
  @override
  Uint8List? displayThumbnailForSong(Song song) => null;
  @override
  void requestSongCover(
    String path, {
    ArtworkRequestPriority priority = ArtworkRequestPriority.visible,
    bool fullResolution = false,
  }) {
    leases.update(path, (n) => n + 1, ifAbsent: () => 1);
    if (leases.length > peak) peak = leases.length;
  }

  @override
  void releaseSongCover(String path, {bool fullResolution = false}) {
    expect(leases[path], isNotNull, reason: 'unbalanced cover release $path');
    if (leases[path] == 1) {
      leases.remove(path);
    } else {
      leases[path] = leases[path]! - 1;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Routes extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

const _preview = String.fromEnvironment('PREVIEW438');
Future<void> _capture(
  WidgetTester tester,
  GlobalKey capture,
  String name,
) async {
  if (_preview.isEmpty) return;
  await tester.runAsync(() async {
    final image =
        await (capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await Directory(_preview).create(recursive: true);
    await File('$_preview/$name.png').writeAsBytes(data.buffer.asUint8List());
    image.dispose();
  });
}

Future<(_Library, SettingsProvider, _Routes, GlobalKey)> _host(
  WidgetTester tester, {
  bool custom = false,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({
    'homeThemeImageEnabled': custom,
    'homeThemeImagePath': File('assets/images/icon/logo.png').absolute.path,
    'homeThemeImageDim': .31,
    'homeThemeImageBlur': 17.0,
  });
  final settings = SettingsProvider();
  await settings.initializationFuture;
  if (custom) {
    await tester.runAsync(() async {
      final provider = FileImage(File(settings.homeThemeImagePath!));
      final key = await provider.obtainKey(ImageConfiguration.empty);
      final codec = await ui.instantiateImageCodec(
        await provider.file.readAsBytes(),
      );
      final frame = await codec.getNextFrame();
      PaintingBinding.instance.imageCache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: frame.image)),
        ),
      );
      codec.dispose();
    });
  }
  final theme = ThemeProvider();
  final library = _Library();
  final manager = StatisticsManager();
  manager.statisticsData.updateStats({
    for (var i = 0; i < 160; i++)
      '/music/$i.mp3': SongPlayStat(
        title: 'Song$i',
        artist: 'Artist$i',
        album: 'Album$i',
        path: '/music/$i.mp3',
        playCount: 160 - i,
      ),
  }, totalPlaybackDuration: const Duration(hours: 12, minutes: 3));
  if (_preview.isNotEmpty) {
    await tester.runAsync(() async {
      await (FontLoader(
        'Preview438',
      )..addFont(rootBundle.load('assets/fonts/MiSansVF.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
  }
  final routes = _Routes(), capture = GlobalKey();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PlaylistContentNotifier>.value(value: library),
        ChangeNotifierProvider.value(value: manager),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: theme),
      ],
      child: MaterialApp(
        theme: ThemeData(
          brightness: brightness,
          fontFamily: _preview.isEmpty ? null : 'Preview438',
        ),
        navigatorObservers: [routes],
        builder: (_, child) => RepaintBoundary(key: capture, child: child!),
        home: const StatisticsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (custom && _preview.isNotEmpty) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
  }
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(library.leases, isEmpty);
    PaintingBinding.instance.imageCache.clear();
    library.signal.dispose();
    library.dispose();
    settings.dispose();
    theme.dispose();
    manager.statisticsData.updateStats({});
  });
  return (library, settings, routes, capture);
}

void main() {
  testWidgets('artwork updates leave ranking text and summary rows intact', (
    tester,
  ) async {
    final host = await _host(tester);
    final tile = find.byKey(const ValueKey('songs-/music/0.mp3'));
    final before = tester.widget<ListTile>(tile);
    host.$1.refreshArtwork();
    await tester.pump();
    expect(tester.widget<ListTile>(tile), same(before));
    expect(tester.takeException(), isNull);
  });

  testWidgets('six summary rows share one full width surface with left icons', (
    tester,
  ) async {
    final host = await _host(tester);
    const labels = ['总歌曲数', '总专辑数', '总歌手数', '总时长', '曲库空间', '累计播放时长'];
    Rect? previous;
    final headerCard = tester.widget<Card>(
      find.ancestor(of: find.text('统计信息'), matching: find.byType(Card)).first,
    );
    for (final label in labels) {
      final text = find.textContaining(label).first;
      final card = find.ancestor(of: text, matching: find.byType(Card)).first;
      expect(tester.widget<Card>(card), same(headerCard));
      expect(tester.getRect(card).width, greaterThan(330));
      final row = find.ancestor(of: text, matching: find.byType(Row)).first;
      final rect = tester.getRect(row);
      if (previous != null) {
        expect(rect.top, greaterThanOrEqualTo(previous.bottom));
      }
      final icon = find.descendant(of: row, matching: find.byType(Icon)).first;
      expect(tester.getCenter(icon).dx, lessThan(tester.getRect(text).left));
      previous = rect;
    }
    expect(find.byType(SingleLineLyricView), findsOneWidget);
    await _capture(tester, host.$4, 'statistics-light');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'custom background uses a transparent card shell without changing settings',
    (tester) async {
      final host = await _host(
        tester,
        custom: true,
        brightness: Brightness.dark,
      );
      final card = tester.widget<Card>(
        find
            .ancestor(
              of: find.textContaining('总歌曲数').first,
              matching: find.byType(Card),
            )
            .first,
      );
      expect(card.color, Colors.transparent);
      expect(host.$2.homeThemeImageDim, .31);
      expect(host.$2.homeThemeImageBlur, 17);
      expect(find.byType(SingleLineLyricView), findsOneWidget);
      await _capture(tester, host.$4, 'statistics-custom');
    },
  );

  testWidgets(
    'more opens independent complete rankings and loads only nearby covers',
    (tester) async {
      final host = await _host(tester);
      for (final pair in [
        ('歌曲播放排行', 'Song159'),
        ('艺术家播放排行', 'Artist159'),
        ('专辑播放排行', 'Album159'),
      ]) {
        final heading = find.text(pair.$1).first;
        final row = find
            .ancestor(of: heading, matching: find.byType(Row))
            .first;
        final more = find.descendant(
          of: row,
          matching: find.byType(TextButton),
        );
        await tester.ensureVisible(more);
        await tester.pumpAndSettle();
        final pushes = host.$3.pushes;
        await tester.tap(more);
        await tester.pumpAndSettle();
        expect(host.$3.pushes, pushes + 1);
        expect(find.text('收起'), findsNothing);
        final list = find.byType(ListView).last;
        await tester.scrollUntilVisible(
          find.text(pair.$2),
          500,
          scrollable: find
              .descendant(of: list, matching: find.byType(Scrollable))
              .first,
          maxScrolls: 50,
        );
        await tester.pumpAndSettle();
        expect(find.text(pair.$2).hitTestable(), findsOneWidget);
        expect(host.$1.leases.length, lessThan(60));
        if (pair.$1 == '歌曲播放排行') {
          await _capture(tester, host.$4, 'songs-complete');
        }
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
        expect(find.text('统计信息'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reset confirms first and invalidates ranking rows and cover leases',
    (tester) async {
      final host = await _host(tester);
      await tester.tap(find.byTooltip('重置统计数据'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(StatisticsManager().totalSongs, 160);
      await tester.tap(find.byTooltip('重置统计数据'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(StatisticsManager().totalSongs, 0);
      expect(find.text('暂无播放记录'), findsNWidgets(3));
      expect(find.textContaining('总歌曲数：160'), findsOneWidget);
      expect(host.$1.leases, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'distributed preset chips apply built-in and saved equalizer presets',
    (tester) async {
      tester.view.physicalSize = const Size(820, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final library = _Library();
      await tester.pumpWidget(
        ChangeNotifierProvider<PlaylistContentNotifier>.value(
          value: library,
          child: MaterialApp(
            home: Scaffold(
              body: BalanceRateControl(
                player: _Player(),
                iconColor: Colors.white,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('音效设置'));
      await tester.pumpAndSettle();
      expect(find.byType(SideSelectionMenu<String>), findsNothing);
      expect(
        find.byType(ChoiceChip),
        findsNWidgets(library.availableEqualizerPresets.length - 1),
      );
      await tester.tap(find.widgetWithText(ChoiceChip, '流行乐'));
      await tester.pumpAndSettle();
      expect(library.preset, '流行乐');
      final saved = find.widgetWithText(ChoiceChip, '我的预设');
      await tester.ensureVisible(saved);
      await tester.tap(saved);
      await tester.pumpAndSettle();
      expect(library.preset, '我的预设');
      expect(library.gains, [1, 2, 3, 2, 1, 0, -1, 0, 1, 2]);
      expect(tester.widget<ChoiceChip>(saved).selected, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      library.signal.dispose();
      library.dispose();
    },
  );
}
