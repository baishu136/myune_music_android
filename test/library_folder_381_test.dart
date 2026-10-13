import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';
import 'package:myune_music/page/setting/playlist_folder_manager.dart';
import 'package:myune_music/services/library_song_visibility.dart';
import 'package:myune_music/services/playlist_folder_policy.dart';

void main() {
  test(
    'automatic sort accepts cache filling but rejects changed rows or user rules',
    () {
      const title = SongSortPreference(
        criterion: SortCriterion.title,
        descending: false,
      );
      final rows = ['/a', '/b'];
      final before = songListSortSignature(rows, {});
      final after = songListSortSignature(rows, {
        p.normalize('/a'): const SongMetadataCacheEntry(
          title: 'Loaded title',
          artist: 'Singer',
          album: 'Album',
          modifiedMs: 1,
        ),
      });
      expect(after, isNot(before));
      expect(
        automaticSongSortStillApplies(
          sourcePaths: rows,
          currentPaths: rows,
          rule: title,
        ),
        isTrue,
      );
      expect(
        automaticSongSortStillApplies(
          sourcePaths: rows,
          currentPaths: ['/b', '/a'],
          rule: title,
        ),
        isFalse,
      );
      expect(
        automaticSongSortStillApplies(
          sourcePaths: rows,
          currentPaths: ['/a', '/c'],
          rule: title,
        ),
        isFalse,
      );
      expect(
        automaticSongSortStillApplies(
          sourcePaths: rows,
          currentPaths: rows,
          rule: title,
          currentRule: const SongSortPreference(
            criterion: SortCriterion.artist,
            descending: true,
          ),
        ),
        isFalse,
      );
    },
  );
  test(
    'batch hiding records every path and identity, even after duplicates',
    () {
      final visibility = LibrarySongVisibility();
      expect(
        visibility.hide(['/a', '/b', '/c', '/a'], ['a', 'b', 'c']),
        isTrue,
      );
      expect(visibility.paths, ['/a', '/b', '/c'].map(p.normalize).toSet());
      expect(visibility.identities, {'a', 'b', 'c'});
      for (final path in ['/a', '/b', '/c']) {
        expect(visibility.includes(path), isFalse);
      }
      expect(visibility.hide(['/a', '/d', '/e'], ['a', 'd', 'e']), isTrue);
      expect(visibility.includes('/other-copy', 'e'), isFalse);
      expect(visibility.hide(['/a', '/d'], ['a', 'd']), isFalse);
    },
  );

  test('show hidden is reversible and preserves persisted hiding', () {
    final visibility = LibrarySongVisibility()..hide(['/a', '/b'], ['song']);
    visibility.showHidden = true;
    expect(visibility.includes('/a', 'song'), isTrue);
    visibility.showHidden = false;
    expect(visibility.includes('/a'), isFalse);
    final restored = LibrarySongVisibility()
      ..paths.addAll(visibility.paths)
      ..identities.addAll(visibility.identities);
    expect(restored.hasHidden, isTrue);
    expect(restored.includes('/b'), isFalse);
    expect(restored.includes('/duplicate', 'song'), isFalse);
  });

  test(
    'an all-hidden or intentionally emptied library does not recover old rows',
    () {
      expect(
        shouldRecoverSavedLibraryOrder(
          hasSourcePaths: true,
          sourceWasSeen: false,
        ),
        isFalse,
      );
      expect(
        shouldRecoverSavedLibraryOrder(
          hasSourcePaths: false,
          sourceWasSeen: true,
        ),
        isFalse,
      );
      expect(
        shouldRecoverSavedLibraryOrder(
          hasSourcePaths: false,
          sourceWasSeen: false,
        ),
        isTrue,
      );
    },
  );

  test(
    'sort signature detects metadata changes without requiring added paths',
    () {
      const a = SongMetadataCacheEntry(
        title: 'A',
        artist: 'Singer',
        album: 'Album',
        modifiedMs: 1,
      );
      const b = SongMetadataCacheEntry(
        title: 'Z',
        artist: 'Singer',
        album: 'Album',
        modifiedMs: 1,
      );
      final key = p.normalize('/a');
      final old = songListSortSignature(['/a', '/b'], {key: a});
      expect(songListSortSignature(['/b', '/a'], {key: a}), old);
      expect(songListSortSignature(['/a', '/b'], {key: b}), isNot(old));
      expect(songListSortSignature(['/a'], {key: a}), isNot(old));
    },
  );

  test(
    'detaching folder preserves overlapping roots, other lists and growable rows',
    () {
      final playlist = Playlist(
        name: 'Folders',
        isFolderBased: true,
        folderPaths: ['/music', '/music/keep'],
        songFilePaths: [
          '/music/a.mp3',
          '/music/keep/b.mp3',
          '/music-other/c.mp3',
        ],
        songs: [
          for (final path in [
            '/music/a.mp3',
            '/music/keep/b.mp3',
            '/music-other/c.mp3',
          ])
            Song(title: path, artist: 'Singer', filePath: path),
        ],
      );
      expect(detachPlaylistFolder(playlist, '/music'), isTrue);
      expect(playlist.songFilePaths, [
        '/music/keep/b.mp3',
        '/music-other/c.mp3',
      ]);
      expect(
        playlist.songs!.map((song) => song.filePath),
        playlist.songFilePaths,
      );
      expect(playlist.isFolderBased, isTrue);
      expect(detachPlaylistFolder(playlist, '/music/keep'), isTrue);
      expect(playlist.songFilePaths, ['/music-other/c.mp3']);
      expect(playlist.isFolderBased, isFalse);
      expect(detachPlaylistFolder(playlist, '/unknown'), isFalse);
    },
  );

  test('ordinary playlists imported from folders are managed explicitly', () {
    final linked = Playlist(name: 'Linked', folderPaths: ['/music']);
    final unlinked = Playlist(name: 'Manual', songFilePaths: ['/music/a.mp3']);
    expect(folderPlaylistTracksImportedRoot(linked, '/music'), isTrue);
    expect(folderPlaylistTracksImportedRoot(unlinked, '/music'), isFalse);
    expect(songPathInFolder('/music-other/a.mp3', '/music'), isFalse);
  });

  test(
    'real recursive folder scan filters files, and inaccessible roots fail before mutation',
    () async {
      final root = await Directory.systemTemp.createTemp('myune-folder-381-');
      addTearDown(() async {
        final owned = p.normalize(root.absolute.path);
        expect(
          p.isWithin(p.normalize(Directory.systemTemp.absolute.path), owned),
          isTrue,
        );
        await root.delete(recursive: true);
      });
      await Directory(p.join(root.path, 'nested')).create();
      final audio = File(p.join(root.path, 'nested', 'song.MP3'));
      await audio.writeAsBytes([1]);
      await File(p.join(root.path, 'ignore.txt')).writeAsString('fixture');
      expect(await scanPlaylistFolder(root.path, ['.mp3']), {
        p.normalize(audio.path),
      });
      final playlist = Playlist(
        name: 'Live',
        folderPaths: [root.path],
        songFilePaths: [audio.path],
      );
      await expectLater(
        scanPlaylistFolder(p.join(root.path, 'missing'), ['.mp3']),
        throwsA(isA<FileSystemException>()),
      );
      expect(playlist.songFilePaths, [audio.path]);
      detachPlaylistFolder(playlist, root.path);
      expect(playlist.songFilePaths, isEmpty);
      expect(
        await audio.exists(),
        isTrue,
        reason: 'removal detaches; no physical deletion',
      );
    },
  );

  testWidgets(
    'advanced folder manager refreshes one root and removes only after confirmation',
    (tester) async {
      final notifier = _FolderNotifier();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PlaylistFolderManager(notifier: notifier)),
        ),
      );
      await tester.tap(find.text('歌单文件夹管理'));
      await tester.pumpAndSettle();
      expect(find.text('/music'), findsOneWidget);
      await tester.tap(find.byTooltip('刷新文件夹歌曲'));
      await tester.pumpAndSettle();
      expect(notifier.refreshed, '/music');
      await tester.tap(find.byTooltip('移除歌单文件夹'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(notifier.removed, isNull);
      await tester.tap(find.byTooltip('移除歌单文件夹'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '移除'));
      await tester.pumpAndSettle();
      expect(notifier.removed, '/music');
      expect(find.text('暂无已导入的歌单文件夹'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      notifier.dispose();
    },
  );
  testWidgets('legacy folder requires an explicit destination before refresh', (
    tester,
  ) async {
    final notifier = _FolderNotifier(legacy: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PlaylistFolderManager(notifier: notifier)),
      ),
    );
    await tester.tap(find.text('歌单文件夹管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('刷新文件夹歌曲'));
    await tester.pumpAndSettle();
    expect(find.text('选择关联歌单'), findsOneWidget);
    expect(notifier.refreshed, isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(notifier.linked, isFalse);
    await tester.tap(find.byTooltip('刷新文件夹歌曲'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Folder'));
    await tester.pumpAndSettle();
    expect(notifier.linked, isTrue);
    expect(notifier.refreshed, '/music');
    await tester.pumpWidget(const SizedBox());
    notifier.dispose();
    expect(tester.takeException(), isNull);
  });
}

class _FolderNotifier extends ChangeNotifier
    implements PlaylistContentNotifier {
  String? refreshed, removed;
  _FolderNotifier({bool legacy = false}) : linked = !legacy;
  bool linked;
  @override
  List<Playlist> get playlists => [
    Playlist(
      id: 'owner',
      name: 'Folder',
      folderPaths: linked ? ['/music'] : [],
    ),
  ];
  @override
  bool get isLoadingSongs => false;
  @override
  Future<List<String>> importedAudioFolders() async =>
      removed == null ? ['/music'] : [];
  @override
  Future<void> removeImportedAudioFolder(String root) async {
    removed = root;
  }

  @override
  Future<void> associateImportedAudioFolder(
    String root,
    String playlistId,
  ) async {
    expect(playlistId, 'owner');
    expect(root, '/music');
    linked = true;
  }

  @override
  Future<ImportedFolderRefreshSummary> refreshImportedAudioFolders({
    String? folderPath,
  }) async {
    refreshed = folderPath;
    return const ImportedFolderRefreshSummary(
      refreshedFolders: 1,
      skippedFolders: 0,
      addedSongs: 1,
      removedSongs: 0,
      failedFolders: [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
