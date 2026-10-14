import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myune_music/services/equalizer_preset_store.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';
import 'package:myune_music/page/setting/equalizer_preset_widgets.dart';

class _Notifier extends ChangeNotifier implements PlaylistContentNotifier {
  _Notifier(this.store);
  final EqualizerPresetStore store;
  final gains = List<double>.filled(10, 3);
  @override
  bool get canSaveEqualizerPreset => true;
  @override
  List<EqualizerPreset> get savedEqualizerPresets => store.presets;
  @override
  Future<void> saveEqualizerPreset(String name) async {
    await store.save(name, gains);
    notifyListeners();
  }

  @override
  Future<void> removeEqualizerPreset(String id) async {
    await store.remove(id);
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late EqualizerPresetStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = EqualizerPresetStore(
      await SharedPreferences.getInstance(),
      reservedNames: {'默认', 'Rock'},
    );
  });
  tearDown(() => store.dispose());
  test(
    'save captures immutable gains and survives restart; removal persists',
    () async {
      final values = List<double>.filled(10, 4);
      final pending = store.save(' 我的预设 ', values);
      values[0] = 12;
      final preset = await pending;
      expect(preset.name, '我的预设');
      expect(preset.gains, List.filled(10, 4));
      expect(() => preset.gains[0] = 1, throwsUnsupportedError);
      final restored = EqualizerPresetStore(
        await SharedPreferences.getInstance(),
        reservedNames: {'默认', 'Rock'},
      );
      expect(restored.presets.single.id, preset.id);
      expect(restored.presets.single.gains, preset.gains);
      expect(await restored.remove(preset.id!), isTrue);
      expect(await restored.remove(preset.id!), isFalse);
      restored.dispose();
      final empty = EqualizerPresetStore(
        await SharedPreferences.getInstance(),
        reservedNames: {},
      );
      expect(empty.presets, isEmpty);
      empty.dispose();
    },
  );
  test(
    'reserved, blank, duplicate names and invalid gains are rejected',
    () async {
      final gains = List<double>.filled(10, 0);
      for (final name in [' ', 'rock', '默认', '字' * 41]) {
        await expectLater(store.save(name, gains), throwsArgumentError);
      }
      await expectLater(store.save('bad', [double.nan]), throwsArgumentError);
      await store.save('A', gains);
      await expectLater(store.save(' a ', gains), throwsArgumentError);
      expect(store.presets, hasLength(1));
    },
  );
  test(
    'concurrent naming cannot create duplicates, errors do not poison later saves',
    () async {
      final a = store.save('same', List.filled(10, 1));
      final b = store.save('SAME', List.filled(10, 2));
      await expectLater(b, throwsArgumentError);
      await a;
      await store.save('next', List.filled(10, 3));
      expect(store.presets.map((p) => p.name), ['same', 'next']);
    },
  );
  test('malformed entries do not replace built-ins or crash loading', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      EqualizerPresetStore.key,
      jsonEncode([
        {'id': '1', 'name': '默认', 'gains': List.filled(10, 1)},
        {'id': '2', 'name': 'valid', 'gains': List.filled(10, -4)},
        {
          'id': '3',
          'name': 'bad',
          'gains': [20],
        },
        {'id': '2', 'name': 'duplicate-id', 'gains': List.filled(10, 2)},
        'garbage',
      ]),
    );
    final restored = EqualizerPresetStore(prefs, reservedNames: {'默认'});
    expect(restored.presets.map((p) => p.name), ['valid']);
    restored.dispose();
  });
  test(
    'finishing a save after disposal does not notify disposed listeners',
    () async {
      final other = EqualizerPresetStore(
        await SharedPreferences.getInstance(),
        reservedNames: {},
      );
      final pending = other.save('late', List.filled(10, 0));
      other.dispose();
      await pending;
    },
  );
  testWidgets(
    'name/save and Advanced removal operate on the same persisted preset',
    (tester) async {
      final notifier = _Notifier(store);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EqualizerSaveButton(notifier: notifier)),
        ),
      );
      await tester.tap(find.text('保留均衡器参数'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '人声');
      await tester.tap(find.text('保存'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(store.presets.single.name, '人声');
      await tester.pumpWidget(
        ChangeNotifierProvider<PlaylistContentNotifier>.value(
          value: notifier,
          child: const MaterialApp(home: EqualizerPresetManager()),
        ),
      );
      expect(find.text('人声'), findsOneWidget);
      await tester.tap(find.byTooltip('移除预设'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(find.text('暂无保存的均衡器参数'), findsOneWidget);
      expect(store.presets, isEmpty);
      await tester.pumpWidget(const SizedBox());
      notifier.dispose();
    },
  );
}
