import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Persistent, content-addressed storage for encoded 256x256 thumbnails.
/// Identical covers embedded in many tracks occupy only one file.
class CoverDiskCache {
  CoverDiskCache({
    Directory? rootDirectory,
    this.maximumBytes = 192 * 1024 * 1024,
    this.maximumEntries = 4000,
    this.cleanupInterval = 32,
    this.beforeMaintenance,
  }) : assert(maximumBytes > 0),
       assert(maximumEntries > 0),
       assert(cleanupInterval > 0),
       _rootDirectory = rootDirectory;

  final Directory? _rootDirectory;
  final int maximumBytes;
  final int maximumEntries;
  final int cleanupInterval;
  final Future<void> Function()? beforeMaintenance;
  Future<Directory>? _resolvedDirectory;
  Future<Map<String, String>>? _indexFuture;
  Future<void> _writeChain = Future<void>.value();
  int _writesSinceCleanup = 0;

  Future<Uint8List?> read(String filePath, int modifiedMs) async {
    try {
      final index = await _index();
      final contentKey = index[_sourceKey(filePath, modifiedMs)];
      if (contentKey == null) return null;
      final file = await _contentFile(contentKey);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        await file.delete();
        return null;
      }
      await file.setLastModified(DateTime.now());
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String filePath, int modifiedMs, Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maximumBytes) return Future.value();
    final operation = _writeChain.then((_) async {
      try {
        final index = await _index();
        final contentKey = _stableHashBytes(bytes);
        final file = await _contentFile(contentKey);
        if (!await file.exists()) {
          final temporary = File('${file.path}.tmp');
          await temporary.writeAsBytes(bytes, flush: true);
          if (await file.exists()) {
            await temporary.delete();
          } else {
            await temporary.rename(file.path);
          }
        } else {
          await file.setLastModified(DateTime.now());
        }
        index[_sourceKey(filePath, modifiedMs)] = contentKey;
        await _saveIndex(index);
        _writesSinceCleanup++;
        if (_writesSinceCleanup >= cleanupInterval) {
          _writesSinceCleanup = 0;
          await beforeMaintenance?.call();
          await _cleanup(index, protectedKey: contentKey);
        }
      } catch (_) {
        // Cache failures must never block extraction from the audio file.
      }
    });
    _writeChain = operation.catchError((_) {});
    return operation;
  }

  Future<Map<String, String>> _index() => _indexFuture ??= () async {
    final directory = await _directory();
    final file = File('${directory.path}${Platform.pathSeparator}index.json');
    if (!await file.exists()) return <String, String>{};
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is! Map) return <String, String>{};
      return value.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } catch (_) {
      return <String, String>{};
    }
  }();

  Future<void> _saveIndex(Map<String, String> index) async {
    final directory = await _directory();
    final file = File('${directory.path}${Platform.pathSeparator}index.json');
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(index), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<File> _contentFile(String key) async {
    final directory = await _directory();
    return File('${directory.path}${Platform.pathSeparator}$key.thumb');
  }

  Future<Directory> _directory() => _resolvedDirectory ??= () async {
    final base = _rootDirectory ?? await getApplicationSupportDirectory();
    final directory = Directory(
      '${base.path}${Platform.pathSeparator}artwork_thumbnails_v3',
    );
    await directory.create(recursive: true);
    return directory;
  }();

  Future<void> _cleanup(
    Map<String, String> index, {
    required String protectedKey,
  }) async {
    final directory = await _directory();
    final records =
        <({File file, String key, int length, DateTime modified})>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.thumb')) continue;
      final stat = await entity.stat();
      final name = entity.uri.pathSegments.last;
      records.add((
        file: entity,
        key: name.substring(0, name.length - '.thumb'.length),
        length: stat.size,
        modified: stat.modified,
      ));
    }
    var totalBytes = records.fold<int>(0, (sum, item) => sum + item.length);
    records.sort((a, b) => a.modified.compareTo(b.modified));
    final removed = <String>{};
    var remaining = records.length;
    for (final record in records) {
      if (remaining <= maximumEntries && totalBytes <= maximumBytes) break;
      if (record.key == protectedKey) continue;
      await record.file.delete();
      removed.add(record.key);
      remaining--;
      totalBytes -= record.length;
    }
    if (removed.isNotEmpty) {
      index.removeWhere((_, value) => removed.contains(value));
      await _saveIndex(index);
    }
  }

  String _sourceKey(String path, int modifiedMs) =>
      '${_stableHashString(path.toLowerCase())}:$modifiedMs';

  String _stableHashString(String value) =>
      _stableHashBytes(Uint8List.fromList(utf8.encode(value)));

  String _stableHashBytes(Uint8List bytes) {
    var hash = 0xcbf29ce484222325;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
