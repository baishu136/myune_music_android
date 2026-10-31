import '../page/playlist/playlist_models.dart';

/// Read metadata only when a sort is requested, never during list building.
Future<List<String>> sortSongPathsByTrackNumber({
  required List<String> paths,
  required Future<int?> Function(String path) readTrackNumber,
  required bool descending,
}) async {
  final entries = <({String path, int? track, int index})>[];
  for (var i = 0; i < paths.length; i++) {
    final track = await readTrackNumber(paths[i]);
    entries.add((
      path: paths[i],
      track: track != null && track > 0 ? track : null,
      index: i,
    ));
  }
  entries.sort((a, b) {
    // Missing/invalid tags remain last in either direction. Equal numbers
    // retain their input order, including songs from different albums.
    if (a.track == null && b.track != null) return 1;
    if (b.track == null && a.track != null) return -1;
    final byTrack = a.track == null ? 0 : a.track!.compareTo(b.track!);
    if (byTrack != 0) return descending ? -byTrack : byTrack;
    return a.index.compareTo(b.index);
  });
  return entries.map((entry) => entry.path).toList();
}

/// Retain saved order while accepting newly imported songs and removals.
List<Song> restoreSongCollectionOrder(List<Song> songs, List<String>? order) {
  if (order == null) return songs;
  final remaining = {for (final song in songs) song.filePath: song};
  final result = <Song>[];
  for (final path in order) {
    final song = remaining.remove(path);
    if (song != null) result.add(song);
  }
  for (final song in songs) {
    if (remaining.remove(song.filePath) != null) result.add(song);
  }
  return result;
}
