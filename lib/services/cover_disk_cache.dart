import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// A bounded temporary cache for encoded embedded artwork.
///
/// Keys include the audio file modification time, so replacing or retagging a
/// song never reuses stale artwork. The operating system may clear this cache
/// at any time; callers must always retain their metadata extraction fallback.
class CoverDiskCache {
  CoverDiskCache({
    Directory? rootDirectory,
    this.maximumBytes = 64 * 1024 * 1024,
    this.maximumEntries = 160,
    this.cleanupInterval = 12,
  }) : assert(maximumBytes > 0),
       assert(maximumEntries > 0),
       assert(cleanupInterval > 0),
       _rootDirectory = rootDirectory;

  final Directory? _rootDirectory;
  final int maximumBytes;
  final int maximumEntries;
  final int cleanupInterval;
  Future<Directory>? _resolvedDirectory;
  bool _cleanupRunning = false;
  int _writesSinceCleanup = 0;

  Future<Uint8List?> read(String filePath, int modifiedMs) async {
    try {
      final file = await _file(filePath, modifiedMs);
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

  Future<void> write(String filePath, int modifiedMs, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maximumBytes) return;
    try {
      final file = await _file(filePath, modifiedMs);
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
      _writesSinceCleanup++;
      if (_writesSinceCleanup >= cleanupInterval) {
        _writesSinceCleanup = 0;
        await _cleanup(protectedFile: file);
      }
    } catch (_) {
      // A cache failure must never block artwork loaded from the source file.
    }
  }

  Future<File> _file(String filePath, int modifiedMs) async {
    final directory = await _directory();
    final hash = _stableHash(filePath);
    return File(
      '${directory.path}${Platform.pathSeparator}${hash}_$modifiedMs.cover',
    );
  }

  Future<Directory> _directory() => _resolvedDirectory ??= () async {
    final base = _rootDirectory ?? await getTemporaryDirectory();
    final directory = Directory(
      '${base.path}${Platform.pathSeparator}artwork_cache_v1',
    );
    await directory.create(recursive: true);
    return directory;
  }();

  Future<void> _cleanup({required File protectedFile}) async {
    if (_cleanupRunning) return;
    _cleanupRunning = true;
    try {
      final directory = await _directory();
      final records = <({File file, int length, DateTime modified})>[];
      await for (final entity in directory.list()) {
        if (entity is! File || entity.path.endsWith('.tmp')) continue;
        final stat = await entity.stat();
        records.add((file: entity, length: stat.size, modified: stat.modified));
      }
      var totalBytes = records.fold<int>(0, (sum, item) => sum + item.length);
      if (records.length <= maximumEntries && totalBytes <= maximumBytes) {
        return;
      }
      records.sort((a, b) => a.modified.compareTo(b.modified));
      var remainingEntries = records.length;
      for (final record in records) {
        if (remainingEntries <= maximumEntries && totalBytes <= maximumBytes) {
          break;
        }
        if (record.file.path == protectedFile.path) continue;
        await record.file.delete();
        remainingEntries--;
        totalBytes -= record.length;
      }
    } catch (_) {
      // Best-effort cleanup; the OS can also evict the temporary directory.
    } finally {
      _cleanupRunning = false;
    }
  }

  String _stableHash(String value) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
