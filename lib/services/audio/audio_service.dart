import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

class _PlaybackConfiguration {
  const _PlaybackConfiguration({
    required this.pitch,
    required this.rate,
    required this.eqGains,
    required this.eqFrequencies,
    required this.exclusiveMode,
  });

  final double pitch;
  final double rate;
  final List<double> eqGains;
  final List<int> eqFrequencies;
  final bool exclusiveMode;

  bool matches(_PlaybackConfiguration other) =>
      pitch == other.pitch &&
      rate == other.rate &&
      exclusiveMode == other.exclusiveMode &&
      listEquals(eqGains, other.eqGains) &&
      listEquals(eqFrequencies, other.eqFrequencies);
}

// class FakePlayerStream implements PlayerStream {
//   @override
//   Stream<Duration> get position => const Stream<Duration>.empty();

//   @override
//   Stream<bool> get playing => const Stream<bool>.empty();

//   @override
//   Stream<Duration> get duration => const Stream<Duration>.empty();

//   @override
//   Stream<bool> get completed => const Stream<bool>.empty();

//   @override
//   Stream<MediaSessionCommand> get mediaSessionCommands =>
//       const Stream<MediaSessionCommand>.empty();

//   @override
//   Stream<MpvPlayerError> get error => const Stream<MpvPlayerError>.empty();

//   @override
//   Stream<List<Device>> get audioDevices => Stream<List<Device>>.value(const []);

//   @override
//   Stream<Device> get audioDevice =>
//       Stream<Device>.value(const Device(name: 'auto', description: 'Auto'));

//   @override
//   dynamic noSuchMethod(Invocation invocation) {
//     return const Stream<dynamic>.empty();
//   }
// }

// class FakePlayer implements Player {
//   final _stream = FakePlayerStream();
//   final _state = const PlayerState();

//   @override
//   PlayerStream get stream => _stream;

//   @override
//   PlayerState get state => _state;

//   @override
//   dynamic noSuchMethod(Invocation invocation) {
//     if (invocation.isMethod) {
//       return Future<void>.value();
//     }
//     return null;
//   }
// }

class AudioService {
  final Player _player;
  late final Future<void> _initialization;
  bool _disposed = false;
  int _trackLoadRevision = 0;
  _PlaybackConfiguration? _desiredConfiguration;
  _PlaybackConfiguration? _appliedConfiguration;
  Future<void>? _configurationDrain;

  Player get player => _player;

  AudioService()
    : _player = Player(
        // configuration: const PlayerConfiguration(autoPlay: false),
        // Wait, default autoPlay is false anyway.
        configuration: const PlayerConfiguration(),
      ) {
    _initialization = _initialize();
  }

  Future<void> init() => _initialization;

  Future<void> _initialize() async {
    // Apply every option independently. One unsupported option must not prevent
    // the remaining Android stability settings from being installed.
    await _bestEffort(
      () => _player.setAudioClientName('Myune music for Android'),
    );
    if (Platform.isAndroid) {
      // Keep enough decoded audio queued to absorb activity switches,
      // scheduler jitter and short Doze transitions without audible gaps.
      await _bestEffort(
        () => _player.setAudioBuffer(const Duration(milliseconds: 500)),
      );
    }
    await _bestEffort(() => _player.setRawProperty('sub-auto', 'no'));
  }

  Future<void> _bestEffort(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (_) {
      // Optional player properties vary between platforms and mpv builds.
    }
  }

