import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../page/playlist/playlist_models.dart';
import 'network_qrc_cipher.dart';

const networkLyricByteLimit = 2 * 1024 * 1024;
const _maximumTime = 24 * 60 * 60 * 1000;

class NetworkLyricContent {
  const NetworkLyricContent({
    this.timed = const [],
    this.lrc = const [],
    this.translation = const [],
  });
  final List<LyricLine> timed;
  final List<String> lrc;
  final List<String> translation;
  bool get isEmpty =>
      timed.isEmpty &&
      !lrc.any(
        (line) => RegExp(r'\[\d{1,3}:\d{2}[.:]\d{1,3}\]').hasMatch(line),
      );
}

List<String> splitNetworkLrc(String content) => content.isEmpty
    ? const []
    : content.replaceAll('\uFEFF', '').split(RegExp(r'\r\n|\n|\r'));

NetworkLyricContent decodeNetworkLyrics(
  (String, Map<String, dynamic>, bool) input,
) {
  final (format, data, translate) = input;
  String field(String key) =>
      data[key] is Map ? (data[key]['lyric'] as String? ?? '') : '';
  try {
    if (format == 'netease') {
      final lines = parseNetworkTimedLyrics(field('yrc'), 'yrc');
      final translated = translate
          ? (field('ytlrc').isNotEmpty ? field('ytlrc') : field('tlyric'))
          : '';
      return NetworkLyricContent(
        timed: _mergeTranslation(lines, translated),
        lrc: splitNetworkLrc(field('lrc')),
        translation: translate ? splitNetworkLrc(translated) : const [],
      );
    }
    if (format == 'krc') {
      final text = decodeKrc(data['content'] as String? ?? '');
      var lines = parseNetworkTimedLyrics(text, 'krc');
      if (translate) lines = _krcTranslation(lines, text);
      return NetworkLyricContent(timed: lines);
    }
    if (format == 'qq') {
      final text = decodeQqLyric(data['lyric'] as String? ?? '');
      final translated = translate
          ? _tryQqTranslation(data['trans'] as String? ?? '')
          : '';
      final timed = data['qrc'] == 1
          ? parseNetworkTimedLyrics(_qrcText(text), 'qrc')
          : const <LyricLine>[];
      return NetworkLyricContent(
        timed: _mergeTranslation(timed, translated),
        lrc: timed.isEmpty ? splitNetworkLrc(text) : const [],
        translation: translate ? splitNetworkLrc(translated) : const [],
      );
    }
    final text = format == 'kugouLrc'
        ? utf8.decode(base64Decode(data['content'] as String? ?? ''))
        : _tryQqText(data['lyric'] as String? ?? '');
    return NetworkLyricContent(
      lrc: splitNetworkLrc(text),
      translation: translate
          ? splitNetworkLrc(_tryQqText(data['trans'] as String? ?? ''))
          : const [],
    );
  } catch (_) {
    return const NetworkLyricContent();
  }
}

String decodeKrc(String encoded) {
  if (encoded.length > networkLyricByteLimit * 2) {
    throw const FormatException('KRC too large');
  }
  final raw = base64Decode(encoded);
  if (raw.length < 5 ||
      raw[0] != 107 ||
      raw[1] != 114 ||
      raw[2] != 99 ||
      raw[3] != 49) {
    throw const FormatException('Invalid KRC header');
  }
  const key = [
    64,
    71,
    97,
    119,
    94,
    50,
    116,
    71,
    81,
    54,
    49,
    45,
    206,
    210,
    110,
    105,
  ];
  final data = Uint8List(raw.length - 4);
  for (var i = 0; i < data.length; i++) {
    data[i] = raw[i + 4] ^ key[i % 16];
  }
  return _inflateText(data);
}

String decodeQqLyric(String payload) {
  if (payload.length > networkLyricByteLimit * 2) {
    throw const FormatException('QRC too large');
  }
  if (payload.startsWith('[') || payload.startsWith('<')) return payload;
  if (payload.isNotEmpty &&
      payload.length.isEven &&
      RegExp(r'^[0-9a-fA-F]+$').hasMatch(payload)) {
    final data = Uint8List.fromList([
      for (var i = 0; i < payload.length; i += 2)
        int.parse(payload.substring(i, i + 2), radix: 16),
    ]);
    return _inflateText(decryptQrcCloud(data));
  }
  return utf8.decode(base64Decode(payload));
}

String _tryQqText(String content) {
  try {
    return decodeQqLyric(content);
  } catch (_) {
    return '';
  }
}

String _tryQqTranslation(String content) {
  try {
    return _qrcText(_tryQqText(content));
  } catch (_) {
    return '';
  }
}

String _inflateText(List<int> input) {
  final sink = _BoundedBytes();
  final conversion = ZLibDecoder().startChunkedConversion(sink);
  conversion.add(input);
  conversion.close();
  return utf8.decode(sink.bytes.takeBytes());
}

class _BoundedBytes implements Sink<List<int>> {
  final bytes = BytesBuilder(copy: false);
  var length = 0;
  @override
  void add(List<int> data) {
    length += data.length;
    if (length > networkLyricByteLimit) {
      throw const FormatException('Lyric expansion too large');
    }
    bytes.add(data);
  }

  @override
  void close() {}
}

String _qrcText(String content) {
  if (!content.trimLeft().startsWith('<')) return content;
  if (content.contains('<!DOCTYPE')) {
    throw const FormatException('Unsupported QRC document');
  }
  final xml = XmlDocument.parse(content);
  for (final element in xml.descendants.whereType<XmlElement>()) {
    final value = element.getAttribute('LyricContent');
    if (value != null && value.isNotEmpty) return value;
  }
  return '';
}

