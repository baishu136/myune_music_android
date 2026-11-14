import 'dart:convert';
import 'package:flutter/services.dart';
import 'plugin_package.dart';

abstract interface class PluginRuntime {
  Future<Map<String, dynamic>> start(String code, Map<String, dynamic> event);
  Future<Map<String, dynamic>> step(List<Map<String, dynamic>> responses);
  Future<void> close();
}

class AndroidPluginRuntime implements PluginRuntime {
  AndroidPluginRuntime({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.myune.music/plugins');
  final MethodChannel _channel;
  Map<String, dynamic>? lastIsolation;
  Future<Map<String, dynamic>> _call(
    String method,
    Object? input, [
    String code = '',
  ]) async {
    final reply = await _channel
        .invokeMapMethod<String, dynamic>(method, {
          'code': code,
          'input': jsonEncode(input),
        })
        .timeout(const Duration(seconds: 5));
    if (reply == null || reply['result'] is! String) {
      throw StateError('插件进程无响应');
    }
    lastIsolation = {
      'uid': reply['uid'],
      'pid': reply['pid'],
      'isolated': reply['isolated'],
      'hostUid': reply['hostUid'],
    };
    return pluginMap(jsonDecode(reply['result'] as String));
  }

  @override
  Future<Map<String, dynamic>> start(String code, Map<String, dynamic> event) =>
      _call('start', event, code);
  @override
  Future<Map<String, dynamic>> step(List<Map<String, dynamic>> responses) =>
      _call('step', responses);
  @override
  Future<void> close() async {
    await _call('close', null);
  }
}
