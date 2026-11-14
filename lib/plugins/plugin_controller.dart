import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'plugin_network.dart';
import 'plugin_package.dart';
import 'plugin_runtime.dart';

abstract interface class PluginHost {
  String? get songIdentity;
  Map<String, dynamic> snapshot();
  Future<Object?> call(String method, Map<String, dynamic> args);
}

class PluginEntry {
  PluginEntry(
    this.package, {
    this.enabled = false,
    Map<String, dynamic>? storage,
  }) : storage = storage ?? {};
  final PluginPackage package;
  bool enabled;
  final Map<String, dynamic> storage;
  int generation = 0, failures = 0;
  String? lastError;
}

class PluginCancelled implements Exception {
  const PluginCancelled();
  @override
  String toString() => '插件任务已失效';
}

/// Versioned host boundary. No raw player, notifier, paths or file handles cross
/// it. All runtime invocations are serialized; high-frequency player ticks do
/// not enter JS. Revocation is checked again after every await.
class PluginController extends ChangeNotifier {
  PluginController(this.preferences, {PluginRuntime? runtime})
    : runtime = runtime ?? AndroidPluginRuntime() {
    _restore();
  }
  final SharedPreferences preferences;
  final PluginRuntime runtime;
  static const storeKey = 'myune_plugins_sdk1';
  final List<PluginEntry> _entries = [];
  List<PluginEntry> get entries => List.unmodifiable(_entries);
  bool get hasLyricProviders =>
      _entries.any((e) => e.enabled && e.package.features.contains('lyrics'));
  final List<String> _logs = [];
  List<String> get logs => List.unmodifiable(_logs);
  PluginHost? _host;
  Future<void> _tail = Future.value(), _writes = Future.value();
  int _queued = 0;
  bool _disposed = false;
  int revision = 0;
  Timer? _eventTimer;
  Object? _lastEvent;
  void bindHost(PluginHost host) {
    _host = host;
  }

  void unbindHost(PluginHost host) {
    if (identical(_host, host)) _host = null;
  }

  void _restore() {
    try {
      final raw = preferences.getString(storeKey);
      if (raw == null) return;
      final list = jsonDecode(raw);
      if (list is! List || list.length > 16) throw const FormatException();
      for (final item in list) {
        try {
          final data = pluginMap(item);
          final package = PluginPackage.parse(jsonEncode(data['package']));
          final storage = pluginMap(data['storage'] ?? <String, dynamic>{});
          if (utf8.encode(jsonEncode(storage)).length > 16384 ||
              _entries.any((e) => e.package.id == package.id)) {
            continue;
          }
          _entries.add(
            PluginEntry(
              package,
              enabled: data['enabled'] == true,
              storage: storage,
            ),
          );
        } catch (_) {
          _logs.add('已跳过损坏的插件记录');
        }
      }
    } catch (_) {
      _logs.add('插件记录无法读取，内置功能仍可使用');
    }
  }

  void _log(PluginEntry entry, Object error) {
    final message = error.toString();
    entry.lastError = message.length > 1000
        ? message.substring(0, 1000)
        : message;
    _logs.add('${entry.package.name}：${entry.lastError}');
    while (_logs.length > 60) {
      _logs.removeAt(0);
    }
  }

  Future<void> _save() {
    final encoded = jsonEncode([
      for (final e in _entries)
        {'package': e.package.json, 'enabled': e.enabled, 'storage': e.storage},
    ]);
    final write = _writes.then((_) async {
      if (!await preferences.setString(storeKey, encoded)) {
        throw StateError('插件保存失败');
      }
    });
    _writes = write.catchError((Object _) {});
    return write;
  }

  void _changed() {
    revision++;
    if (!_disposed) notifyListeners();
  }

  Future<void> install(PluginPackage package) async {
    final index = _entries.indexWhere((e) => e.package.id == package.id);
    if (index < 0 && _entries.length >= 16) throw StateError('最多安装 16 个插件');
    if (index >= 0) {
      _entries[index].generation++;
      _entries[index].enabled = false;
      _entries[index] = PluginEntry(package);
    } else {
      _entries.add(PluginEntry(package));
    }
    _changed();
    await _save();
  }

