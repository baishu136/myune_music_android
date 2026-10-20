import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'music_effect_policy.dart';

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
  final PlayerApi _player;
  StreamSubscription<AudioParams>? _sampleRateSubscription;
  Future<void>? _equalizerDrain, _normalizationDrain;
  List<double>? _desiredGains;
  List<int>? _desiredFrequencies;
  bool _smoothEqualizer = false;
  bool _smoothNormalization = true;
  double _desiredNormalization = 0;
  late final Future<void> _initialization;
  bool _disposed = false;
  int _trackLoadRevision = 0;
  int _nextReplacementRevision = 0;
  Future<void> _nextReplacement = Future<void>.value();
  _PlaybackConfiguration? _desiredConfiguration;
  _PlaybackConfiguration? _appliedConfiguration;
  Future<void>? _configurationDrain;

  PlayerApi get player => _player;

  AudioService({PlayerApi? player})
    : _player =
          player ??
          Player(
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
    await _bestEffort(() => _player.setVolumeGain(0));
    _sampleRateSubscription = _player.stream.audioParams.listen((params) {
      final rate = params.sampleRate;
      if (_disposed ||
          rate == null ||
          rate < 8000 ||
          rate > 384000 ||
          rate == _player.musicDsp.rate) {
        return;
      }
      unawaited(
        _player
            .updateMusicDsp((dsp) => dsp.copyWith(sampleRate: rate))
            .catchError((Object error) {
              debugPrint('更新音效采样率失败: $error');
            }),
      );
    });
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
    await _sampleRateSubscription?.cancel();
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
    await _player.open(Media(filePath), play: false);
    if (revision != _trackLoadRevision) return;
    if (play) await _player.play();
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
    if (revision != _trackLoadRevision) return;
    await _player.openAll(tracks, play: false);
    if (revision != _trackLoadRevision) return;
    if (play) await _player.play();
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
    final revision = ++_nextReplacementRevision;
    final trackRevision = _trackLoadRevision;
    await _ensureReady();
    bool needed() =>
        !_disposed &&
        revision == _nextReplacementRevision &&
        trackRevision == _trackLoadRevision;
    final previous = _nextReplacement;
    final task = () async {
      await previous;
      if (!needed()) return;
      try {
        while (_player.state.playlist.items.length > 1) {
          await _player.remove(_player.state.playlist.items.length - 1);
          if (!needed()) return;
        }
        if (nextPath != null) await _player.add(Media(nextPath));
      } catch (_) {
        // A failed optional preload must not interrupt the current song.
      }
    }();
    _nextReplacement = task;
    await task;
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
    final revision = ++_trackLoadRevision;
    await _ensureReady();
    if (revision != _trackLoadRevision) return;
    await _player.stop();
  }

  Future<void> pause() async {
    final revision = ++_trackLoadRevision;
    await _ensureReady();
    if (revision != _trackLoadRevision) return;
    await _player.pause();
  }

  Future<void> play() async {
    final revision = ++_trackLoadRevision;
    await _ensureReady();
    if (revision != _trackLoadRevision) return;
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

  bool _isEqualizerFlat(List<double> gains) =>
      gains.every((g) => g.abs() < .05);

  Future<void> applyEqualizer({
    required List<double> gains,
    required List<int> frequencies,
  }) async {
    await _ensureReady();
    await _queueEqualizer(gains, frequencies, smooth: true);
    _appliedConfiguration = null;
  }

  Future<void> _applyEqualizerToPlayer({
    required List<double> gains,
    required List<int> frequencies,
  }) => _queueEqualizer(gains, frequencies, smooth: false);

  Future<void> _queueEqualizer(
    List<double> gains,
    List<int> frequencies, {
    required bool smooth,
  }) async {
    if (gains.length != frequencies.length ||
        gains.isEmpty ||
        gains.length > 32) {
      throw ArgumentError('EQ band counts must match and be between 1 and 32');
    }
    _desiredGains = List<double>.unmodifiable(
      gains.map((g) => g.isFinite ? g.clamp(-12.0, 12.0) : 0.0),
    );
    _desiredFrequencies = List<int>.unmodifiable(frequencies);
    _smoothEqualizer = smooth;
    final existing = _equalizerDrain;
    if (existing != null) {
      await existing;
      return;
    }
    final drain = _drainEqualizer();
    _equalizerDrain = drain;
    try {
      await drain;
    } finally {
      if (identical(_equalizerDrain, drain)) _equalizerDrain = null;
    }
  }

  Future<void> _drainEqualizer() async {
    while (!_disposed) {
      final target = _desiredGains!, frequencies = _desiredFrequencies!;
      final previous = _player.musicDsp;
      final animate =
          _smoothEqualizer &&
          _player.state.playing &&
          previous.gains.length == target.length &&
          listEquals(previous.frequencies, frequencies);
      final next = animate
          ? [
              for (var i = 0; i < target.length; i++)
                previous.gain(i) +
                    (target[i] - previous.gain(i)).clamp(-1.0, 1.0),
            ]
          : target;
      await _player.updateMusicDsp(
        (dsp) => dsp.copyWith(
          enabled: true,
          gains: List<double>.unmodifiable(next),
          frequencies: frequencies,
          keepAlive:
              animate &&
              (dsp.keepAlive ||
                  !_isEqualizerFlat(next) ||
                  !_isEqualizerFlat(dsp.gains)),
        ),
      );
      if (identical(target, _desiredGains) && listEquals(next, target)) return;
      if (_disposed) return;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> applyEffect(String id, bool enabled, {String? model}) async {
    await _ensureReady();
    if (!_player.musicDsp.enabled) {
      await _player.updateMusicDsp((dsp) => dsp.copyWith(enabled: true));
    }
    // Typed state is retained; the backend places it in the managed float graph.
    await _player.updateAudioEffects(
      (e) => musicEffectPolicy(e, id, enabled, model: model),
    );
  }

  Future<void> setNormalizationGain(double gainDb, {bool smooth = true}) async {
    await _ensureReady();
    _desiredNormalization = gainDb.isFinite ? gainDb.clamp(-24.0, 24.0) : 0;
    _smoothNormalization = smooth;
    final existing = _normalizationDrain;
    if (existing != null) {
      await existing;
      return;
    }
    final drain = _drainNormalization();
    _normalizationDrain = drain;
    try {
      await drain;
    } finally {
      if (identical(_normalizationDrain, drain)) _normalizationDrain = null;
    }
  }

  Future<void> _drainNormalization() async {
    while (!_disposed) {
      final target = _desiredNormalization;
      final previous = _player.musicDsp.outputDb;
      final next = _smoothNormalization && _player.state.playing
          ? previous + (target - previous).clamp(-1.0, 1.0)
          : target;
      await _player.updateMusicDsp(
        (dsp) => dsp.copyWith(enabled: true, normalizationGainDb: next),
      );
      if (target == _desiredNormalization && (next - target).abs() < .00001) {
        return;
      }
      if (_disposed) return;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }
}