List<LyricLine> parseNetworkTimedLyrics(String content, String format) {
  if (content.length > networkLyricByteLimit) {
    throw const FormatException('Lyric text too large');
  }
  if (content.isEmpty) return const [];
  final offset =
      int.tryParse(
        RegExp(r'\[offset:([+-]?\d+)\]').firstMatch(content)?.group(1) ?? '0',
      ) ??
      0;
  final result = <LyricLine>[];
  final rows = RegExp(
    r'\[(\d+),(\d+)\]([\s\S]*?)(?=\[\d+,\d+\]|$)',
  ).allMatches(content);
  final marker = format == 'krc'
      ? RegExp(r'<(\d+),(\d+),\d+>')
      : format == 'yrc'
      ? RegExp(r'\((\d+),(\d+),\d+\)')
      : RegExp(r'\((\d+),(\d+)\)');
  for (final row in rows) {
    if (result.length >= 10000) {
      throw const FormatException('Too many lyric rows');
    }
    final lineStart = int.tryParse(row.group(1)!);
    final lineDuration = int.tryParse(row.group(2)!);
    if (lineStart == null ||
        lineDuration == null ||
        lineStart > _maximumTime ||
        lineDuration > _maximumTime) {
      continue;
    }
    final body = row.group(3)!.trimRight();
    final markers = marker.allMatches(body).toList(growable: false);
    if (markers.isEmpty) continue;
    if (markers.length > 2000) {
      throw const FormatException('Too many lyric words');
    }
    final tokens = <LyricToken>[];
    var cursor = 0, valid = true;
    for (var i = 0; i < markers.length; i++) {
      final word = markers[i];
      final start = int.tryParse(word.group(1)!);
      final duration = int.tryParse(word.group(2)!);
      if (start == null ||
          duration == null ||
          start > _maximumTime ||
          duration > _maximumTime) {
        valid = false;
        break;
      }
      final actualStart = start + (format == 'krc' ? lineStart : 0) + offset;
      if (actualStart + duration > _maximumTime ||
          (tokens.isNotEmpty &&
              math.max(0, actualStart) < tokens.last.start.inMilliseconds)) {
        valid = false;
        break;
      }
      final text = format == 'qrc'
          ? body.substring(cursor, word.start)
          : body.substring(
              word.end,
              i + 1 < markers.length ? markers[i + 1].start : body.length,
            );
      cursor = word.end;
      if (text.isEmpty || actualStart + duration < 0) continue;
      tokens.add(
        LyricToken(
          text: text,
          start: Duration(milliseconds: math.max(0, actualStart)),
          end: Duration(milliseconds: math.max(0, actualStart + duration)),
        ),
      );
    }
    if (!valid || tokens.isEmpty || !tokens.any((t) => t.end > t.start)) {
      continue;
    }
    if (format == 'qrc' && body.substring(cursor).trim().isNotEmpty) continue;
    final text = tokens.map((t) => t.text).join();
    if (text.trim().isEmpty) continue;
    result.add(
      LyricLine(
        timestamp: Duration(milliseconds: math.max(0, lineStart + offset)),
        texts: [text],
        tokens: [tokens],
      ),
    );
  }
  result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return result;
}

List<LyricLine> _mergeTranslation(List<LyricLine> original, String content) {
  if (original.isEmpty || content.isEmpty) return original;
  final translations = <int, String>{};
  for (final line in splitNetworkLrc(content)) {
    final match = RegExp(
      r'^\[(\d{1,3}):(\d{2})[.:](\d{1,3})\](.*)$',
    ).firstMatch(line);
    if (match == null || match.group(4)!.trim().isEmpty) continue;
    final ms =
        int.parse(match.group(1)!) * 60000 +
        int.parse(match.group(2)!) * 1000 +
        int.parse(match.group(3)!.padRight(3, '0'));
    translations[ms] = match.group(4)!;
  }
  final used = <int>{};
  final times = translations.keys.toList()..sort();
  return original
      .map((line) {
        int? best;
        var distance = 801;
        final target = line.timestamp.inMilliseconds;
        var low = 0, high = times.length;
        while (low < high) {
          final middle = (low + high) ~/ 2;
          if (times[middle] < target - 800) {
            low = middle + 1;
          } else {
            high = middle;
          }
        }
        for (
          var index = low;
          index < times.length && times[index] <= target + 800;
          index++
        ) {
          final time = times[index];
          if (used.contains(time)) continue;
          final delta = (time - target).abs();
          if (delta < distance) {
            distance = delta;
            best = time;
          }
        }
        if (best == null) return line;
        used.add(best);
        return LyricLine(
          timestamp: line.timestamp,
          texts: [...line.texts, translations[best]!],
          tokens: line.tokens,
        );
      })
      .toList(growable: false);
}

List<LyricLine> _krcTranslation(List<LyricLine> lines, String content) {
  final language = RegExp(
    r'\[language:([^\]]+)\]',
  ).firstMatch(content)?.group(1);
  if (language == null) return lines;
  try {
    final data = jsonDecode(utf8.decode(base64Decode(language)));
    for (final item in data['content'] as List) {
      if (item['type'] != 1 || item['lyricContent'] is! List) continue;
      final translated = item['lyricContent'] as List;
      if (translated.length != lines.length) return lines;
      return [
        for (var i = 0; i < lines.length; i++)
          LyricLine(
            timestamp: lines[i].timestamp,
            texts: [
              ...lines[i].texts,
              if (translated[i] is List && (translated[i] as List).isNotEmpty)
                (translated[i] as List).join(''),
            ],
            tokens: lines[i].tokens,
          ),
      ];
    }
  } catch (_) {
    return lines;
  }
  return lines;
}
