import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';

Song _song(String name) =>
    Song(title: name, artist: 'Test', filePath: '/music/$name.mp3');

void main() {
  test(
    'import into a restored fixed-length song list preserves existing songs',
    () {
      final existing = _song('existing');
      final added = _song('added');
      final restored = [existing].toList(growable: false);
      final playlist = Playlist(
        name: 'Restored',
        songFilePaths: [existing.filePath],
      )..songs = restored;

      // Matches _ensurePlaylistSongs followed by _processSongsInBackground.
      playlist.songFilePaths.addAll([added.filePath]);
      playlist.songs!.addAll([added]);

      expect(playlist.songFilePaths, [existing.filePath, added.filePath]);
      expect(playlist.songs, [existing, added]);
      expect(restored, [existing]);
    },
  );

  test('an empty fixed-length song list can receive the first import', () {
    final added = _song('first');
    final playlist = Playlist(name: 'Empty')
      ..songs = <Song>[].toList(growable: false);

    playlist.songFilePaths.add(added.filePath);
    playlist.songs!.add(added);
    expect(playlist.songs!.single, same(added));
  });

  test('constructor owns growable copies of fixed and unmodifiable lists', () {
    final song = _song('existing');
    final paths = List<String>.unmodifiable([song.filePath]);
    final songs = List<Song>.unmodifiable([song]);
    const folders = ['/music'];
    final playlist = Playlist(
      name: 'Owned',
      songFilePaths: paths,
      songs: songs,
      folderPaths: folders,
    );

    playlist.songFilePaths.clear();
    playlist.songs!.clear();
    playlist.folderPaths.add('/other');
    expect(paths, [song.filePath]);
    expect(songs, [song]);
    expect(folders, ['/music']);
  });

  test('replacement paths and folders remain editable after restoration', () {
    final playlist = Playlist(name: 'Replacement')
      ..songFilePaths = ['a', 'b'].toList(growable: false)
      ..folderPaths = const ['/music'];

    playlist.songFilePaths.removeAt(0);
    playlist.songFilePaths.insert(0, 'c');
    playlist.folderPaths.removeWhere((path) => path == '/music');
    playlist.folderPaths.add('/other');
    expect(playlist.songFilePaths, ['c', 'b']);
    expect(playlist.folderPaths, ['/other']);
  });

  test('folder refresh can remove and append without mutating its input', () {
    final old = _song('old');
    final kept = _song('kept');
    final added = _song('new');
    final source = [old, kept].toList(growable: false);
    final playlist = Playlist(
      name: 'Folder',
      isFolderBased: true,
      songFilePaths: [old.filePath, kept.filePath].toList(growable: false),
      songs: source,
    );

    playlist.songFilePaths.removeWhere((path) => path == old.filePath);
    playlist.songFilePaths.add(added.filePath);
    playlist.songs!.removeWhere((song) => song.filePath == old.filePath);
    playlist.songs!.add(added);
    expect(playlist.songFilePaths, [kept.filePath, added.filePath]);
    expect(playlist.songs, [kept, added]);
    expect(source, [old, kept]);
  });

  test('rollback removes imported entries only and retains old order', () {
    final first = _song('first');
    final second = _song('second');
    final added = _song('added');
    final playlist = Playlist(
      name: 'Rollback',
      songFilePaths: [first.filePath, second.filePath].toList(growable: false),
      songs: [first, second].toList(growable: false),
    );

    playlist.songFilePaths.add(added.filePath);
    playlist.songs!.add(added);
    playlist.songFilePaths.removeWhere((path) => path == added.filePath);
    playlist.songs!.removeWhere((song) => song.filePath == added.filePath);
    expect(playlist.songFilePaths, [first.filePath, second.filePath]);
    expect(playlist.songs, [first, second]);
  });

  test('null songs still denotes an unloaded playlist', () {
    final playlist = Playlist(name: 'Lazy');
    expect(playlist.songs, isNull);
    playlist.songs = [_song('loaded')];
    playlist.songs = null;
    expect(playlist.songs, isNull);
    final restored = Playlist.fromJson(playlist.toJson());
    restored.folderPaths.add('/music');
    restored.songFilePaths.add('/music/song.mp3');
    expect(restored.songs, isNull);
  });
}
