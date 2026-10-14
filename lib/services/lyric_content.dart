import '../page/playlist/playlist_models.dart';

bool sameLyricContent(List<LyricLine> a, List<LyricLine> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i], y = b[i];
    if (x.timestamp != y.timestamp ||
        x.isInterlude != y.isInterlude ||
        x.interludeDuration != y.interludeDuration ||
        x.allowSyntheticKaraoke != y.allowSyntheticKaraoke ||
        x.texts.length != y.texts.length) {
      return false;
    }
    for (var j = 0; j < x.texts.length; j++) {
      if (x.texts[j] != y.texts[j]) return false;
    }
    final xt = x.tokens, yt = y.tokens;
    if (xt == null || yt == null) {
      if (xt != yt) return false;
      continue;
    }
    if (xt.length != yt.length) return false;
    for (var j = 0; j < xt.length; j++) {
      if (xt[j].length != yt[j].length) return false;
      for (var k = 0; k < xt[j].length; k++) {
        final p = xt[j][k], q = yt[j][k];
        if (p.text != q.text || p.start != q.start || p.end != q.end) {
          return false;
        }
      }
    }
  }
  return true;
}
