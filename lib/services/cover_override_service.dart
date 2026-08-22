import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef CoverOverrideDirectoryProvider = Future<Directory> Function();

/// Stores artwork selected by the user without modifying the source audio.
///
/// The index lives in preferences while image bytes live in the app document
/// directory, so large covers never bloat SharedPreferences. Missing files are
/// discarded during startup and replacing an override removes the old image.
class CoverOverrideService extends ChangeNotifier {
  CoverOverrideService({CoverOverrideDirectoryProvider? directoryProvider})
    : _directoryProvider =
          directoryProvider ??
          (() async => Directory(
            p.join(
              (await getApplicationDocumentsDirectory()).path,
              'myune_music',
              'cover_overrides',
            ),
          )) {
    initializationFuture = _load();
  }

  static const _songIndexKey = 'cover_override_song_index_v1';
  static const _artistIndexKey = 'cover_override_artist_index_v1';
  static const _albumIndexKey = 'cover_override_album_index_v1';

  final CoverOverrideDirectoryProvider _directoryProvider;
  final Map<String, String> _songFiles = {};
  final Map<String, String> _artistFiles = {};
  final Map<String, String> _albumFiles = {};
  final Map<String, Uint8List> _songBytes = {};
  final Map<String, Uint8List> _artistBytes = {};
  final Map<String, Uint8List> _albumBytes = {};
  late final Future<void> initializationFuture;
  int _sequence = 0;

  String _songKey(String path) => p.normalize(path);

  Uint8List? songCover(String path) => _songBytes[_songKey(path)];

  Uint8List? groupCover({required bool artist, required String group}) =>
      (artist ? _artistBytes : _albumBytes)[group];

  bool hasSongCover(String path) => _songBytes.containsKey(_songKey(path));

  bool hasGroupCover({required bool artist, required String group}) =>
      (artist ? _artistBytes : _albumBytes).containsKey(group);

  Future<void> setSongCover(String path, Uint8List? bytes) => _setCover(
    key: _songKey(path),
    bytes: bytes,
    fileIndex: _songFiles,
    byteIndex: _songBytes,
    preferenceKey: _songIndexKey,
    prefix: 'song',
  );

  Future<void> setGroupCover({
    required bool artist,
    required String group,
    Uint8List? bytes,
  }) => _setCover(
    key: group,
    bytes: bytes,
    fileIndex: artist ? _artistFiles : _albumFiles,
    byteIndex: artist ? _artistBytes : _albumBytes,
    preferenceKey: artist ? _artistIndexKey : _albumIndexKey,
    prefix: artist ? 'artist' : 'album',
  );

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      _loadIndex(prefs, _songIndexKey, _songFiles, _songBytes),
      _loadIndex(prefs, _artistIndexKey, _artistFiles, _artistBytes),
      _loadIndex(prefs, _albumIndexKey, _albumFiles, _albumBytes),
    ]);
  }

  Future<void> _loadIndex(
    SharedPreferences prefs,
    String preferenceKey,
    Map<String, String> fileIndex,
    Map<String, Uint8List> byteIndex,
  ) async {
    final encoded = prefs.getString(preferenceKey);
    if (encoded == null || encoded.isEmpty) return;
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
      var changed = false;
      for (final entry in decoded.entries) {
        final path = entry.value is String ? entry.value as String : null;
        if (path == null) {
          changed = true;
          continue;
        }
        final file = File(path);
        if (!await file.exists()) {
          changed = true;
          continue;
        }
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          changed = true;
          continue;
        }
        fileIndex[entry.key] = path;
        byteIndex[entry.key] = bytes;
      }
      if (changed) await _persistIndex(prefs, preferenceKey, fileIndex);
    } catch (_) {
      await prefs.remove(preferenceKey);
    }
  }

  Future<void> _setCover({
    required String key,
    required Uint8List? bytes,
    required Map<String, String> fileIndex,
    required Map<String, Uint8List> byteIndex,
    required String preferenceKey,
    required String prefix,
  }) async {
    await initializationFuture;
    final previousPath = fileIndex[key];
    if (bytes == null || bytes.isEmpty) {
      fileIndex.remove(key);
      byteIndex.remove(key);
    } else {
      final directory = await _directoryProvider();
      if (!await directory.exists()) await directory.create(recursive: true);
      final safeName =
          '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_sequence++}.png';
      final file = File(p.join(directory.path, safeName));
      await file.writeAsBytes(bytes, flush: true);
      fileIndex[key] = file.path;
      byteIndex[key] = Uint8List.fromList(bytes);
    }

    final prefs = await SharedPreferences.getInstance();
    await _persistIndex(prefs, preferenceKey, fileIndex);
    final currentPath = fileIndex[key];
    if (previousPath != null && previousPath != currentPath) {
      try {
        final oldFile = File(previousPath);
        if (await oldFile.exists()) await oldFile.delete();
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _persistIndex(
    SharedPreferences prefs,
    String preferenceKey,
    Map<String, String> index,
  ) async {
    if (index.isEmpty) {
      await prefs.remove(preferenceKey);
    } else {
      await prefs.setString(preferenceKey, jsonEncode(index));
    }
  }
}