  Future<void> setEnabled(PluginEntry entry, bool enabled) async {
    if (!_entries.contains(entry)) throw const PluginCancelled();
    entry.generation++;
    entry.enabled = enabled;
    entry.failures = 0;
    entry.lastError = null;
    _changed();
    await _save();
    if (enabled) {
      try {
        await invoke(entry, 'lifecycle.enable');
      } catch (_) {
        if (_entries.contains(entry)) {
          entry.enabled = false;
          entry.generation++;
          _changed();
          await _save();
        }
        rethrow;
      }
    }
  }

  Future<void> remove(PluginEntry entry) async {
    entry.enabled = false;
    entry.generation++;
    _entries.remove(entry);
    _changed();
    await _save();
  }

  Future<T> _serialize<T>(Future<T> Function() work) {
    if (_disposed || _queued >= 8) return Future.error(StateError('插件任务繁忙'));
    _queued++;
    final result = _tail.then((_) => work());
    _tail = result
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .whenComplete(() => _queued--);
    return result;
  }

  Future<Object?> invoke(PluginEntry entry, String event, {Object? data}) {
    final generation = entry.generation;
    final host = _host;
    final song = host?.songIdentity;
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    void valid() {
      if (_disposed ||
          !entry.enabled ||
          generation != entry.generation ||
          !_entries.contains(entry) ||
          !identical(host, _host)) {
        throw const PluginCancelled();
      }
      if (DateTime.now().isAfter(deadline)) throw TimeoutException('插件任务超时');
    }

    return _serialize(() async {
      try {
        valid();
        var state = await runtime.start(entry.package.script, {
          'type': event,
          'data': data,
          'sdk': pluginSdkVersion,
          if (entry.package.permissions.contains('playback.read'))
            'playback': host?.snapshot(),
        });
        var calls = 0;
        for (var turn = 0; turn < 25; turn++) {
          valid();
          if (state['error'] != null) throw StateError('${state['error']}');
          if (state['done'] == true) {
            entry.failures = 0;
            return state['value'];
          }
          final requests = state['calls'];
          if (requests is! List ||
              requests.isEmpty ||
              calls + requests.length > 24) {
            throw StateError('插件未完成或请求过多');
          }
          final responses = <Map<String, dynamic>>[];
          for (final request in requests) {
            valid();
            calls++;
            final r = pluginMap(request);
            if (r['id'] is! int || r['method'] is! String) {
              throw const FormatException('无效插件请求');
            }
            try {
              final result = await _dispatch(
                entry,
                r['method'] as String,
                pluginMap(r['args']),
                host,
                song,
                event,
                valid,
              );
              valid();
              responses.add({'id': r['id'], 'value': result});
            } on PluginCancelled {
              rethrow;
            } catch (error) {
              responses.add({'id': r['id'], 'error': error.toString()});
            }
          }
          valid();
          state = await runtime.step(responses);
        }
        throw StateError('插件调用轮次超限');
      } on PluginCancelled {
        rethrow;
      } catch (error) {
        if (!_disposed &&
            generation == entry.generation &&
            _entries.contains(entry)) {
          _log(entry, error);
          if (++entry.failures >= 3) {
            entry.enabled = false;
            entry.generation++;
            _changed();
            await _save();
          } else {
            notifyListeners();
          }
        }
        rethrow;
      } finally {
        try {
          await runtime.close();
        } catch (_) {
          /* Dead isolated process. */
        }
      }
    });
  }

