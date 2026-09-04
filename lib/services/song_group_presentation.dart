import 'package:path/path.dart' as p;
import 'package:pinyin/pinyin.dart';

import '../page/playlist/playlist_models.dart';
import '../page/statistics_page/statistics_models.dart';

class SongGroupPresentation {
  const SongGroupPresentation._();

  static final Map<String, String> _alphabeticSortKeyCache = {};

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
    Song? best;
    for (final candidate in songs) {
      final current = best;
      if (current == null) {
        best = candidate;
        continue;
      }
      final candidateCount = playCount(candidate, normalizedCounts);
      final currentCount = playCount(current, normalizedCounts);
      if (candidateCount > currentCount) {
        best = candidate;
        continue;
      }
      if (candidateCount < currentCount) continue;
      final titleResult = candidate.title.toLowerCase().compareTo(
        current.title.toLowerCase(),
      );
      if (titleResult < 0 ||
          (titleResult == 0 &&
              candidate.normalizedPath.toLowerCase().compareTo(
                    current.normalizedPath.toLowerCase(),
                  ) <
                  0)) {
        best = candidate;
      }
    }
    return best;
  }

  static String alphabeticSortKey(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final cached = _alphabeticSortKeyCache[trimmed];
    if (cached != null) return cached;
    final pinyin = PinyinHelper.getPinyin(
      trimmed,
      separator: '',
    ).toLowerCase().trim();
    final result = pinyin.isEmpty ? trimmed.toLowerCase() : pinyin;
    if (_alphabeticSortKeyCache.length >= 4096) {
      _alphabeticSortKeyCache.clear();
    }
    _alphabeticSortKeyCache[trimmed] = result;
    return result;
  }

  static String initialSection(String value) {
    final key = alphabeticSortKey(value);
    if (key.isEmpty) return '#';
    final first = key[0].toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(first) ? first : '#';
  }

  static Map<String, List<T>> groupByInitial<T>(
    Iterable<T> values,
    String Function(T value) labelOf,
  ) {
    final sorted = values.toList(growable: false)
      ..sort((a, b) {
        final aLabel = labelOf(a);
        final bLabel = labelOf(b);
        final byPinyin = alphabeticSortKey(
          aLabel,
        ).compareTo(alphabeticSortKey(bLabel));
        return byPinyin != 0 ? byPinyin : aLabel.compareTo(bLabel);
      });
    final buckets = <String, List<T>>{};
    for (final value in sorted) {
      buckets
          .putIfAbsent(initialSection(labelOf(value)), () => <T>[])
          .add(value);
    }
    final sections = buckets.keys.toList(growable: false)
      ..sort((a, b) {
        if (a == '#') return b == '#' ? 0 : -1;
        if (b == '#') return 1;
        return a.compareTo(b);
      });
    return {for (final section in sections) section: buckets[section]!};
  }

  static ({List<T> pinned, List<T> regular}) separatePinned<T>(
    Iterable<T> values,
    bool Function(T value) isPinned,
  ) {
    final pinned = <T>[];
    final regular = <T>[];
    for (final value in values) {
      (isPinned(value) ? pinned : regular).add(value);
    }
    return (pinned: pinned, regular: regular);
  }
}
