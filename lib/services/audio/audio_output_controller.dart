import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import '../../models/audio_output_state.dart';
import '../lyric_sync_preferences.dart';
import 'audio_output_error_policy.dart';

/// Route policy for the existing Player. No decoder, queue or transport state here.
class AudioOutputController extends ChangeNotifier {
  AudioOutputController({
    required this.player,
    bool? android,
    MethodChannel? channel,
    EventChannel? events,
  }) : supported = android ?? Platform.isAndroid,
       _channel =
           channel ?? const MethodChannel('com.myune.music/audio_output'),
       _events =
           events ?? const EventChannel('com.myune.music/audio_output_events') {
    initializationFuture = _initialize();
  }
  final PlayerApi player;
  final bool supported;
  final MethodChannel _channel;
  final EventChannel _events;
  final sync = LyricSyncPreferences();
  late final Future<void> initializationFuture;
  AudioOutputSnapshot snapshot = AudioOutputSnapshot.fromMap({});
  StreamSubscription<dynamic>? _nativeEvents;
  StreamSubscription<AudioParams>? _params;
  StreamSubscription<MpvPlayerError>? _errors;
  AudioOutputMode mode = AudioOutputMode.standard;
  OutputPcmFormat? requestedFormat;
  int? requestedDeviceId;
  String? message;
  bool busy = false, _disposed = false;
  int _request = 0;
  Future<void> _tail = Future.value();
  Timer? _formatDebounce;
  Timer? _recoveryTimer;
  bool _compatibleBackend = false;
  Object? _configuredSource;
  Future<void>? _release;
  int _systemRouteRevision = 0;
  String? _lastProfileKey;
  int _snapshotRevision = -1;
  bool _dspBypassConfirmed = false;
  AudioOutputDevice? get current => snapshot.current;
  bool get bitPerfectReported =>
      mode == AudioOutputMode.bitPerfect &&
      _dspBypassConfirmed &&
      requestedFormat != null &&
      player.state.audioParams.sampleRate == requestedFormat!.sampleRate &&
      player.state.audioParams.channelCount == requestedFormat!.channels &&
      (player.state.audioParams.format?.mpvValue ==
              requestedFormat!.mpvFormat ||
          player.state.audioParams.format?.mpvValue ==
              '${requestedFormat!.mpvFormat}p') &&
      snapshot.matches(requestedFormat!);
  bool get exclusiveReported =>
      mode == AudioOutputMode.exclusive && snapshot.exclusiveConfirmed;

  Future<void> _initialize() async {
    await sync.initializationFuture;
    if (!supported || _disposed) return;
    _nativeEvents = _events.receiveBroadcastStream().listen(
      (data) {
        if (data is Map && !_disposed) {
          try {
            _accept(data);
          } catch (error) {
            message = '设备状态无效，保留普通播放：$error';
            notifyListeners();
          }
        }
      },
      onError: (Object error) {
        if (!_disposed) {
          message = '设备状态读取失败：$error';
          notifyListeners();
        }
      },
    );
    try {
      await refresh();
      if (snapshot.bridgeAvailable && snapshot.sdk >= 26) {
        // Default remains system automatic (device-id 0), with the old backend as fallback.
        await player.setRawProperty('ao', 'aaudio,audiotrack,opensles');
      }
    } catch (error) {
      message = '输出管理暂不可用：$error';
    }
    if (_disposed) return;
    _params = player.stream.audioParams.listen((params) {
      final identity = (params.format, params.sampleRate, params.channelCount);
      if (identity == _configuredSource) return;
      _dspBypassConfirmed = false;
      notifyListeners();
      _formatDebounce?.cancel();
      if (mode != AudioOutputMode.bitPerfect) return;
      if ((params.sampleRate ?? 0) <= 0 ||
          (params.channelCount ?? 0) <= 0 ||
          params.format == null) {
        return;
      }
      _formatDebounce = Timer(const Duration(milliseconds: 120), () {
        if (!_disposed && !busy && mode == AudioOutputMode.bitPerfect) {
          unawaited(_run(() => _configureBitPerfect(requestedDeviceId)));
        }
      });
    });
    _errors = player.stream.error.listen((error) {
      if (busy || !isAudioOutputFailure(error)) return;
      _recoverAfterSettling(() async {
        if (!player.state.playWhenReady) return false;
        final driver = await player.getRawProperty('current-ao');
        // The engine has already rebuilt a healthy stream: leave it alone.
        if (player.state.playing &&
            driver != null &&
            driver.isNotEmpty &&
            driver != 'null' &&
            (current != null || driver != 'aaudio')) {
          return false;
        }
        _compatibleBackend = true;
        return true;
      }, '输出未能恢复，已切换兼容的系统自动输出');
    });
    notifyListeners();
  }

