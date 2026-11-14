import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myune_music/plugins/plugin_controller.dart';
import 'package:myune_music/plugins/plugin_package.dart';
import 'package:myune_music/plugins/plugin_network.dart';
import 'package:myune_music/plugins/plugin_runtime.dart';

PluginPackage package({
  String id = 'test.plugin',
  List<String> permissions = const [],
  List<String> features = const [],
}) => PluginPackage.parse(
  jsonEncode({
    'manifest': {
      'id': id,
      'name': '测试插件',
      'version': '1.0.0',
      'sdk': 1,
      'permissions': permissions,
      'features': features,
    },
    'script': 'globalThis.myunePlugin=()=>null;',
  }),
);

class Runtime implements PluginRuntime {
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? onStart;
  List<Map<String, dynamic>>? responses;
  int closed = 0, starts = 0;
  @override
  Future<Map<String, dynamic>> start(
    String code,
    Map<String, dynamic> event,
  ) async {
    starts++;
    return onStart == null ? {'done': true, 'value': 42} : onStart!(event);
  }

  @override
  Future<Map<String, dynamic>> step(
    List<Map<String, dynamic>> responses,
  ) async {
    this.responses = responses;
    return {'done': true, 'value': responses};
  }

  @override
  Future<void> close() async {
    closed++;
  }
}

class Host implements PluginHost {
  @override
  String? songIdentity = 'song-a';
  int mutations = 0;
  @override
  Map<String, dynamic> snapshot() => {'song': songIdentity};
  @override
  Future<Object?> call(String method, Map<String, dynamic> args) async {
    mutations++;
    return true;
  }
}

