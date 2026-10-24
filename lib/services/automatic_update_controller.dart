import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_version.dart';
import '../page/setting/settings_provider.dart';
import '../page/setting/update_checker.dart';
import 'interaction_performance_controller.dart';

/// One lifecycle-owned updater. System download service owns transfer/retry;
/// there is no progress polling, playback subscription, or automatic install.
class AutomaticUpdateController extends ChangeNotifier
    with WidgetsBindingObserver {
  AutomaticUpdateController(
    this.settings, {
    MethodChannel? channel,
    bool? android,
    Future<String> Function()? version,
    Future<UpdateCheckResult> Function(String)? check,
    DateTime Function()? now,
    this.startupDelay = const Duration(seconds: 4),
  }) : supported = android ?? Platform.isAndroid,
       _channel = channel ?? const MethodChannel('com.myune.music/updates'),
       _version = version ?? AppVersion.current,
       _check = check ?? UpdateChecker.checkForUpdates,
       _now = now ?? DateTime.now {
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    settings.addListener(_settingsChanged);
    _enabled = settings.autoUpdateDownload;
    if (supported) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'changed') await refresh();
      });
      unawaited(_initialize());
    }
  }
  final SettingsProvider settings;
  final bool supported;
  final MethodChannel _channel;
  final Future<String> Function() _version;
  final Future<UpdateCheckResult> Function(String) _check;
  final DateTime Function() _now;
  final Duration startupDelay;
  bool _enabled = true, _closed = false, _foreground = true;
  int _generation = 0;
  Timer? _timer;
  Future<void>? _checking;
  int _nextCheckMs = 0;
  String? error;
  Map<Object?, Object?> download = const {};
  UpdateInfo? available;
  bool checking = false;

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.get('automaticUpdateNextCheck419');
    final latest = _now().add(const Duration(hours: 6)).millisecondsSinceEpoch;
    _nextCheckMs = saved is int && saved >= 0 && saved <= latest ? saved : 0;
    if (_closed) return;
    await _setNativeEnabled();
    await refresh();
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (!_closed && supported && _enabled && _foreground) {
      _timer = Timer(startupDelay, () => unawaited(checkNow(automatic: true)));
    }
  }

  void _settingsChanged() {
    if (_enabled == settings.autoUpdateDownload) return;
    _enabled = settings.autoUpdateDownload;
    _generation++;
    _timer?.cancel();
    unawaited(_setNativeEnabled().then((_) => refresh()));
    _schedule();
  }

  Future<void> _setNativeEnabled() async {
    if (!supported || _closed) return;
    try {
      await _channel.invokeMethod<void>('enabled', _enabled);
    } catch (e) {
      if (!_closed) {
        error = '更新下载不可用：$e';
        notifyListeners();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      unawaited(refresh());
      _schedule();
    } else {
      _timer?.cancel();
    }
  }

  Future<void> checkNow({bool automatic = false}) {
    if (_closed ||
        !supported ||
        (automatic &&
            (!_enabled ||
                !_foreground ||
                _now().millisecondsSinceEpoch < _nextCheckMs))) {
      return Future.value();
    }
    return _checking ??= _performCheck(
      automatic,
    ).whenComplete(() => _checking = null);
  }

  Future<void> _performCheck(bool automatic) async {
    final generation = _generation;
    checking = true;
    error = null;
    notifyListeners();
    try {
      if (automatic) {
        await InteractionPerformanceController.instance.waitForIdle(
          maxWait: const Duration(seconds: 2),
        );
        if (_closed || !_enabled || !_foreground || generation != _generation) {
          return;
        }
        if (InteractionPerformanceController.instance.blocksFluidAnimation) {
          _schedule();
          return;
        }
      }
      final result = await _check(await _version());
      if (_closed || (automatic && (!_enabled || generation != _generation))) {
        return;
      }
      _nextCheckMs = _now()
          .add(
            Duration(hours: result.type == UpdateCheckResultType.error ? 1 : 6),
          )
          .millisecondsSinceEpoch;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('automaticUpdateNextCheck419', _nextCheckMs);
      if (_closed || (automatic && (!_enabled || generation != _generation))) {
        return;
      }
      available = result.updateInfo;
      if (result.type == UpdateCheckResultType.error) {
        error = result.errorMessage ?? '检查更新失败';
      } else if (result.updateInfo?.apk != null) {
        await downloadUpdate(automatic: automatic);
      }
    } catch (e) {
      if (!_closed) error = '检查更新失败：$e';
    } finally {
      if (!_closed) {
        checking = false;
        notifyListeners();
      }
    }
  }

  Future<void> downloadUpdate({bool automatic = false}) async {
    final info = available, apk = available?.apk;
    if (_closed || apk == null || info == null || (automatic && !_enabled)) {
      return;
    }
    try {
      await _channel.invokeMethod<Object?>('download', {
        'url': apk.url,
        'name': apk.name,
        'size': apk.size,
        'sha256': apk.sha256,
        'version': info.latestVersion,
        'automatic': automatic,
      });
      await refresh();
    } catch (e) {
      if (!_closed) {
        error = '下载失败：$e';
        notifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    if (_closed || !supported) return;
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>('status');
      final installed = await _version();
      if (_closed) return;
      final version = result?['version'];
      download =
          version is String && !UpdateChecker.isVersionNewer(version, installed)
          ? const {'state': 'none'}
          : result ?? const {};
      notifyListeners();
    } catch (e) {
      if (!_closed) {
        error = '读取更新下载状态失败：$e';
        notifyListeners();
      }
    }
  }

  Future<void> openDownload() async {
    if (_closed) return;
    try {
      await _channel.invokeMethod<void>('open');
    } catch (e) {
      if (!_closed) {
        error = '无法打开下载：$e';
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    _timer?.cancel();
    settings.removeListener(_settingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    if (supported) _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
