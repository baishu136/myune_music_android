import '../page/playlist/playlist_models.dart';

/// Edits belong to the open window and are committed only after it closes.
class SongPlaylistDraft {
  SongPlaylistDraft(this.song);
  final Song song;
  final changes = <String, bool>{};
  final _original = <String, bool>{};
  final created = <Playlist>[];
  bool includes(Playlist p) =>
      changes[p.id] ?? p.containsSongPath(song.filePath);
  void setIncluded(Playlist p, bool included) {
    final original = _original.putIfAbsent(
      p.id,
      () => p.containsSongPath(song.filePath),
    );
    if (included == original) {
      changes.remove(p.id);
    } else {
      changes[p.id] = included;
    }
  }

  void create(String name) => created.add(
    Playlist(name: name, songFilePaths: [song.filePath], songs: [song]),
  );
}
