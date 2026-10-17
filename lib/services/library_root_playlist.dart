import '../page/playlist/playlist_models.dart';

/// Keep existing IDs, favorites and folder associations; only add ownership.
List<Playlist> ensureLibraryRoot(List<Playlist> playlists) {
  final roots = playlists.where((item) => item.isLibrary).toList();
  final root = roots.isEmpty
      ? Playlist(id: Playlist.libraryId, name: '总歌曲', isDefault: true)
      : roots.first;
  root.name = '总歌曲';
  root.songFilePaths = {
    ...root.songFilePaths,
    ...playlists.expand((item) => item.songFilePaths),
  }.toList();
  final others = playlists.where((item) => !item.isLibrary).toList();
  if (!others.any((item) => item.isDefault || item.name == '收藏')) {
    others.insert(0, Playlist(name: '收藏', isDefault: true));
  }
  return [root, ...others];
}
