import 'dart:math';

import 'package:pinyin/pinyin.dart';

import '../page/playlist/playlist_models.dart';

class _SongSearchIndex {
  _SongSearchIndex(this.song)
    : fields = [
        song.title,
        song.artist,
        song.album,
      ].map((value) => value.toLowerCase()).toList(),
      pinyin = [song.title, song.artist, song.album].map(_fullPinyin).toList(),
      initials = [song.title, song.artist, song.album].map(_initials).toList();

  final Song song;
  final List<String> fields;
  final List<String> pinyin;
  final List<String> initials;

  static String _fullPinyin(String text) =>
      PinyinHelper.getPinyin(text, separator: '').toLowerCase();

  static String _initials(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final value = PinyinHelper.getPinyin(char, separator: '').toLowerCase();
      buffer.write(
        value.isNotEmpty && value != char.toLowerCase()
            ? value[0]
            : char.toLowerCase(),
      );
    }
    return buffer.toString();
  }
}

/// Ranked search for Chinese metadata, pinyin, initials and small typos.
class SearchService {
  final Map<String, _SongSearchIndex> _cache = {};

  void rebuild(Iterable<Song> songs) {
    final paths = songs.map((song) => song.normalizedPath).toSet();
    _cache.removeWhere((path, _) => !paths.contains(path));
    for (final song in songs) {
      _cache[song.normalizedPath] = _SongSearchIndex(song);
    }
  }

  List<Song> search(String keyword, Iterable<Song> songs) {
    final source = songs.toList();
    final query = keyword.trim().toLowerCase();
    if (query.isEmpty) return source;

    final scored = <({Song song, double score, int order})>[];
    for (var i = 0; i < source.length; i++) {
      final song = source[i];
      final index = _cache.putIfAbsent(
        song.normalizedPath,
        () => _SongSearchIndex(song),
      );
      var best = -1.0;
      for (var field = 0; field < index.fields.length; field++) {
        final text = index.fields[field];
        final fieldWeight = field == 0
            ? 20.0
            : field == 1
            ? 10.0
            : 4.0;
        if (text == query) best = max(best, 120 + fieldWeight);
        if (text.startsWith(query)) best = max(best, 105 + fieldWeight);
        if (text.contains(query)) best = max(best, 90 + fieldWeight);

        final initials = index.initials[field];
        if (initials == query) best = max(best, 88 + fieldWeight);
        if (initials.startsWith(query)) best = max(best, 82 + fieldWeight);
        if (initials.contains(query)) best = max(best, 76 + fieldWeight);

        final pinyin = index.pinyin[field];
        if (pinyin == query) best = max(best, 74 + fieldWeight);
        if (pinyin.startsWith(query)) best = max(best, 68 + fieldWeight);
        if (pinyin.contains(query)) best = max(best, 62 + fieldWeight);

        final fuzzy = _fuzzyScore(query, text);
        if (fuzzy > 0) best = max(best, fuzzy + fieldWeight);
      }
      if (best > 0) scored.add((song: song, score: best, order: i));
    }
    scored.sort((a, b) {
      final score = b.score.compareTo(a.score);
      return score == 0 ? a.order.compareTo(b.order) : score;
    });
    return scored.map((entry) => entry.song).toList();
  }

  double _fuzzyScore(String query, String target) {
    if (query.isEmpty || target.isEmpty) return -1;
    var queryIndex = 0;
    var previous = -2;
    var score = 0.0;
    for (var i = 0; i < target.length && queryIndex < query.length; i++) {
      if (target[i] != query[queryIndex]) continue;
      score += previous + 1 == i ? 4 : 1;
      if (i == 0 || target[i - 1] == ' ' || target[i - 1] == '-') score += 6;
      previous = i;
      queryIndex++;
    }
    return queryIndex == query.length
        ? score + (query.length / target.length) * 5
        : -1;
  }
}
