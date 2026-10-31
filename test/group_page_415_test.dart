import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myune_music/mobile/mobile_shell.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/page/statistics_page/statistics_manager.dart';
import 'package:myune_music/page/statistics_page/statistics_models.dart';
import 'package:myune_music/services/cover_override_service.dart';
import 'package:myune_music/widgets/song_collection_header.dart';
import 'package:myune_music/services/song_sorting.dart';
import 'package:myune_music/services/interaction_performance_controller.dart';

class _Covers extends ChangeNotifier implements CoverOverrideService {
  @override
  Uint8List? groupCover({required bool artist, required String group}) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Library extends ChangeNotifier implements PlaylistContentNotifier {
  final songs = List.generate(
    3,
    (i) => Song(
      title: '歌曲 $i',
      artist: i == 2 ? 'Pinned' : 'Most',
      album: i == 2 ? 'Pinned' : 'Most',
      filePath: '$i.mp3',
      trackNumber: 3 - i,
    ),
  );
  final cover = ValueNotifier(0);
  final target = ValueNotifier<String?>(null);
  final skipping = ValueNotifier(false);
  Song? current;
  List<Song>? played;
  final hidden = <Song>[];
  final extra = <Song>[];
  final favorites = <Song>[];
  int groupReads = 0;
  SongSortPreference? sortPreference;
  List<String>? sortedOrder;
  int sortRevision = 0;
  @override
  Future<void> sortSongCollection({
    required bool artist,
    required String title,
    required List<Song> songs,
    required SortCriterion criterion,
    required bool descending,
  }) async {
    sortedOrder = await sortSongPathsByTrackNumber(
      paths: songs.map((s) => s.filePath).toList(),
      readTrackNumber: (path) async =>
          songs.firstWhere((s) => s.filePath == path).trackNumber,
      descending: descending,
    );
    sortPreference = SongSortPreference(
      criterion: criterion,
      descending: descending,
    );
    sortRevision++;
    notifyListeners();
  }

  Map<String, List<Song>> get groups {
    groupReads++;
    return {
      'Pinned': [songs.last],
      'Most': [
        ...songs.take(2),
        ...extra,
      ].where((s) => !hidden.contains(s)).toList(),
    };
  }

  @override
  dynamic noSuchMethod(Invocation call) {
    switch (call.memberName) {
      case #songsByArtist:
      case #songsByAlbum:
        return groups;
      case #libraryGroupsReady:
        return true;
      case #currentSong:
        return current;
      case #isAppForeground:
      case #isPlaying:
      case #isContinuousSkipping:
        return false;
      case #totalDuration:
        return const Duration(minutes: 3);
      case #libraryRevision:
        return hidden.length;
      case #playlistRevision:
      case #artworkImageCacheGeneration:
        return 0;
      case #collectionSortRevision:
        return sortRevision;
      case #songCollectionSortPreference:
        return sortPreference;
      case #songCollectionOrder:
        return restoreSongCollectionOrder(
          call.namedArguments[#songs] as List<Song>,
          sortedOrder,
        );
      case #isPinned:
        return call.positionalArguments[1] == 'Pinned';
      case #pinnedNamesFirst:
        return ['Pinned', 'Most'];
      case #pinnedFirst:
        return call.positionalArguments[1];
      case #artistSongsPinScope:
        return 'artistSongs:${call.positionalArguments[0]}';
      case #albumSongsPinScope:
        return 'albumSongs:${call.positionalArguments[0]}';
      case #coverListenableForSongPath:
      case #artworkRecoveryListenable:
      case #playbackArtworkPrewarmListenable:
        return cover;
      case #playbackArtworkTargetListenable:
        return target;
      case #continuousSkipListenable:
        return skipping;
      case #playbackArtworkPrewarmPaths:
        return <String>[];
      case #prefetchSongCovers:
        return Future<void>.value();
      case #ensureSongThumbnail:
        return Future<Uint8List?>.value();
      case #artworkResolutionStateForPath:
        return ArtworkResolutionState.unavailable;
      case #playFromDynamicList:
        played = List<Song>.from(call.positionalArguments[0] as Iterable);
        current = played![call.positionalArguments[1] as int];
        notifyListeners();
        return Future<void>.value();
      case #hideSongsFromLibrary:
        hidden.addAll(call.positionalArguments[0] as Iterable<Song>);
        notifyListeners();
        return Future<void>.value();
      case #addSongsToFavorites:
        favorites.addAll(call.positionalArguments[0] as Iterable<Song>);
        return Future<void>.value();
      case #beginArtworkPrefetchWindow:
      case #requestSongCover:
      case #releaseSongCover:
      case #recoverSongCover:
      case #displayCoverForSong:
      case #displayThumbnailForSong:
        return null;
      default:
        throw UnimplementedError('${call.memberName}');
    }
  }
}

void main() {
  setUp(
    () =>
        InteractionPerformanceController.instance.pulse(InteractionPhase.idle),
  );
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
      'misans',
    )..addFont(rootBundle.load('assets/fonts/MiSansVF.ttf'))).load();
  });
  for (final kind in ['歌手', '专辑']) {
    for (final compact in [false, true]) {
      testWidgets(
        '$kind header remains fixed while songs scroll and footer fills the inset: compact=$compact',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          final size = compact ? const Size(320, 520) : const Size(390, 844);
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          SharedPreferences.setMockInitialValues({});
          final settings = SettingsProvider();
          await settings.initializationFuture;
          final library = _Library();
          library.current = library.songs.first;
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(seconds: 1));
            library.cover.dispose();
            library.target.dispose();
            library.skipping.dispose();
            library.dispose();
            settings.dispose();
          });
          library.extra.addAll(
            List.generate(
              40,
              (i) => Song(
                title: '额外歌曲 $i',
                artist: 'Most',
                album: 'Most',
                filePath: 'extra$i.mp3',
              ),
            ),
          );
          final stats = StatisticsManager();
          stats.statisticsData.updateStats({
            '0.mp3': SongPlayStat(
              title: '歌曲 0',
              artist: 'Most',
              album: 'Most',
              path: '0.mp3',
              playCount: 8,
            ),
          });
          final capture = GlobalKey();
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: settings),
                ChangeNotifierProvider<PlaylistContentNotifier>.value(
                  value: library,
                ),
                ChangeNotifierProvider<CoverOverrideService>.value(
                  value: _Covers(),
                ),
                ChangeNotifierProvider.value(value: stats),
              ],
              child: MaterialApp(
                theme: ThemeData.dark(),
                builder: (_, child) => MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: TextScaler.linear(compact ? 1.8 : 1),
                    padding: const EdgeInsets.only(top: 24, bottom: 24),
                    viewPadding: const EdgeInsets.only(top: 24, bottom: 24),
                  ),
                  child: RepaintBoundary(key: capture, child: child!),
                ),
                home: Scaffold(
                  body: SongGroupTab(kind: kind, useHomeTheme: false),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 700));
          await tester.tap(find.byKey(ValueKey('$kind-featured-group')));
          await tester.pumpAndSettle();
          final header = find.byKey(const ValueKey('collection-detail-header'));
          final before = tester.getRect(header);
          final list = find.byType(Scrollable).last;
          await tester.drag(list, const Offset(0, -420));
          await tester.pumpAndSettle();
          expect(tester.getRect(header), before);
          expect(
            tester.state<ScrollableState>(list).position.pixels,
            greaterThan(300),
          );
          await tester.runAsync(() async {
            final image =
                await (capture.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final rgba = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            final bottom = ((image.height - 2) * image.width + 5) * 4;
            final player = ((image.height - 26) * image.width + 5) * 4;
            expect(
              rgba.sublist(bottom, bottom + 4),
              rgba.sublist(player, player + 4),
            );
            image.dispose();
          });
          await tester.ensureVisible(find.byTooltip('播放全部'));
          await tester.tap(find.byTooltip('播放全部'));
          await tester.pumpAndSettle();
          expect(library.played, hasLength(42));
          InteractionPerformanceController.instance.pulse(
            InteractionPhase.idle,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final kind in ['歌手', '专辑']) {
    testWidgets(
      '$kind featured priority, live details, playback and list actions',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        SharedPreferences.setMockInitialValues({});
        final settings = SettingsProvider();
        await settings.initializationFuture;
        final library = _Library();
        final stats = StatisticsManager();
        stats.statisticsData.updateStats({
          for (var i = 0; i < 3; i++)
            '$i.mp3': SongPlayStat(
              title: '歌曲 $i',
              artist: 'Artist',
              album: 'Album',
              path: '$i.mp3',
              playCount: i == 2 ? 7 : 4,
            ),
        });
        final capture = GlobalKey();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: settings),
              ChangeNotifierProvider<PlaylistContentNotifier>.value(
                value: library,
              ),
              ChangeNotifierProvider<CoverOverrideService>.value(
                value: _Covers(),
              ),
              ChangeNotifierProvider.value(value: stats),
            ],
            child: MaterialApp(
              theme: ThemeData.dark().copyWith(
                textTheme: ThemeData.dark().textTheme.apply(
                  fontFamily: 'misans',
                ),
              ),
              builder: (_, child) =>
                  RepaintBoundary(key: capture, child: child),
              home: Scaffold(
                body: SongGroupTab(kind: kind, useHomeTheme: false),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 700));
        expect(tester.takeException(), isNull);
        final featured = find.byKey(ValueKey('$kind-featured-group'));
        expect(featured, findsOneWidget);
        final readsBeforeDuration = library.groupReads;
        stats.recordPlaybackDuration(const Duration(seconds: 12));
        await tester.pump();
        await stats.flushPendingSave();
        expect(library.groupReads, readsBeforeDuration);
        expect(
          tester.getTopLeft(find.text('Most')).dy,
          lessThan(tester.getTopLeft(find.text('Pinned')).dy),
        );
        Future<void> picture(String suffix) async {
          final output = Platform.environment['GROUP415_PREVIEW_DIR'];
          if (output == null) return;
          await tester.runAsync(() async {
            final image =
                await (capture.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '$output/$kind-$suffix.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await picture('list');
        await tester.tap(featured);
        await tester.pumpAndSettle();
        expect(find.byType(AppBar), findsNothing);
        expect(
          find.byKey(const ValueKey('collection-detail-header')),
          findsOneWidget,
        );
        expect(find.text('已收听 8 次'), findsOneWidget);
        final toolbar = find.byKey(const ValueKey('collection-detail-toolbar'));
        final header = find.byKey(const ValueKey('collection-detail-header'));
        expect(
          tester.getRect(toolbar).bottom,
          lessThanOrEqualTo(tester.getRect(header).top),
        );
        expect(
          find.descendant(of: toolbar, matching: find.byTooltip('返回主页')),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('排序歌曲'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('按音轨号排序'));
        await tester.tap(find.text('按音轨号排序'));
        await tester.tap(find.text('应用排序'));
        await tester.pumpAndSettle();
        expect(library.sortPreference!.criterion, SortCriterion.trackNumber);
        expect(
          tester.getTopLeft(find.text('歌曲 1')).dy,
          lessThan(tester.getTopLeft(find.text('歌曲 0')).dy),
        );
        await picture('sorted');
        await tester.tap(find.byTooltip('播放全部'));
        await tester.pumpAndSettle();
        expect(library.played!.length, 2);
        expect(library.played!.first.filePath, '1.mp3');
        expect(find.byTooltip('返回主页'), findsOneWidget);
        await picture('details');
        await tester.tap(find.byTooltip('返回主页'));
        await tester.pumpAndSettle();
        await tester.tap(featured);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('排序歌曲'));
        await tester.pumpAndSettle();
        final radio = tester.widget<RadioGroup<SortCriterion>>(
          find.byType(RadioGroup<SortCriterion>),
        );
        expect(radio.groupValue, SortCriterion.trackNumber);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('多选'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('全选'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widgetList<Checkbox>(find.byType(Checkbox))
              .every((c) => c.value == true),
          isTrue,
        );
        await tester.tap(find.byTooltip('收藏'));
        await tester.pumpAndSettle();
        expect(library.favorites, hasLength(2));
        await tester.tap(find.byTooltip('多选'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('全选'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('隐藏歌曲'));
        await tester.pumpAndSettle();
        expect(library.hidden, hasLength(2));
        expect(find.text('共 0 首歌曲'), findsOneWidget);
        expect(find.text('没有歌曲'), findsOneWidget);
        await tester.tap(find.byTooltip('返回主页'));
        await tester.pumpAndSettle();
        expect(find.byType(SongCollectionHeader), findsOneWidget);
        if (kind == '歌手') {
          await settings.setArtistGroupViewMode(GroupViewMode.indexedGrid);
        } else {
          await settings.setAlbumGroupViewMode(GroupViewMode.indexedGrid);
        }
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('$kind-featured-group')), findsNothing);
        stats.statisticsData.updateStats({});
        if (kind == '歌手') {
          await settings.setArtistGroupViewMode(GroupViewMode.list);
        } else {
          await settings.setAlbumGroupViewMode(GroupViewMode.list);
        }
        await tester.pumpAndSettle();
        expect(find.byType(SongCollectionHeader), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        library.cover.dispose();
        library.target.dispose();
        library.skipping.dispose();
        library.dispose();
        settings.dispose();
      },
    );
  }
}
