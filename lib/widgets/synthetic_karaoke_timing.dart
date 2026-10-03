import 'dart:math' as math;

import 'package:characters/characters.dart';

import '../page/playlist/playlist_models.dart';

bool karaokeRowCanHighlight(int rowIndex) => rowIndex == 0;

bool hasUsableKaraokeTiming(LyricLine line) =>
    line.tokens != null &&
    line.tokens!.isNotEmpty &&
    line.tokens!.first.any((token) => token.end > token.start);

// Unicode mode preserves supplementary ideographs and emoji. Kana and Hangul
// also use character cadence; western words retain their trailing whitespace.
final _cjk = RegExp(
  r'[\u1100-\u11FF\u3130-\u318F\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\u3040-\u30FF\u31F0-\u31FF\uAC00-\uD7AF\u{20000}-\u{3134F}]',
  unicode: true,
);
final _punctuation = RegExp(r'^[\p{P}\p{S}]+$', unicode: true);

List<String> _syntheticChunks(String text) {
  final chunks = <String>[];
  final word = StringBuffer();
  var trailingSpace = false;
  void flush() {
    if (word.isNotEmpty) {
      chunks.add(word.toString());
      word.clear();
    }
    trailingSpace = false;
  }

  // Applying the language regex to complete graphemes avoids splitting kana
  // with a combining dakuten or a supplementary Han surrogate pair.
  for (final grapheme in text.characters) {
    if (_cjk.hasMatch(grapheme)) {
      flush();
      chunks.add(grapheme);
    } else if (grapheme.trim().isEmpty) {
      word.write(grapheme);
      trailingSpace = true;
    } else {
      if (trailingSpace) flush();
      word.write(grapheme);
    }
  }
  flush();
  return chunks;
}

double karaokeSyntheticTokenWeight(String token) => token.trim().isEmpty
    ? 0
    : math.max(.25, math.pow(token.trim().characters.length, .9).toDouble());

class _TimingEntry {
  _TimingEntry(this.next, this.result, List<String> texts)
    : texts = List<String>.of(texts);
  final Duration? next;
  final LyricLine result;
  final List<String> texts;

  bool matches(List<String> current) {
    if (current.length != texts.length) return false;
    for (var i = 0; i < texts.length; i++) {
      if (current[i] != texts[i]) return false;
    }
    return true;
  }
}

// Weak identity keys: cached timelines disappear with their source lyrics.
final _cache = Expando<_TimingEntry>();

/// Estimates timing from an ordinary LRC line. It cannot infer vocal timing.
/// Real token timestamps always take precedence. The requested 650 ms floor
/// also applies to very short intervals; this is an estimate, not extra audio.
LyricLine synthesizeKaraokeTiming(LyricLine line, {Duration? nextTimestamp}) {
  if (line.isInterlude || line.texts.isEmpty || hasUsableKaraokeTiming(line)) {
    return line;
  }
  final cached = _cache[line];
  if (cached != null &&
      cached.next == nextTimestamp &&
      cached.matches(line.texts)) {
    return cached.result;
  }
  final interval = nextTimestamp == null
      ? const Duration(seconds: 4)
      : nextTimestamp - line.timestamp;
  final chunks = _syntheticChunks(line.texts.first);
  final cjkCount = chunks.where((chunk) => _cjk.hasMatch(chunk)).length;
  final visibleCount = chunks.where((chunk) => chunk.trim().isNotEmpty).length;
  final cjkShare = visibleCount == 0 ? 0.0 : cjkCount / visibleCount;
  // Ordinary LRC has only line boundaries. CJK syllables usually occupy the
  // start of a sung phrase; Latin words need more of the interval for their
  // individual letters to travel. Mixed lines interpolate between the two.
  final activeFraction = .98 - .22 * cjkShare;
  final activeUs = (interval.inMicroseconds * activeFraction).round().clamp(
    650000,
    8000000,
  );
  final leadUs = (80000 * cjkShare).round().clamp(
    0,
    line.timestamp.inMicroseconds,
  );
  final start = line.timestamp - Duration(microseconds: leadUs);
  final timelineUs = activeUs + leadUs;
  final weights = <double>[];
  for (final chunk in chunks) {
    if (chunk.trim().isEmpty) {
      weights.add(0); // Preserve layout text, but do not invent silent beats.
    } else if (_cjk.hasMatch(chunk)) {
      // A line timestamp cannot reveal which syllable is sustained. Equal
      // estimates avoid the former .72/1/1.3/1.8 artificial speed staircase.
      weights.add(1);
    } else if (_punctuation.hasMatch(chunk.trim())) {
      weights.add(.25);
    } else {
      weights.add(karaokeSyntheticTokenWeight(chunk));
    }
  }
  final total = weights.fold<double>(0, (sum, weight) => sum + weight);
  if (total <= 0) return line;
  var elapsed = 0.0;
  final tokens = <LyricToken>[];
  for (var i = 0; i < chunks.length; i++) {
    final startUs = (timelineUs * elapsed / total).round();
    elapsed += weights[i];
    final endUs = i == chunks.length - 1
        ? timelineUs
        : (timelineUs * elapsed / total).round();
    tokens.add(
      LyricToken(
        text: chunks[i],
        start: start + Duration(microseconds: startUs),
        end: start + Duration(microseconds: endUs),
      ),
    );
  }
  final result = LyricLine(
    timestamp: line.timestamp,
    texts: line.texts,
    tokens: [
      tokens,
      for (var i = 1; i < line.texts.length; i++) const <LyricToken>[],
    ],
  );
  _cache[line] = _TimingEntry(nextTimestamp, result, line.texts);
  return result;
}
