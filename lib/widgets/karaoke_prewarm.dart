part of 'mobile_lyrics_list.dart';

/// A list-local, single spare cache, not a second cache for mounted rows.
/// Adoption transfers ownership to the row. Invalidated/stale spares are
/// explicitly disposed, so warming never retains an entire song's Pictures.
class _KaraokePrewarmSlot {
  final mounted = <Object>{};
  final warmers = <Object, VoidCallback>{};
  Object? identity;
  _KaraokePaintCache? cache;

  void clear() {
    cache?.dispose();
    cache = null;
    identity = null;
  }

  _KaraokePaintCache? take(Object key) {
    if (identity != key) return null;
    final prepared = cache;
    cache = null;
    identity = null;
    return prepared;
  }
}

List<_KaraokeTokenRange> _karaokeRanges(LyricLine line) {
  final ranges = <_KaraokeTokenRange>[];
  final tokenRows = line.tokens ?? const <List<LyricToken>>[];
  var rowOffset = 0;
  for (var rowIndex = 0; rowIndex < line.texts.length; rowIndex++) {
    final rowText = line.texts[rowIndex];
    var searchOffset = 0;
    if (karaokeRowCanHighlight(rowIndex) && rowIndex < tokenRows.length) {
      for (final token in tokenRows[rowIndex]) {
        if (token.text == '\u200B') continue;
        var localStart = rowText.indexOf(token.text, searchOffset);
        if (localStart < 0 &&
            searchOffset + token.text.length <= rowText.length) {
          localStart = searchOffset;
        }
        if (localStart < 0) continue;
        final localEnd = (localStart + token.text.length).clamp(
          localStart,
          rowText.length,
        );
        final visible = karaokeVisibleTokenBounds(token.text);
        if (visible != null) {
          ranges.add(
            _KaraokeTokenRange(
              token: token,
              start: rowOffset + localStart + visible.start,
              end: rowOffset + localStart + visible.end,
            ),
          );
        }
        searchOffset = localEnd;
      }
    }
    rowOffset += rowText.length + (rowIndex + 1 < line.texts.length ? 1 : 0);
  }
  return ranges;
}
