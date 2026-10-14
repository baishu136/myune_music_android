import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/equalizer_preset.dart';

class EqualizerPresetStore extends ChangeNotifier {
  EqualizerPresetStore(this.preferences, {required this.reservedNames}) {
    try {
      final decoded = jsonDecode(preferences.getString(key) ?? '[]');
      if (decoded is! List) return;
      final ids = <String>{}, names = <String>{};
      for (final entry in decoded) {
        if (entry is! Map ||
            entry['id'] is! String ||
            entry['name'] is! String ||
            entry['gains'] is! List) {
          continue;
        }
        final id = entry['id'] as String,
            name = (entry['name'] as String).trim();
        final values = entry['gains'] as List;
        if (id.isEmpty ||
            ids.contains(id) ||
            names.contains(name.toLowerCase()) ||
            nameError(name) != null ||
            values.length != 10 ||
            values.any(
              (v) => v is! num || !v.toDouble().isFinite || v.abs() > 12,
            )) {
          continue;
        }
        ids.add(id);
        names.add(name.toLowerCase());
        _items.add(
          EqualizerPreset(
            name,
            List<double>.unmodifiable(values.map((v) => (v as num).toDouble())),
            id: id,
          ),
        );
      }
    } catch (_) {
      /* Keep usable defaults when an old preference is malformed. */
    }
  }
  static const key = 'player_saved_equalizer_presets';
  final SharedPreferences preferences;
  final Set<String> reservedNames;
  List<EqualizerPreset> _items = [];
  Future<void> _pending = Future.value();
  bool _disposed = false;
  List<EqualizerPreset> get presets => List.unmodifiable(_items);

  String? nameError(String input) {
    final name = input.trim();
    if (name.isEmpty) return '请输入预设名称';
    if (name.runes.length > 40) return '名称最多40个字';
    final folded = name.toLowerCase();
    if (reservedNames.any((n) => n.toLowerCase() == folded) ||
        _items.any((p) => p.name.toLowerCase() == folded)) {
      return '已有同名预设';
    }
    return null;
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final task = _pending.then((_) => operation());
    _pending = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return task;
  }

  Future<void> _persist(List<EqualizerPreset> next) async {
    final success = await preferences.setString(
      key,
      jsonEncode([
        for (final p in next) {'id': p.id, 'name': p.name, 'gains': p.gains},
      ]),
    );
    if (!success) throw StateError('无法保存均衡器参数');
    _items = next;
    if (!_disposed) notifyListeners();
  }

  Future<EqualizerPreset> save(String input, List<double> values) {
    final gains = List<double>.unmodifiable(values);
    return _enqueue(() async {
      final error = nameError(input);
      if (error != null) throw ArgumentError(error);
      if (gains.length != 10 || gains.any((g) => !g.isFinite || g.abs() > 12)) {
        throw ArgumentError('均衡器参数无效');
      }
      final preset = EqualizerPreset(
        input.trim(),
        gains,
        id: const Uuid().v4(),
      );
      await _persist([..._items, preset]);
      return preset;
    });
  }

  Future<bool> remove(String id) => _enqueue(() async {
    if (!_items.any((p) => p.id == id)) return false;
    await _persist(_items.where((p) => p.id != id).toList());
    return true;
  });

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