  void _accept(Map data) {
    if (_disposed) return;
    final revision = (data['snapshotRevision'] as num?)?.toInt() ?? 0;
    if (revision < _snapshotRevision) return;
    _snapshotRevision = revision;
    final previousDevice = current;
    final previousOverride = sync.deviceOverrideMs;
    final previousProfile = _lastProfileKey;
    final systemRevision = (data['systemRouteRevision'] as num?)?.toInt() ?? 0;
    final systemChanged = systemRevision > _systemRouteRevision;
    _systemRouteRevision = systemRevision;
    snapshot = AudioOutputSnapshot.fromMap(data);
    final device = current;
    if (device != null) {
      _lastProfileKey = device.profileKey;
      sync.useDevice(device.profileKey, persistent: device.persistentIdentity);
      if (previousDevice?.id == device.id &&
          previousProfile != device.profileKey &&
          previousProfile?.startsWith('connection:') == true &&
          device.persistentIdentity &&
          previousOverride != null) {
        unawaited(
          sync.setDevice(previousOverride).catchError((Object error) {
            if (!_disposed) {
              message = '设备同步配置保存失败：$error';
              notifyListeners();
            }
          }),
        );
      }
    } else {
      _lastProfileKey = null;
      sync.useDevice(null, persistent: false);
    }
    if (data['identityNotice'] is String) {
      message = data['identityNotice'] as String;
    }
    if (systemChanged && !busy && requestedDeviceId != null) {
      _recoverAfterSettling(
        () async => requestedDeviceId != null,
        '已跟随用户的系统输出选择',
      );
    } else if (!busy &&
        requestedDeviceId != null &&
        !snapshot.devices.any((d) => d.id == requestedDeviceId)) {
      _recoverAfterSettling(
        () async =>
            requestedDeviceId != null &&
            !snapshot.devices.any((d) => d.id == requestedDeviceId),
        '所选设备已断开，已恢复系统自动输出',
      );
    } else if (!busy &&
        current?.usb == true &&
        ((mode == AudioOutputMode.bitPerfect && !snapshot.mixerConfirmed) ||
            (mode == AudioOutputMode.exclusive &&
                !snapshot.exclusiveConfirmed))) {
      _recoverAfterSettling(
        () async =>
            current?.usb == true &&
            ((mode == AudioOutputMode.bitPerfect && !snapshot.mixerConfirmed) ||
                (mode == AudioOutputMode.exclusive &&
                    !snapshot.exclusiveConfirmed)),
        '系统已撤回专用输出，已恢复标准模式',
      );
    }
    notifyListeners();
  }

  void _recoverAfterSettling(
    Future<bool> Function() stillFailed,
    String reason,
  ) {
    if (_disposed || busy || _recoveryTimer != null) return;
    _recoveryTimer = Timer(const Duration(milliseconds: 900), () {
      _recoveryTimer = null;
      if (_disposed || busy) return;
      unawaited(
        _run(() async {
          await refresh();
          if (!await stillFailed()) return;
          await _standard();
          message = reason;
        }),
      );
    });
  }

