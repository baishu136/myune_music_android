import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../page/playlist/playlist_content_notifier.dart';
import '../page/playlist/playlist_models.dart';
import '../page/setting/settings_provider.dart';
import 'font_service.dart';
import '../theme/theme_provider.dart';

class DesktopLyricsController extends ChangeNotifier {
  static const MethodChannel _channel = MethodChannel(
    'com.myune.music/desktop_lyrics',
  );

  SettingsProvider? _settings;
  ThemeProvider? _theme;
  PlaylistContentNotifier? _playlist;
  StreamSubscription<Duration>? _positionSubscription;
  Timer? _songSwitchSyncTimer;
  StreamSubscription<dynamic>? _mediaCommandSubscription;
  Duration _position = Duration.zero;
  bool _initialized = false;
  bool _pendingEnable = false;
  bool _overlayShown = false;
  String? _lastPayloadKey;
  String? _observedSongPath;
  List<LyricLine>? _observedLyrics;
  int _observedLyricsLength = -1;
  bool? _observedPlaying;
  int _lastLyricIndex = -2;
  bool _syncRunning = false;
  bool _syncRequested = false;
  bool _forceSyncRequested = false;
  String? _pendingSongSwitchPath;
  String? _observedFontFamily;
  String? _resolvedFontFamily;
  String? _resolvedFontPath;
  int _resolvedFontCollectionIndex = 0;

  bool get isSupported => Platform.isAndroid;
  bool get enabled => _settings?.desktopLyricsEnabled ?? false;
  bool get locked => _settings?.desktopLyricsLocked ?? false;
  double get fontSize => _settings?.desktopLyricsFontSize ?? 22.0;
  int get color => _settings?.desktopLyricsColor ?? 0xFF00A9D6;
  bool get outlineEnabled => _settings?.desktopLyricsOutlineEnabled ?? false;
  double get outlineWidth => _settings?.desktopLyricsOutlineWidth ?? 1.15;
  int get outlineColor => _settings?.desktopLyricsOutlineColor ?? 0xFFFFFFFF;
  double get outlineOpacity => _settings?.desktopLyricsOutlineOpacity ?? 1.0;

