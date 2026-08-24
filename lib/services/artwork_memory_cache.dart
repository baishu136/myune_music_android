import 'dart:collection';
import 'dart:typed_data';

/// Byte-bounded LRU for encoded 192/256px thumbnails. Flutter's ImageCache is the
/// decoded-image LRU; this cache avoids disk/native metadata work before that.
class ArtworkMemoryCache {
  ArtworkMemoryCache({
    required this.maximumEntries,
    required this.maximumBytes,
  });

  final int maximumEntries;
  final int maximumBytes;
  final LinkedHashMap<String, Uint8List?> _entries = LinkedHashMap();
  final Map<String, String> _entryHashes = {};
  final Map<String, Uint8List> _contentByHash = {};
  final Map<String, int> _contentReferences = {};
  int _bytes = 0;

  int get length => _entries.length;
  int get bytes => _bytes;
  Iterable<String> get keys => _entries.keys;
  bool containsKey(String key) => _entries.containsKey(key);

  Uint8List? operator [](String key) => get(key);
  void operator []=(String key, Uint8List? value) => put(key, value);

  Uint8List? get(String key) {
    if (!_entries.containsKey(key)) return null;
    final value = _entries.remove(key);
    _entries[key] = value;
    return value;
  }

  void put(String key, Uint8List? value) {
    _removeEntry(key);
    if (value == null) {
      _entries[key] = null;
      _trim();
      return;
    }
    final hash = _stableHash(value);
    final canonical = _contentByHash.putIfAbsent(hash, () {
      _bytes += value.length;
      return value;
    });
    _contentReferences.update(hash, (count) => count + 1, ifAbsent: () => 1);
    _entryHashes[key] = hash;
    _entries[key] = canonical;
    _trim();
  }

  void remove(String key) => _removeEntry(key);

  void clear() {
    _entries.clear();
    _entryHashes.clear();
    _contentByHash.clear();
    _contentReferences.clear();
    _bytes = 0;
  }

  void _trim() {
    while (_entries.length > maximumEntries || _bytes > maximumBytes) {
      final oldest = _entries.keys.first;
      _removeEntry(oldest);
    }
  }

  void _removeEntry(String key) {
    _entries.remove(key);
    final hash = _entryHashes.remove(key);
    if (hash == null) return;
    final references = (_contentReferences[hash] ?? 1) - 1;
    if (references > 0) {
      _contentReferences[hash] = references;
      return;
    }
    _contentReferences.remove(hash);
    final removed = _contentByHash.remove(hash);
    _bytes -= removed?.length ?? 0;
  }

  String _stableHash(Uint8List bytes) {
    var hash = 0xcbf29ce484222325;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16);
  }
}
