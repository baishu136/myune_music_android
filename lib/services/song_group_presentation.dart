import 'package:path/path.dart' as p;

import '../page/playlist/playlist_models.dart';
import '../page/statistics_page/statistics_models.dart';

class SongGroupPresentation {
  const SongGroupPresentation._();

  static String _normalize(String path) =>
      p.normalize(path).replaceAll('\\', '/').toLowerCase();

  static Map<String, int> normalizedPlayCounts(
    Map<String, SongPlayStat> statistics,
  ) => {
    for (final entry in statistics.entries)
      _normalize(entry.key): entry.value.playCount,
  };

  static int playCount(Song song, Map<String, int> normalizedCounts) =>
      normalizedCounts[_normalize(song.normalizedPath)] ?? 0;

  static List<Song> sortByPlayCount(
    Iterable<Song> songs,
    Map<String, int> normalizedCounts,
  ) {
    final sorted = songs.toList(growable: false);
    sorted.sort((a, b) {
      final countResult = playCount(
        b,
        normalizedCounts,
      ).compareTo(playCount(a, normalizedCounts));
      if (countResult != 0) return countResult;
      final titleResult = a.title.toLowerCase().compareTo(
        b.title.toLowerCase(),
      );
      if (titleResult != 0) return titleResult;
      return a.normalizedPath.toLowerCase().compareTo(
        b.normalizedPath.toLowerCase(),
      );
    });
    return sorted;
  }

  static Song? representativeSong(
    Iterable<Song> songs,
    Map<String, int> normalizedCounts,
  ) {
    final sorted = sortByPlayCount(songs, normalizedCounts);
    return sorted.isEmpty ? null : sorted.first;
  }
}
