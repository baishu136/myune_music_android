import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../page/playlist/playlist_models.dart';
import '../widgets/synthetic_karaoke_timing.dart';

/// Maximise the smaller contrast against the fill and the actual outline.
/// An explicit user colour is stored separately and never replaced by this.
int desktopLyricHighlightColor(int fill, int outline) {
  final a = Color(fill).computeLuminance();
  final b = Color(outline).computeLuminance();
  double contrast(double x, double y) =>
      (math.max(x, y) + .05) / (math.min(x, y) + .05);
  final middle =
      math.sqrt((math.min(a, b) + .05) * (math.max(a, b) + .05)) - .05;
  final candidates = <int>[0xFF000000, 0xFFFFFFFF];
  final channel = middle <= .0031308
      ? middle * 12.92
      : 1.055 * math.pow(middle, 1 / 2.4) - .055;
  final grey = (channel * 255).round().clamp(0, 255);
  candidates.add(0xFF000000 | (grey << 16) | (grey << 8) | grey);
  double score(int c) {
    final luminance = Color(c).computeLuminance();
    return math.min(contrast(luminance, a), contrast(luminance, b));
  }

  return candidates.reduce((best, c) => score(c) > score(best) ? c : best);
}

class DesktopLyricPresentation {
  const DesktopLyricPresentation(this.text, this.words);
  final String text;
  final List<Map<String, int>> words;

  static DesktopLyricPresentation fromLine(
    LyricLine? line, {
    required bool karaoke,
    Duration? nextTimestamp,
  }) {
    if (line == null) {
      return const DesktopLyricPresentation('暂无歌词', []);
    }
    final rows = <int>[
      for (var i = 0; i < line.texts.length; i++)
        if (line.texts[i].trim().isNotEmpty) i,
    ].take(2).toList();
    final text = rows.map((i) => line.texts[i]).join('\n');
    if (!karaoke || line.isInterlude || rows.isEmpty) {
      return DesktopLyricPresentation(text.isEmpty ? '♪' : text, const []);
    }
    // Real timings win. Ordinary LRC can only provide an estimated sweep;
    // translation rows without supplied timings keep their normal colour.
    final timed = line.hasTimedWords
        ? line
        : synthesizeKaraokeTiming(line, nextTimestamp: nextTimestamp);
    final words = <Map<String, int>>[];
    var rowOffset = 0;
    for (final row in rows) {
      final tokens = timed.tokens;
      if (tokens != null && row < tokens.length) {
        final source = line.texts[row];
        final rowTokens = tokens[row];
        // Mismatched provider text must not colour unrelated characters.
        if (rowTokens.map((t) => t.text).join() == source &&
            rowTokens.every(
              (t) => t.start >= Duration.zero && t.end >= t.start,
            )) {
          var offset = rowOffset;
          for (final token in rowTokens) {
            if (token.text.isNotEmpty) {
              words.add({
                'offset': offset,
                'length': token.text.length,
                'start': token.start.inMilliseconds,
                'end': token.end.inMilliseconds,
              });
            }
            offset += token.text.length;
          }
        }
      }
      rowOffset += line.texts[row].length + 1;
    }
    return DesktopLyricPresentation(text, words);
  }
}