  Future<void> refresh() async {
    if (!supported || _disposed) return;
    final data = await _channel.invokeMapMethod<Object?, Object?>('snapshot');
    if (data != null && !_disposed) _accept(data);
  }

  Future<void> _run(Future<void> Function() operation) {
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    final revision = ++_request;
    final result = _tail.catchError((_) {}).then((_) async {
      if (_disposed || revision != _request) return;
      busy = true;
      message = null;
      notifyListeners();
      try {
        await operation();
      } catch (error) {
        try {
          await _standard();
        } catch (_) {}
        message = '切换未完成，已尝试恢复普通输出：$error';
      } finally {
        if (!_disposed) {
          busy = false;
          notifyListeners();
        }
      }
    });
    _tail = result;
    return result;
  }

  AudioOutputDevice _device(int id) => snapshot.devices.firstWhere(
    (d) => d.id == id,
    orElse: () => throw StateError('设备已断开'),
  );
  Future<void> selectDevice(int id) => _run(() async {
    await initializationFuture;
    final device = _device(id);
    if (!device.directSelectable) throw StateError('系统限制此设备直接切换，请使用系统输出选择');
    if (mode == AudioOutputMode.standard &&
        current?.id == id &&
        requestedDeviceId == id) {
      return;
    }
    await _standard(resetDevice: false, reload: false);
    _compatibleBackend = false;
    requestedDeviceId = id;
    await player.setRawProperty('aaudio-device-id', '$id');
    await player.setRawProperty('ao', 'aaudio');
    await player.reloadAudio();
    await _verifyRoute(id);
  });
  Future<void> useAutomatic() => _run(() => _standard());
  Future<void> requestUsbIdentity() async {
    final device = current;
    if (device == null || !device.usb) return;
    await _channel.invokeMethod('requestUsbIdentity', {'id': device.id});
    await refresh();
  }

  Future<void> systemPicker() async {
    await useAutomatic();
    await _channel.invokeMethod<void>('systemPicker');
  }

