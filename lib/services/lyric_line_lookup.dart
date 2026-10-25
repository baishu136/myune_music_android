import '../page/playlist/playlist_models.dart';

/// Sorted LRC timestamps: keep the current interval cheap, seek by binary search.
/// Equal timestamps belong to the final matching line, including after a seek.
int lyricLineIndexAt(
  List<LyricLine> lines,
  Duration position, {
  int hint = -1,
}) {
  final count = lines.length;
  if (count == 0) return -1;
  if (hint >= 0 && hint < count) {
    if (lines[hint].timestamp <= position &&
        (hint + 1 == count || position < lines[hint + 1].timestamp)) {
      return hint;
    }
    final next = hint + 1;
    if (next < count &&
        lines[next].timestamp <= position &&
        (next + 1 == count || position < lines[next + 1].timestamp)) {
      return next;
    }
  }
  var low = 0, high = count;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (lines[middle].timestamp <= position) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low - 1;
}