  Future<bool> hasOverlayPermission() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('hasPermission') ?? false;
  }

  Future<void> requestOverlayPermissionOnly() async {
    if (!isSupported || await hasOverlayPermission()) return;
    await _channel.invokeMethod<void>('requestPermission', {
      'enableOnGrant': false,
    });
  }

  void updateDependencies(
    SettingsProvider settings,
    ThemeProvider theme,
    PlaylistContentNotifier playlist,
  ) {
    if (identical(_settings, settings) &&
        identical(_theme, theme) &&
        identical(_playlist, playlist)) {
      return;
    }
    _settings?.removeListener(_onSettingsChanged);
    _theme?.removeListener(_onThemeChanged);
    _playlist?.removeListener(_onPlaylistChanged);
    _settings = settings;
    _theme = theme;
    _observedFontFamily = theme.currentFontFamily;
    _playlist = playlist;
    settings.addListener(_onSettingsChanged);
    theme.addListener(_onThemeChanged);
    playlist.addListener(_onPlaylistChanged);
    if (!_initialized) {
      _initialized = true;
      _channel.setMethodCallHandler(_handleNativeCall);
      unawaited(_initialize());
    }
  }

  Future<void> _initialize() async {
    if (!isSupported) return;
    // Attach before awaiting preferences/permission. Media-session commands
    // are transient broadcast events; subscribing afterwards can silently
    // lose an early notification-button press during application startup.
    _mediaCommandSubscription ??= _playlist
        ?.mediaPlayer
        .stream
        .mediaSessionCommands
        .listen((command) {
          if (command is MediaSessionCommandDesktopLyrics) {
            unawaited(cycleNotificationState());
          }
        });
    await _settings?.initializationFuture;
    if (enabled) {
      final granted =
          await _channel.invokeMethod<bool>('hasPermission') ?? false;
      if (granted) {
        _startPositionUpdates();
        await _sync(force: true);
      } else {
        await _settings?.setDesktopLyricsEnabled(false);
      }
    }
    notifyListeners();
  }

  Future<bool> setEnabled(bool value) async {
    if (!isSupported) return false;
    if (!value) {
      _pendingEnable = false;
      _songSwitchSyncTimer?.cancel();
      _songSwitchSyncTimer = null;
      _pendingSongSwitchPath = null;
      _positionSubscription?.cancel();
      _positionSubscription = null;
      _overlayShown = false;
      _lastPayloadKey = null;
      await _settings?.setDesktopLyricsEnabled(false);
      await _settings?.setDesktopLyricsLocked(false);
      await _channel.invokeMethod<void>('hide');
      await _refreshNotification();
      notifyListeners();
      return true;
    }

    final granted = await hasOverlayPermission();
    if (!granted) {
      _pendingEnable = true;
      await _channel.invokeMethod<void>('requestPermission', {
        'enableOnGrant': true,
      });
      return false;
    }
    await _completeEnable();
    return true;
  }

  Future<void> _completeEnable() async {
    _pendingEnable = false;
    await _settings?.setDesktopLyricsEnabled(true);
    _startPositionUpdates();
    await _sync(force: true);
    await _refreshNotification();
    notifyListeners();
  }

  Future<void> setLocked(bool value) async {
    if (!enabled) return;
    await _settings?.setDesktopLyricsLocked(value);
    await _channel.invokeMethod<void>('setLocked', {'locked': value});
    await _sync(force: true);
    await _refreshNotification();
    notifyListeners();
  }

  Future<void> setColor(int value) async {
    await _settings?.setDesktopLyricsColor(value);
    await _sync(force: true);
  }

  Future<void> setFontSize(double value) async {
    await _settings?.setDesktopLyricsFontSize(value);
    await _sync(force: true);
  }

  Future<void> setOutlineEnabled(bool value) async {
    await _settings?.setDesktopLyricsOutlineEnabled(value);
    await _sync(force: true);
  }

  Future<void> setOutlineWidth(double value) async {
    await _settings?.setDesktopLyricsOutlineWidth(value);
    await _sync(force: true);
  }

  Future<void> setOutlineColor(int value) async {
    await _settings?.setDesktopLyricsOutlineColor(value);
    await _sync(force: true);
  }

  Future<void> setOutlineOpacity(double value) async {
    await _settings?.setDesktopLyricsOutlineOpacity(value);
    await _sync(force: true);
  }

  Future<void> cycleNotificationState() async {
    if (!enabled) {
      await setEnabled(true);
    } else if (locked) {
      await setLocked(false);
    } else {
      await setEnabled(false);
    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'permissionChanged') {
      final arguments = call.arguments;
      final granted = arguments is Map
          ? arguments['granted'] == true
          : arguments == true;
      final enableOnGrant = arguments is Map
          ? arguments['enableOnGrant'] != false
          : true;
      // Native code only sends this callback for a permission request started
      // by this app. Enabling even after a Flutter/Activity recreation avoids
      // losing the user's choice while Android's settings screen is open.
      if (enableOnGrant && granted && (_pendingEnable || !enabled)) {
        await _completeEnable();
      }
      if (enableOnGrant && _pendingEnable && !granted) {
        _pendingEnable = false;
        notifyListeners();
      }
      return;
    }
    if (call.method != 'event' || call.arguments is! Map) return;
    final event = Map<Object?, Object?>.from(call.arguments as Map);
    switch (event['type']) {
      case 'control':
        final playlist = _playlist;
        if (playlist == null) return;
        switch (event['action']) {
          case 'playPause':
            if (playlist.isPlaying) {
              await playlist.pause();
            } else {
              await playlist.play();
            }
            return;
          case 'previous':
            // Keep desktop-lyrics transport behavior aligned with the app's
            // playback page: an explicit previous/next action is a request to
            // switch tracks and start the selected track, even when the old
            // track was paused.
            await playlist.playPrevious(playAfterLoad: true);
            return;
          case 'next':
            await playlist.playNext(playAfterLoad: true);
            return;
        }
      case 'locked':
        await setLocked(event['locked'] == true);
        return;
      case 'style':
        final value = event['color'];
        final size = event['fontSize'];
        if (value is num) await _settings?.setDesktopLyricsColor(value.toInt());
        if (size is num) {
          await _settings?.setDesktopLyricsFontSize(size.toDouble());
        }
        await _sync(force: true);
        return;
      case 'close':
        await setEnabled(false);
        return;
    }
  }

  void _startPositionUpdates() {
    if (!enabled || _positionSubscription != null) return;
    final player = _playlist?.mediaPlayer;
    if (player == null) return;
    _position = player.state.position;
    _positionSubscription = player.stream.position.listen((position) {
      _position = position;
      final lyrics = _playlist?.currentLyrics ?? const <LyricLine>[];
      final index = _currentLyricIndex(lyrics, position);
      if (index != _lastLyricIndex) {
        _lastLyricIndex = index;
        if (_pendingSongSwitchPath != null) return;
        unawaited(_sync());
      }
    });
  }

  void _onSettingsChanged() {
    if (enabled) {
      _startPositionUpdates();
      unawaited(_sync(force: true));
    }
    notifyListeners();
  }

  void _onThemeChanged() {
    final fontFamily = _theme?.currentFontFamily;
    if (fontFamily == _observedFontFamily) return;
    _observedFontFamily = fontFamily;
    if (enabled) unawaited(_sync(force: true));
    notifyListeners();
  }

  void _onPlaylistChanged() {
    if (!enabled) return;
    _startPositionUpdates();
    final playlist = _playlist;
    if (playlist == null) return;
    final songPath = playlist.currentSong?.filePath;
    final lyrics = playlist.currentLyrics;
    final playing = playlist.isPlaying;
    final songChanged = songPath != _observedSongPath;
    final materiallyChanged =
        songPath != _observedSongPath ||
        !identical(lyrics, _observedLyrics) ||
        lyrics.length != _observedLyricsLength ||
        playing != _observedPlaying;
    if (!materiallyChanged) return;
    _observedSongPath = songPath;
    _observedLyrics = lyrics;
    _observedLyricsLength = lyrics.length;
    _observedPlaying = playing;
    _position = playlist.mediaPlayer.state.position;
    _lastLyricIndex = _currentLyricIndex(lyrics, _position);
    if (songChanged) {
      _pendingSongSwitchPath = songPath;
      _songSwitchSyncTimer?.cancel();
      _songSwitchSyncTimer = Timer(const Duration(milliseconds: 280), () {
        if (!enabled || _playlist?.currentSong?.filePath != songPath) return;
        _pendingSongSwitchPath = null;
        unawaited(_sync(force: true));
      });
      return;
    }
    if (_pendingSongSwitchPath == songPath) {
      if (lyrics.isEmpty) return;
      _songSwitchSyncTimer?.cancel();
      _songSwitchSyncTimer = null;
      _pendingSongSwitchPath = null;
    }
    unawaited(_sync());
  }

  Future<void> _sync({bool force = false}) async {
    _syncRequested = true;
    _forceSyncRequested = _forceSyncRequested || force;
    if (_syncRunning) return;
    _syncRunning = true;
    try {
      while (_syncRequested) {
        _syncRequested = false;
        final currentForce = _forceSyncRequested;
        _forceSyncRequested = false;
        await _performSync(force: currentForce);
      }
    } finally {
      _syncRunning = false;
    }
  }

  Future<void> _performSync({required bool force}) async {
    if (!isSupported || !enabled) return;
    final playlist = _playlist;
    final settings = _settings;
    final theme = _theme;
    if (playlist == null || settings == null || theme == null) return;
    final song = playlist.currentSong;
    final lyrics = playlist.currentLyrics;
    final lyricIndex = _currentLyricIndex(lyrics, _position);
    _lastLyricIndex = lyricIndex;
    final lyric = _lyricAt(lyrics, lyricIndex);
    final fontPath = await _resolveFontPath(theme.currentFontFamily);
    final payload = <String, Object?>{
      'title': song?.title ?? 'Myune music for Android',
      'artist': song?.artist ?? '',
      'lyric': lyric,
      'isPlaying': playlist.isPlaying,
      'isLocked': settings.desktopLyricsLocked,
      'color': settings.desktopLyricsColor,
      'fontSize': settings.desktopLyricsFontSize,
      'fontFamily': theme.currentFontFamily,
      'fontPath': fontPath ?? '',
      'fontCollectionIndex': _resolvedFontCollectionIndex,
      'outlineEnabled': settings.desktopLyricsOutlineEnabled,
      'outlineWidth': settings.desktopLyricsOutlineWidth,
      'outlineColor': settings.desktopLyricsOutlineColor,
      'outlineOpacity': settings.desktopLyricsOutlineOpacity,
      // Desktop lyrics deliberately use their own color. App dynamic theme
      // changes must never overwrite a color explicitly chosen by the user.
      'dynamicColor': false,
    };
    final key = payload.entries.map((e) => '${e.key}:${e.value}').join('|');
    if (!force && key == _lastPayloadKey) return;
    _lastPayloadKey = key;
    await _channel.invokeMethod<void>(
      _overlayShown ? 'update' : 'show',
      payload,
    );
    _overlayShown = true;
  }

  int _currentLyricIndex(List<LyricLine> lyrics, Duration position) {
    if (lyrics.isEmpty) return -1;
    var low = 0;
    var high = lyrics.length - 1;
    var index = 0;
    while (low <= high) {
      final middle = (low + high) >> 1;
      if (lyrics[middle].timestamp <= position) {
        index = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return index;
  }

  String _lyricAt(List<LyricLine> lyrics, int index) {
    if (index < 0 || lyrics.isEmpty) return '暂无歌词';
    final text = lyrics[index].texts
        .where((line) => line.trim().isNotEmpty)
        .take(2)
        .join('\n');
    return text.isEmpty ? '♪' : text;
  }

  Future<String?> _resolveFontPath(String fontFamily) async {
    if (_resolvedFontFamily == fontFamily) return _resolvedFontPath;
    _resolvedFontFamily = fontFamily;
    final reference = await FontService().resolveFontFile(fontFamily);
    _resolvedFontPath = reference?.path;
    _resolvedFontCollectionIndex = reference?.collectionIndex ?? 0;
    return _resolvedFontPath;
  }

  Future<void> _refreshNotification() async {
    await _playlist?.refreshDesktopLyricsMediaSession();
  }

  @override
  void dispose() {
    _settings?.removeListener(_onSettingsChanged);
    _theme?.removeListener(_onThemeChanged);
    _playlist?.removeListener(_onPlaylistChanged);
    _positionSubscription?.cancel();
    _songSwitchSyncTimer?.cancel();
    _mediaCommandSubscription?.cancel();
    if (isSupported) unawaited(_channel.invokeMethod<void>('hide'));
    super.dispose();
  }
}
