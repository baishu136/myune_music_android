import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/page/setting/update_checker.dart';
import 'package:myune_music/services/automatic_update_controller.dart';

const url =
    'https://github.com/baishu136/myune_music_android/releases/download/v1.0.0-android.999/Myune-Music-1.0.0-android.999-arm64-v8a.apk';
final update = UpdateCheckResult.successUpdateAvailable(
  UpdateInfo(
    latestVersion: '1.0.0-android.999',
    releaseNotes: '',
    downloadUrl: UpdateChecker.projectUrl,
    apk: const UpdateApk(
      url: url,
      name: 'Myune-Music-1.0.0-android.999-arm64-v8a.apk',
      size: 123,
    ),
  ),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('default enabled and explicit off survives restart', () async {
    final a = SettingsProvider();
    await a.initializationFuture;
    expect(a.autoUpdateDownload, isTrue);
    await a.setAutoUpdateDownload(false);
    final b = SettingsProvider();
    await b.initializationFuture;
    expect(b.autoUpdateDownload, isFalse);
    a.dispose();
    b.dispose();
  });
  test(
    'release parsing rejects drafts, previews and wrong assets, finds newest stable',
    () {
      Map<String, Object> release(
        int n, {
        bool draft = false,
        bool preview = false,
      }) => {
        'tag_name': 'v1.0.0-android.$n',
        'draft': draft,
        'prerelease': preview,
        'assets': [
          {'name': 'source.zip', 'size': 99, 'browser_download_url': url},
          {
            'name': 'wrong-arm64-v8a.apk',
            'size': 123,
            'browser_download_url': 'https://evil.example/update.apk',
          },
          {
            'name': 'Myune-Music-1.0.0-android.999-arm64-v8a.apk',
            'size': 123,
            'browser_download_url': url,
            'digest': 'sha256:${List.filled(64, 'a').join()}',
          },
        ],
      };
      final result = UpdateChecker.parseReleases([
        release(998),
        release(1000, preview: true),
        release(1001, draft: true),
        release(999),
      ], '1.0.0-android.419');
      expect(result.updateInfo!.latestVersion, '1.0.0-android.999');
      expect(result.updateInfo!.apk!.sha256, List.filled(64, 'a').join());
      expect(
        UpdateChecker.parseReleases([release(419)], '1.0.0-android.419').type,
        UpdateCheckResultType.successNoUpdate,
      );
      expect(
        UpdateApk.fromAssets([
          {
            'name': 'a-arm64-v8a.apk',
            'size': 123,
            'browser_download_url': 'http://github.com/a',
          },
        ]),
        isNull,
      );
    },
  );
  test('HTTP failure and malformed data are recoverable results', () async {
    for (final response in [
      http.Response('', 403),
      http.Response('broken', 200),
      http.Response('{}', 200),
    ]) {
      final client = MockClient((_) async => response);
      expect(
        (await UpdateChecker.checkForUpdates(
          '1.0.0-android.419',
          client: client,
        )).type,
        UpdateCheckResultType.error,
      );
      client.close();
    }
  });
  Future<void> scenario(
    Future<void> Function(
      SettingsProvider,
      AutomaticUpdateController,
      List<MethodCall>,
      int Function(),
    )
    body, {
    bool enabled = true,
    Object? savedNextCheck,
    Future<UpdateCheckResult> Function(String)? check,
  }) async {
    SharedPreferences.setMockInitialValues({
      'autoUpdateDownload419': enabled,
      if (savedNextCheck != null) 'automaticUpdateNextCheck419': savedNextCheck,
    });
    final settings = SettingsProvider();
    await settings.initializationFuture;
    const channel = MethodChannel('updater419-test');
    final calls = <MethodCall>[];
    var checks = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'status' ? {'state': 'none'} : null;
    });
    final controller = AutomaticUpdateController(
      settings,
      channel: channel,
      android: true,
      startupDelay: const Duration(days: 1),
      version: () async => '1.0.0-android.419',
      check: (v) {
        checks++;
        return check?.call(v) ?? Future.value(update);
      },
    );
    try {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await body(settings, controller, calls, () => checks);
    } finally {
      controller.dispose();
      settings.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    }
  }

  test(
    'automatic checks deduplicate, throttle and hand the real APK to native downloads',
    () async {
      await scenario((s, c, calls, count) async {
        await Future.wait([
          c.checkNow(automatic: true),
          c.checkNow(automatic: true),
        ]);
        expect(count(), 1);
        expect(calls.where((m) => m.method == 'download'), hasLength(1));
        expect(
          (calls.firstWhere((m) => m.method == 'download').arguments
              as Map)['automatic'],
          isTrue,
        );
        await c.checkNow(automatic: true);
        expect(count(), 1);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('automaticUpdateNextCheck419'), isNotNull);
      });
    },
  );
  test(
    'off blocks automatic work, while explicit manual checks can download',
    () async {
      await scenario((s, c, calls, count) async {
        await c.checkNow(automatic: true);
        expect(count(), 0);
        await c.checkNow();
        expect(count(), 1);
        expect(
          (calls.firstWhere((m) => m.method == 'download').arguments
              as Map)['automatic'],
          isFalse,
        );
      }, enabled: false);
    },
  );
  test(
    'turning off during a request discards its result and cancels native auto work',
    () async {
      final gate = Completer<UpdateCheckResult>();
      await scenario((s, c, calls, count) async {
        final checking = c.checkNow(automatic: true);
        await Future<void>.delayed(Duration.zero);
        await s.setAutoUpdateDownload(false);
        gate.complete(update);
        await checking;
        expect(calls.where((m) => m.method == 'download'), isEmpty);
        expect(
          calls.where((m) => m.method == 'enabled').last.arguments,
          isFalse,
        );
      }, check: (_) => gate.future);
    },
  );
  test(
    'corrupt or implausible check timestamps cannot disable updating',
    () async {
      for (final timestamp in [
        'broken',
        DateTime.now().add(const Duration(days: 20)).millisecondsSinceEpoch,
      ]) {
        await scenario((s, c, calls, count) async {
          await c.checkNow(automatic: true);
          expect(count(), 1);
        }, savedNextCheck: timestamp);
      }
    },
  );
  test(
    'network failure leaves ordinary playback untouched and permits manual retry',
    () async {
      var n = 0;
      await scenario(
        (s, c, calls, count) async {
          await c.checkNow();
          expect(c.error, contains('offline'));
          await c.checkNow();
          expect(calls.where((m) => m.method == 'download'), hasLength(1));
        },
        check: (_) async =>
            n++ == 0 ? UpdateCheckResult.error('offline') : update,
      );
    },
  );
}