Map<String, dynamic> request(
  String method, [
  Map<String, dynamic> args = const {},
]) => {
  'done': false,
  'calls': [
    {'id': 1, 'method': method, 'args': args},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late Runtime runtime;
  late PluginController controller;
  late Host host;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    runtime = Runtime();
    controller = PluginController(prefs, runtime: runtime);
    host = Host();
    controller.bindHost(host);
  });
  tearDown(() => controller.dispose());
  Future<PluginEntry> enabled(PluginPackage p) async {
    await controller.install(p);
    final e = controller.entries.last;
    await controller.setEnabled(e, true);
    return e;
  }

  test(
    'package rejects unknown capabilities, incompatible SDK, wildcard domains and oversize',
    () {
      final json =
          jsonDecode(jsonEncode(package().json)) as Map<String, dynamic>;
      for (final change in [
        {'sdk': 2},
        {
          'permissions': ['native.execute'],
        },
        {
          'features': ['unknown'],
        },
        {
          'permissions': ['network'],
          'networkDomains': ['*.example.com'],
        },
        {
          'features': ['lyrics'],
          'permissions': [],
        },
      ]) {
        final copy = {
          ...json,
          'manifest': {...json['manifest'] as Map, ...change},
        };
        expect(
          () => PluginPackage.parse(jsonEncode(copy)),
          throwsFormatException,
        );
      }
      expect(
        () => PluginPackage.parse(' ' * (pluginPackageByteLimit + 1)),
        throwsFormatException,
      );
    },
  );
  test(
    'import never executes and replacement revokes grants and clears private storage',
    () async {
      final e = await enabled(package(permissions: ['storage']));
      e.storage['private'] = 'old';
      final starts = runtime.starts;
      await controller.install(
        package(permissions: ['storage', 'playback.control']),
      );
      expect(runtime.starts, starts);
      expect(e.enabled, false);
      expect(controller.entries.single.enabled, false);
      expect(controller.entries.single.storage, isEmpty);
      await expectLater(
        controller.invoke(e, 'ui.open'),
        throwsA(isA<PluginCancelled>()),
      );
    },
  );
  test(
    'ungranted host command is rejected without calling the player',
    () async {
      final e = await enabled(package());
      runtime.onStart = (_) async =>
          request('playback.command', {'command': 'next'});
      final result = await controller.invoke(e, 'ui.action');
      expect((result as List).single['error'], contains('未授权'));
      expect(host.mutations, 0);
    },
  );
  test('automatic events cannot create playback feedback loops', () async {
    final e = await enabled(package(permissions: ['playback.control']));
    runtime.onStart = (_) async =>
        request('playback.command', {'command': 'pause'});
    await controller.invoke(e, 'playback.changed');
    expect(runtime.responses!.single['error'], contains('用户触发'));
    expect(host.mutations, 0);
  });
  test(
    'song changed while JS is waiting rejects late transport command',
    () async {
      final e = await enabled(package(permissions: ['playback.control']));
      final ready = Completer<Map<String, dynamic>>();
      runtime.onStart = (_) => ready.future;
      final result = controller.invoke(e, 'ui.action');
      await Future<void>.delayed(Duration.zero);
      host.songIdentity = 'song-b';
      ready.complete(request('playback.command', {'command': 'pause'}));
      await expectLater(result, throwsA(isA<PluginCancelled>()));
      expect(host.mutations, 0);
      expect(e.failures, 0);
    },
  );
  test(
    'disabling in flight prevents pending storage and player writes',
    () async {
      final e = await enabled(package(permissions: ['storage']));
      final ready = Completer<Map<String, dynamic>>();
      runtime.onStart = (_) => ready.future;
      final result = controller.invoke(e, 'ui.action');
      await Future<void>.delayed(Duration.zero);
      await controller.setEnabled(e, false);
      ready.complete(request('storage.set', {'key': 'late', 'value': true}));
      await expectLater(result, throwsA(isA<PluginCancelled>()));
      expect(e.storage, isEmpty);
    },
  );
  test(
    'three consecutive failures stop the plugin and remain stopped after restart',
    () async {
      final e = await enabled(package());
      runtime.onStart = (_) async => {
        'done': true,
        'error': 'execution time limit',
      };
      for (var i = 0; i < 3; i++) {
        await expectLater(controller.invoke(e, 'ui.open'), throwsStateError);
      }
      expect(e.enabled, false);
      expect(e.failures, 3);
      final restored = PluginController(prefs, runtime: Runtime());
      expect(restored.entries.single.enabled, false);
      restored.dispose();
      expect(runtime.closed, 4);
    },
  );
  test(
    'storage stays in the declaring plugin namespace and restores',
    () async {
      final a = await enabled(
        package(id: 'test.first', permissions: ['storage']),
      );
      final b = await enabled(
        package(id: 'test.second', permissions: ['storage']),
      );
      runtime.onStart = (_) async =>
          request('storage.set', {'key': 'value', 'value': 7});
      await controller.invoke(a, 'ui.action');
      runtime.onStart = (_) async => request('storage.get', {'key': 'value'});
      await controller.invoke(b, 'ui.open');
      expect(runtime.responses!.single['value'], null);
      final restored = PluginController(prefs, runtime: Runtime());
      expect(restored.entries.first.storage['value'], 7);
      restored.dispose();
    },
  );
  test('large storage is refused and existing value is preserved', () async {
    final e = await enabled(package(permissions: ['storage']));
    e.storage['keep'] = 1;
    runtime.onStart = (_) async =>
        request('storage.set', {'key': 'large', 'value': 'x' * 17000});
    await controller.invoke(e, 'ui.action');
    expect(runtime.responses!.single['error'], contains('超限'));
    expect(e.storage, {'keep': 1});
  });
  test('broken lyric provider falls through to a healthy one', () async {
    await enabled(
      package(
        id: 'test.broken',
        permissions: ['lyrics.provide'],
        features: ['lyrics'],
      ),
    );
    await enabled(
      package(
        id: 'test.healthy',
        permissions: ['lyrics.provide'],
        features: ['lyrics'],
      ),
    );
    var attempt = 0;
    runtime.onStart = (_) async => ++attempt == 1
        ? {'done': true, 'error': 'broken'}
        : {
            'done': true,
            'value': {'lrc': '[00:00.00]healthy'},
          };
    expect(
      (await controller.lyrics({'title': 'a'}))!['lrc'],
      contains('healthy'),
    );
  });
  test('disabled or updated provider cannot publish its late lyrics', () async {
    final e = await enabled(
      package(permissions: ['lyrics.provide'], features: ['lyrics']),
    );
    final ready = Completer<Map<String, dynamic>>();
    runtime.onStart = (_) => ready.future;
    final result = controller.lyrics({'title': 'a'});
    await Future<void>.delayed(Duration.zero);
    await controller.setEnabled(e, false);
    ready.complete({
      'done': true,
      'value': {'lrc': '[00:00.00]old'},
    });
    expect(await result, null);
  });
  test(
    'bounded queue rejects excess work and unwinds after failures',
    () async {
      final e = await enabled(package());
      final ready = Completer<Map<String, dynamic>>();
      runtime.onStart = (_) => ready.future;
      final tasks = [
        for (var i = 0; i < 8; i++) controller.invoke(e, 'ui.open'),
      ];
      await expectLater(controller.invoke(e, 'ui.open'), throwsStateError);
      ready.complete({'done': true, 'value': true});
      await Future.wait(tasks);
      expect(await controller.invoke(e, 'ui.open'), true);
    },
  );
  test(
    'HTTPS capability blocks missing grant, redirects by policy and private IP ranges',
    () async {
      await expectLater(
        pluginFetch({'example.com'}, {'url': 'http://example.com'}),
        throwsStateError,
      );
      await expectLater(
        pluginFetch({'example.com'}, {'url': 'https://other.example.com'}),
        throwsStateError,
      );
      for (final value in [
        '127.0.0.1',
        '10.1.2.3',
        '172.16.0.1',
        '192.168.2.1',
        '169.254.1.1',
        '100.64.0.1',
        '::1',
        'fc00::1',
        'fe80::1',
        '::ffff:127.0.0.1',
      ]) {
        expect(
          pluginPublicAddress(InternetAddress(value)),
          false,
          reason: value,
        );
      }
      expect(pluginPublicAddress(InternetAddress('8.8.8.8')), true);
      expect(pluginPublicAddress(InternetAddress('2606:4700::1111')), true);
    },
  );
}