  Future<void> _ensureReady() async {
    await _initialization;
    if (_disposed) {
      throw StateError('AudioService has already been disposed.');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _initialization;
    try {
      await _player.stop();
    } finally {
      await _player.dispose();
    }
  }

  Future<void> playSong(
    String filePath, {
    required double pitch,
    required double rate,
    required List<double> eqGains,
    required List<int> eqFrequencies,
    bool exclusiveMode = false,
    bool play = true,
  }) async {
    final revision = ++_trackLoadRevision;
    await _ensureReady();
    await _ensurePlaybackConfiguration(
      _PlaybackConfiguration(
        pitch: pitch,
        rate: rate,
        eqGains: List<double>.unmodifiable(eqGains),
        eqFrequencies: List<int>.unmodifiable(eqFrequencies),
        exclusiveMode: exclusiveMode,
      ),
    );
    if (revision != _trackLoadRevision) return;
    await _player.open(Media(filePath), play: play);
  }

  // 启用无缝播放模式：设置 Gapless.yes + 开启 prefetch
  Future<void> enableGapless() async {
    await _ensureReady();
    try {
      await _player.setGapless(Gapless.yes);
      await _player.setPrefetchPlaylist(true);
    } catch (e) {
      //
    }
  }

  // 关闭无缝播放模式：恢复默认 Gapless.weak + 关闭 prefetch
  Future<void> disableGapless() async {
    await _ensureReady();
    try {
      await _player.setGapless(Gapless.weak);
      await _player.setPrefetchPlaylist(false);
    } catch (e) {
      //
    }
  }

  // 使用 2-track playlist 播放，启用 mpv 无缝过渡
  Future<void> playSongGapless(
    String currentPath, {
    String? nextPath,
    required double pitch,
    required double rate,
    required List<double> eqGains,
    required List<int> eqFrequencies,
    bool exclusiveMode = false,
    bool play = true,
  }) async {
    final revision = ++_trackLoadRevision;
    await _ensureReady();
    await _ensurePlaybackConfiguration(
      _PlaybackConfiguration(
        pitch: pitch,
        rate: rate,
        eqGains: List<double>.unmodifiable(eqGains),
        eqFrequencies: List<int>.unmodifiable(eqFrequencies),
        exclusiveMode: exclusiveMode,
      ),
    );
    if (revision != _trackLoadRevision) return;

    final tracks = [Media(currentPath)];
    if (nextPath != null) {
      tracks.add(Media(nextPath));
    }
    await _player.openAll(tracks, play: play);
  }

  Future<void> _ensurePlaybackConfiguration(
    _PlaybackConfiguration configuration,
  ) async {
    _desiredConfiguration = configuration;
    final existingDrain = _configurationDrain;
    if (existingDrain != null) {
      await existingDrain;
      return;
    }

    final drain = _drainPlaybackConfiguration();
    _configurationDrain = drain;
    try {
      await drain;
    } finally {
      if (identical(_configurationDrain, drain)) {
        _configurationDrain = null;
      }
    }
  }

  Future<void> _drainPlaybackConfiguration() async {
    while (!_disposed) {
      final target = _desiredConfiguration;
      if (target == null) return;
      final applied = _appliedConfiguration;
      if (applied != null && applied.matches(target)) return;

      if (applied == null || applied.exclusiveMode != target.exclusiveMode) {
        try {
          await _player.setAudioExclusive(target.exclusiveMode);
        } catch (_) {
          // Optional on platforms/backends that do not expose exclusivity.
        }
      }
      if (applied == null || applied.pitch != target.pitch) {
        await _player.setPitch(target.pitch);
      }
      if (applied == null || applied.rate != target.rate) {
        await _player.setRate(target.rate);
      }
      if (applied == null ||
          !listEquals(applied.eqGains, target.eqGains) ||
          !listEquals(applied.eqFrequencies, target.eqFrequencies)) {
        await _applyEqualizerToPlayer(
          gains: target.eqGains,
          frequencies: target.eqFrequencies,
        );
      }
      _appliedConfiguration = target;
      if (identical(target, _desiredConfiguration)) return;
    }
  }

  // 替换 mpv playlist 中的预备项（index 1）
  Future<void> replaceNext(String? nextPath) async {
    await _ensureReady();
    try {
      // 先移除旧的预备项（如果有）
      final playlist = _player.state.playlist;
      if (playlist.items.length > 1) {
        await _player.remove(1);
      }
      // 追加新的预备项
      if (nextPath != null) {
        await _player.add(Media(nextPath));
      }
    } catch (e) {
      //
    }
  }

  // 移除 mpv playlist 中已播完的首项，使当前播放回到 index 0
  Future<void> removeFirst() async {
    await _ensureReady();
    try {
      await _player.remove(0);
    } catch (e) {
      //
    }
  }

  Future<void> stop() async {
    await _ensureReady();
    await _player.stop();
  }

  Future<void> pause() async {
    await _ensureReady();
    await _player.pause();
  }

  Future<void> play() async {
    await _ensureReady();
    await _player.play();
  }

  Future<void> seek(Duration position) async {
    await _ensureReady();
    await _player.seek(position);
  }

  Future<void> setVolume(double volume) async {
    await _ensureReady();
    await _player.setVolume(volume);
  }

  Future<void> setPitch(double pitch) async {
    await _ensureReady();
    await _player.setPitch(pitch);
    _appliedConfiguration = null;
  }

  Future<void> setRate(double rate) async {
    await _ensureReady();
    await _player.setRate(rate);
    _appliedConfiguration = null;
  }

  bool _isEqualizerFlat(List<double> gains) {
    return gains.every((gain) => gain.abs() < 0.05);
  }

  Future<void> applyEqualizer({
    required List<double> gains,
    required List<int> frequencies,
  }) async {
    await _ensureReady();
    await _applyEqualizerToPlayer(gains: gains, frequencies: frequencies);
    _appliedConfiguration = null;
  }

  Future<void> _applyEqualizerToPlayer({
    required List<double> gains,
    required List<int> frequencies,
  }) async {
    if (_isEqualizerFlat(gains)) {
      // 只清除均衡器自定义滤镜，保留用户启用的其它音效。
      await _player.updateAudioEffects(
        (effects) => effects.copyWith(custom: []),
      );
      return;
    }

    final filters = <String>[];
    for (var i = 0; i < frequencies.length; i++) {
      filters.add(
        'equalizer=f=${frequencies[i]}:t=q:w=1:g=${gains[i].toStringAsFixed(1)}',
      );
    }

    await _player.updateAudioEffects(
      (e) => e.copyWith(custom: ['lavfi=[${filters.join(',')}]']),
    );
  }
}