  Future<Object?> _dispatch(
    PluginEntry e,
    String method,
    Map<String, dynamic> args,
    PluginHost? host,
    String? song,
    String event,
    void Function() valid,
  ) async {
    const permissions = {
      'playback.get': 'playback.read',
      'playback.command': 'playback.control',
      'library.query': 'library.read',
      'queue.append': 'queue.write',
      'queue.play': 'queue.write',
      'storage.get': 'storage',
      'storage.set': 'storage',
      'network.fetch': 'network',
    };
    if (method == 'app.capabilities') {
      return {
        'sdk': 1,
        'methods': permissions.keys.toList(),
        'features': pluginFeatures.toList(),
      };
    }
    final permission = permissions[method];
    if (permission == null || !e.package.permissions.contains(permission)) {
      throw StateError('未授权：$method');
    }
    final mutation =
        method == 'playback.command' || method.startsWith('queue.');
    if (mutation && (event != 'ui.action' && event != 'menu.action')) {
      throw StateError('播放操作需要用户触发');
    }
    if (mutation && host?.songIdentity != song) throw const PluginCancelled();
    valid();
    switch (method) {
      case 'storage.get':
        return e.storage[args['key']];
      case 'storage.set':
        final key = args['key'];
        if (key is! String || key.isEmpty || key.length > 80) {
          throw StateError('存储键无效');
        }
        final next = {...e.storage, key: args['value']};
        if (utf8.encode(jsonEncode(next)).length > 16384) {
          throw StateError('插件存储超限');
        }
        e.storage
          ..clear()
          ..addAll(next);
        await _save();
        return true;
      case 'network.fetch':
        return pluginFetch(e.package.domains, args);
      case 'playback.get':
        return host?.snapshot();
      default:
        if (host == null) throw StateError('播放器尚未就绪');
        return host.call(method, args);
    }
  }

  /// Returns only data. Caller owns lyric parsing and song/request revision.
  Future<Map<String, dynamic>?> lyrics(Map<String, dynamic> song) async {
    final startRevision = revision;
    for (final entry in entries.where(
      (e) => e.enabled && e.package.features.contains('lyrics'),
    )) {
      try {
        final result = await invoke(entry, 'lyrics.resolve', data: song);
        if (revision != startRevision) return null;
        if (result is Map<String, dynamic> &&
            result['lrc'] is String &&
            (result['lrc'] as String).length <= 48000 &&
            (result['lrc'] as String).trim().isNotEmpty) {
          return result;
        }
      } catch (_) {
        /* Continue to other providers, then built-in sources. */
      }
    }
    return null;
  }

  void playbackChanged(Object identity) {
    if (_disposed || identity == _lastEvent) return;
    _lastEvent = identity;
    if (!_entries.any(
      (e) => e.enabled && e.package.features.contains('events'),
    )) {
      return;
    }
    _eventTimer?.cancel();
    _eventTimer = Timer(const Duration(milliseconds: 150), () {
      if (_queued > 0 || _disposed) return;
      for (final entry in entries.where(
        (e) => e.enabled && e.package.features.contains('events'),
      )) {
        unawaited(
          invoke(entry, 'playback.changed').catchError((Object _) => null),
        );
      }
    });
  }

  Future<Map<String, dynamic>> diagnose() => _serialize(() async {
    Future<Map<String, dynamic>> run(String script) async {
      try {
        return await runtime.start(script, {'type': 'diagnostic'});
      } finally {
        await runtime.close();
      }
    }

    final good = await run(
      'globalThis.myunePlugin=()=>({answer:6*7, io:typeof std+":"+typeof os});',
    );
    final loop = await run('globalThis.myunePlugin=()=>{while(true){}};');
    final memory = await run(
      'globalThis.myunePlugin=()=>new ArrayBuffer(32*1024*1024);',
    );
    final recovered = await run('globalThis.myunePlugin=()=>42;');
    final passed =
        good['value'] is Map &&
        (good['value'] as Map)['answer'] == 42 &&
        (good['value'] as Map)['io'] == 'undefined:undefined' &&
        '${loop['error']}'.contains('execution time limit') &&
        '${memory['error']}'.toLowerCase().contains('memory') &&
        (runtime is! AndroidPluginRuntime ||
            ((runtime as AndroidPluginRuntime).lastIsolation?['isolated'] ==
                    true &&
                (runtime as AndroidPluginRuntime).lastIsolation?['uid'] !=
                    (runtime as AndroidPluginRuntime)
                        .lastIsolation?['hostUid'])) &&
        recovered['value'] == 42;
    return {
      'passed': passed,
      'execution': good,
      'timeout': loop,
      'memory': memory,
      'recovered': recovered,
      if (runtime is AndroidPluginRuntime)
        'isolation': (runtime as AndroidPluginRuntime).lastIsolation,
    };
  });
  @override
  void dispose() {
    _disposed = true;
    _eventTimer?.cancel();
    for (final e in _entries) {
      e.generation++;
    }
    super.dispose();
  }
}