  Future<void> _verifyRoute(int id) async {
    for (var i = 0; i < 4; i++) {
      await refresh();
      if (current?.id == id) {
        message = '实际输出已切换至 ${current!.name}';
        return;
      }
      if (!player.state.playWhenReady) {
        message = '已请求此设备；播放后才能确认实际输出';
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    throw StateError('实际输出未切换至所选设备；系统可能拒绝此路由');
  }

  Future<void> setMode(AudioOutputMode value) => _run(() async {
    await initializationFuture;
    if (value == AudioOutputMode.standard) {
      await _standard(resetDevice: false);
      return;
    }
    final id = requestedDeviceId ?? current?.id;
    if (id == null || !_device(id).usb) throw StateError('请先选择已连接的 USB 音频设备');
    if (value == AudioOutputMode.bitPerfect) {
      await _configureBitPerfect(id);
      return;
    }
    await _channel.invokeMethod<void>('clearMixer');
    await player.setTransparentOutput(false);
    await player.setAudioExclusive(true);
    await player.setRawProperty('aaudio-performance-mode', 'low-latency');
    await player.setRawProperty('aaudio-device-id', '$id');
    await player.setRawProperty('ao', 'aaudio');
    requestedDeviceId = id;
    await player.reloadAudio();
    await _verifyRoute(id);
    if (!snapshot.exclusiveConfirmed) throw StateError('系统仅提供共享输出，未获得 USB 独占流');
    mode = value;
    message = 'AAudio 已报告 USB 独占流；这不是直接接管 USB 的驱动，也不等同于 Bit-Perfect';
  });
  Future<void> _configureBitPerfect(int? requestedId) async {
    final id = requestedId ?? current?.id;
    if (id == null) throw StateError('没有已确认的 USB 输出');
    final device = _device(id);
    final source = player.state.audioParams;
    _configuredSource = (source.format, source.sampleRate, source.channelCount);
    final rate = source.sampleRate, channels = source.channelCount;
    final sourceFormat = source.format?.mpvValue;
    final format = device.mixerFormats
        .where(
          (f) =>
              f.bitPerfect &&
              f.mpvFormat != null &&
              f.sampleRate == rate &&
              f.channels == channels &&
              (sourceFormat == f.mpvFormat ||
                  sourceFormat == '${f.mpvFormat}p'),
        )
        .firstOrNull;
    if (format == null) {
      throw StateError('当前歌曲 PCM 格式与系统报告的 Bit-Perfect 格式不匹配，保留普通播放');
    }
    await _channel.invokeMethod('requestMixer', {
      'id': id,
      'sampleRate': format.sampleRate,
      'encoding': format.encoding,
      'channels': format.channels,
    });
    await player.setAudioExclusive(false);
    await player.setTransparentOutput(
      true,
      format: format.mpvFormat!,
      sampleRate: format.sampleRate,
      channels: channels == 1
          ? 'mono'
          : channels == 2
          ? 'stereo'
          : '${channels}ch',
    );
    await player.setRawProperty('aaudio-device-id', '$id');
    await player.setRawProperty('ao', 'aaudio');
    requestedDeviceId = id;
    requestedFormat = format;
    mode = AudioOutputMode.bitPerfect;
    await player.reloadAudio();
    await _verifyRoute(id);
    final checks = await Future.wait([
      for (final name in [
        'af',
        'volume',
        'volume-gain',
        'speed',
        'pitch',
        'replaygain',
      ])
        player.getRawProperty(name),
    ]);
    _dspBypassConfirmed =
        checks[0]?.isEmpty == true &&
        double.tryParse(checks[1] ?? '') == 100 &&
        double.tryParse(checks[2] ?? '') == 0 &&
        double.tryParse(checks[3] ?? '') == 1 &&
        double.tryParse(checks[4] ?? '') == 1 &&
        checks[5] == 'no';
    if (!_dspBypassConfirmed) throw StateError('未能确认音效与软件增益已旁路');
    message = bitPerfectReported
        ? '系统报告 Bit-Perfect，应用与硬件格式一致；端到端位流未做外部测量'
        : '已请求 Bit-Perfect，但尚无完整硬件回执；不能确认严格 Bit-Perfect';
  }

  Future<void> _standard({bool resetDevice = true, bool reload = true}) async {
    mode = AudioOutputMode.standard;
    _dspBypassConfirmed = false;
    _configuredSource = null;
    requestedFormat = null;
    Object? failure;
    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action();
      } catch (error) {
        failure ??= error;
      }
    }

    await attempt(() => _channel.invokeMethod<void>('clearMixer'));
    await attempt(() => player.setTransparentOutput(false));
    await attempt(() => player.setAudioExclusive(false));
    await attempt(
      () => player.setRawProperty('aaudio-performance-mode', 'none'),
    );
    if (resetDevice) {
      requestedDeviceId = null;
      await attempt(() => player.setRawProperty('aaudio-device-id', '0'));
    }
    await attempt(
      () => player.setRawProperty(
        'ao',
        requestedDeviceId == null
            ? (_compatibleBackend
                  ? 'audiotrack,opensles'
                  : 'aaudio,audiotrack,opensles')
            : 'aaudio',
      ),
    );
    if (reload) {
      await attempt(player.reloadAudio);
      await attempt(refresh);
    }
    if (failure != null) throw StateError('普通输出恢复时部分接口失败：$failure');
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    _formatDebounce?.cancel();
    _recoveryTimer?.cancel();
    unawaited(_nativeEvents?.cancel());
    unawaited(_params?.cancel());
    unawaited(_errors?.cancel());
    sync.dispose();
    super.dispose();
  }

  Future<void> releaseResources() => _release ??= () async {
    await _tail.catchError((_) {});
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('clearMixer');
    } catch (_) {}
    try {
      await player.setTransparentOutput(false);
    } catch (_) {}
    try {
      await player.setAudioExclusive(false);
    } catch (_) {}
  }();
}
