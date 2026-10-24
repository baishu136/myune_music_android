import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Positive device values delay visuals in wall time. Song offsets use media time.
/// This never mutates source LRC timestamps, audio position, or playback rate.
class LyricSyncPreferences extends ChangeNotifier {
  LyricSyncPreferences() {
    initializationFuture = _load();
  }
  static const key = 'lyricSyncProfiles416';
  late final Future<void> initializationFuture;
  int globalDelayMs = 0;
  bool automatic = true;
  String? _deviceKey, _songKey;
  String? _rawSongPath;
  bool _persistentDevice = false;
  final _devices = <String, int>{},
      _sessionDevices = <String, int>{},
      _songs = <String, int>{};
  bool _disposed = false;
  Future<void> _saving = Future.value();
  int _bounded(num value, int limit) =>
      value.isFinite ? value.round().clamp(-limit, limit) : 0;
  int? get deviceOverrideMs => _deviceKey == null
      ? null
      : (_persistentDevice ? _devices : _sessionDevices)[_deviceKey];
  int get effectiveDeviceMs => deviceOverrideMs ?? globalDelayMs;
  int get songDelayMs => _songs[_songKey] ?? 0;
  bool get canPersistDevice => _deviceKey != null && _persistentDevice;
  bool get hasDevice => _deviceKey != null;
  Duration visualPosition(Duration media, {double rate = 1}) =>
      media -
      Duration(
        microseconds:
            (effectiveDeviceMs * 1000 * (rate.isFinite && rate > 0 ? rate : 1))
                .round() +
            songDelayMs * 1000,
      );
  Duration mediaPosition(Duration lyric, {double rate = 1}) =>
      lyric - visualPosition(Duration.zero, rate: rate);
  void useDevice(String? key, {required bool persistent}) {
    if (_deviceKey == key && _persistentDevice == persistent) return;
    _deviceKey = key;
    _persistentDevice = persistent;
    _changed(save: false);
  }

  void useSong(String? path) {
    if (_rawSongPath == path) return;
    _rawSongPath = path;
    final key = path?.replaceAll('\\', '/').toLowerCase();
    if (_songKey == key) return;
    _songKey = key;
    _changed(save: false);
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      final data = raw == null ? <String, dynamic>{} : jsonDecode(raw) as Map;
      globalDelayMs = _bounded(
        data['global'] is num ? data['global'] as num : 0,
        2000,
      );
      automatic = data['automatic'] != false;
      for (final pair in [
        (data['devices'], _devices, 2000),
        (data['songs'], _songs, 10000),
      ]) {
        if (pair.$1 is! Map) continue;
        for (final entry in (pair.$1 as Map).entries.take(2048)) {
          if (entry.key is String && entry.value is num) {
            pair.$2[entry.key as String] = _bounded(
              entry.value as num,
              pair.$3,
            );
          }
        }
      }
    } catch (_) {
      /* A corrupt sync profile must never block playback. */
    }
    _changed(save: false);
  }

  Future<void> setGlobal(int value) async {
    await initializationFuture;
    globalDelayMs = _bounded(value, 2000);
    _changed();
    await _saving;
  }

  Future<void> setAutomatic(bool value) async {
    await initializationFuture;
    automatic = value;
    _changed();
    await _saving;
  }

  Future<void> setDevice(int? value) async {
    final key = _deviceKey;
    final persistent = _persistentDevice;
    await initializationFuture;
    if (key == null) return;
    final target = persistent ? _devices : _sessionDevices;
    if (value == null) {
      target.remove(key);
    } else {
      target[key] = _bounded(value, 2000);
    }
    _changed();
    await _saving;
  }

  Future<void> setSong(int value) async {
    final song = _songKey;
    await initializationFuture;
    if (song == null) return;
    if (value == 0) {
      _songs.remove(song);
    } else {
      _songs[song] = _bounded(value, 10000);
    }
    _changed();
    await _saving;
  }

  Future<void> reset() async {
    await initializationFuture;
    globalDelayMs = 0;
    automatic = true;
    _devices.clear();
    _sessionDevices.clear();
    _songs.clear();
    _changed();
    await _saving;
  }

  void _changed({bool save = true}) {
    if (_disposed) return;
    notifyListeners();
    if (!save) return;
    final encoded = jsonEncode({
      'global': globalDelayMs,
      'automatic': automatic,
      'devices': _devices,
      'songs': _songs,
    });
    _saving = _saving.catchError((_) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(key, encoded)) throw StateError('歌词同步设置保存失败');
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
