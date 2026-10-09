import 'dart:async';
import 'dart:isolate';
import 'package:pinyin/pinyin.dart';
import 'package:characters/characters.dart';

class PreparedLibraryMetadata {
  PreparedLibraryMetadata(
    this.artists,
    this.albums,
    this.sortKeys,
    this.pinyin,
    this.initials,
    this.mixedKeys,
  );
  final Map<String, List<int>> artists, albums;
  final Map<String, String> sortKeys;
  final List<List<String>> pinyin, initials;
  final Map<String, String> mixedKeys;
}

/// One dictionary instance per worker, reused for subsequent library revisions.
/// Only strings/indices cross the port; artwork and UI objects stay on the UI.
class LibraryPreparationWorker {
  Future<SendPort>? _port;
  Isolate? _isolate;
  ReceivePort? _startupReply;
  bool _disposed = false;
  final Map<ReceivePort, Completer<PreparedLibraryMetadata>> _pending = {};

  Future<SendPort> _start() async {
    final ready = ReceivePort();
    _startupReply = ready;
    try {
      final isolate = await Isolate.spawn(_serve, ready.sendPort);
      _isolate = isolate;
      if (_disposed) {
        isolate.kill();
        throw StateError('Worker disposed');
      }
      final port = await ready.first as SendPort;
      if (_disposed) throw StateError('Worker disposed');
      return port;
    } finally {
      ready.close();
      _startupReply = null;
    }
  }

  Future<PreparedLibraryMetadata> prepare(
    List<List<String>> rows,
    List<String> separators, {
    List<String> labels = const [],
    bool includeSearchIndex = true,
  }) async {
    if (_disposed) throw StateError('Worker disposed');
    final port = await (_port ??= _start());
    if (_disposed) throw StateError('Worker disposed');
    final reply = ReceivePort();
    final result = Completer<PreparedLibraryMetadata>();
    _pending[reply] = result;
    reply.listen((message) {
      _pending.remove(reply);
      reply.close();
      if (message is PreparedLibraryMetadata) {
        result.complete(message);
      } else {
        result.completeError(StateError('$message'));
      }
    });
    port.send((reply.sendPort, rows, separators, labels, includeSearchIndex));
    return result.future;
  }

  void dispose() {
    _disposed = true;
    _startupReply?.close();
    _isolate?.kill();
    for (final entry in _pending.entries) {
      entry.key.close();
      entry.value.completeError(StateError('Worker disposed'));
    }
    _pending.clear();
  }

  static void _serve(SendPort ready) {
    final requests = ReceivePort();
    ready.send(requests.sendPort);
    requests.listen((message) {
      final (
        reply,
        rows,
        separators,
        labels,
        includeSearchIndex,
      ) = message
          as (SendPort, List<List<String>>, List<String>, List<String>, bool);
      try {
        reply.send(
          prepareLibraryMetadata(
            rows,
            separators,
            labels: labels,
            includeSearchIndex: includeSearchIndex,
          ),
        );
      } catch (error) {
        reply.send(error.toString());
      }
    });
  }
}

PreparedLibraryMetadata prepareLibraryMetadata(
  List<List<String>> rows,
  List<String> separators, {
  List<String> labels = const [],
  bool includeSearchIndex = true,
}) {
  final valid = separators.where((s) => s.isNotEmpty && s.trim().isNotEmpty);
  final pattern = valid.isEmpty
      ? null
      : RegExp('[${valid.map(RegExp.escape).join('|')}]');
  final artists = <String, List<int>>{}, albums = <String, List<int>>{};
  final keys = <String, String>{};
  final mixedKeys = <String, String>{};
  final pinyin = <List<String>>[], initials = <List<String>>[];
  String full(String text) =>
      PinyinHelper.getPinyin(text, separator: '').toLowerCase();
  String initial(String text) => text.runes.map((rune) {
    final char = String.fromCharCode(rune),
        value = full(String.fromCharCode(rune));
    return value.isNotEmpty && value != char.toLowerCase()
        ? value[0]
        : char.toLowerCase();
  }).join();
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i]; // title, artist, album
    for (final text in includeSearchIndex ? row : const <String>[]) {
      mixedKeys.putIfAbsent(
        text,
        () => text.characters.map((char) {
          final value = PinyinHelper.getPinyin(char);
          return value.isNotEmpty && value != char ? value : char.toLowerCase();
        }).join(),
      );
    }
    final names = row[1].isEmpty
        ? ['未知歌手']
        : pattern == null
        ? [row[1]]
        : row[1]
              .split(pattern)
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
    for (final name in names.isEmpty ? [row[1]] : names) {
      artists.putIfAbsent(name, () => []).add(i);
    }
    albums.putIfAbsent(row[2], () => []).add(i);
    if (includeSearchIndex) {
      pinyin.add(row.map(full).toList());
      initials.add(row.map(initial).toList());
    }
  }
  for (final name in {
    ...artists.keys,
    ...albums.keys,
    if (includeSearchIndex) ...rows.expand((row) => row),
    ...labels,
  }) {
    final trimmed = name.trim();
    final value = full(trimmed).trim();
    keys[trimmed] = value.isEmpty ? trimmed.toLowerCase() : value;
  }
  return PreparedLibraryMetadata(
    artists,
    albums,
    keys,
    pinyin,
    initials,
    mixedKeys,
  );
}
