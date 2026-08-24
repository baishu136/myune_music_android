import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

enum PlaybackInitialView { cover, lyrics }

class SettingsProvider with ChangeNotifier {
  static const double defaultLyricFontSize = 20.0;
  static const _enableGlobalHotkeysKey = 'enableGlobalHotkeys';
  static const _playPauseHotKeyKey = 'playPauseHotKey';
  static const _nextTrackHotKeyKey = 'nextTrackHotKey';
  static const _prevTrackHotKeyKey = 'prevTrackHotKey';
  static const _volumeUpHotKeyKey = 'volumeUpHotKey';
  static const _volumeDownHotKeyKey = 'volumeDownHotKey';

  static const _prefsKey = 'maxLinesPerLyric';
  static const _fontSizeKey = 'fontSize';
  static const _lyricAlignmentKey = 'lyricAlignment';
  static const _useBlurBackgroundKey = 'useBlurBackground'; // 模糊背景设置的 key
  static const _useDynamicColorKey = 'useDynamicColor'; // 动态颜色设置的 key
  static const _allowAnyFormatKey = 'allowAnyFormat'; // 允许任何格式设置的 key
  static const _forceSingleLineLyricKey =
      'forceSingleLineLyric'; // 强制单行歌词设置的 key
  static const _showAlbumNameKey = 'showAlbumName'; // 显示专辑名称设置的 key

  static const _enableOnlineLyricsKey = 'enableOnlineLyrics';
  static const _enableLyricTranslationKey = 'enableLyricTranslation';
  static const _enableLyricSourceFallbackKey = 'enableLyricSourceFallback';
  static const _lyricVerticalSpacingKey =
      'lyricVerticalSpacing'; // 歌词垂直间距设置的 key
  static const _primaryLyricSourceKey = 'primaryLyricSource'; // 主要歌词源设置的 key
  static const _secondaryLyricSourceKey =
      'secondaryLyricSource'; // 备用歌词源设置的 key
  static const _addLyricPaddingKey = 'addLyricPadding'; // 歌词上下补位设置的 key
  static const _artistSeparatorsKey = 'artistSeparators'; // 艺术家分隔符设置的 key
  static const _minimizeToTrayKey = 'minimizeToTray'; // 最小化到托盘设置的 key
  static const _enableLyricBlurKey = 'enableLyricBlur'; // 歌词模糊效果设置的 key
  static const _lyricBlurStrengthKey = 'lyricBlurStrength'; // 歌词模糊强度设置的 key
  static const _playbackLyricGlowEnabledKey = 'playbackLyricGlowEnabled';
  static const _playbackLyricGlowRadiusKey = 'playbackLyricGlowRadius';
  static const _playbackInitialViewKey = 'playbackInitialView';
  static const _showTaskbarProgressKey =
      'showTaskbarProgress'; // 任务栏进度显示设置的 key
  static const _hiddenPagesKey = 'hiddenPages'; // 隐藏页面设置的 key
  static const _enableDynamicBackgroundKey =
      'enableDynamicBackground'; // 动态背景设置的 key
  static const _audioDeviceNameKey = 'audio_device_name';
  static const _audioDeviceDescKey = 'audio_device_desc';
  static const _audioDeviceIsAutoKey = 'audio_device_is_auto';
  static const _ignorePlaybackErrorsKey = 'ignorePlaybackErrors';
  static const _preferExternalLyricsKey = 'preferExternalLyrics';
  static const _autoAdjustLyricLayoutKey =
      'autoAdjustLyricLayout'; // 自动调节歌词字体与间距设置的 key

  static const _enableLoudnessKey = 'enableLoudness';
  static const _enableReplayGainKey = 'enableReplayGain';
  static const _enableGaplessPlaybackKey = 'enableGaplessPlayback';
  static const _showAudioAnalysisKey = 'showAudioAnalysis';
  static const _homeThemeImagePathKey = 'homeThemeImagePath';
  static const _playbackThemeImagePathKey = 'playbackThemeImagePath';
  static const _homeThemeImageEnabledKey = 'homeThemeImageEnabled';
  static const _playbackThemeImageEnabledKey = 'playbackThemeImageEnabled';
  static const _homeThemeImageDimKey = 'homeThemeImageDim';
  static const _playbackThemeImageDimKey = 'playbackThemeImageDim';
  static const _homeThemeImageBlurKey = 'homeThemeImageBlur';
  static const _playbackThemeImageBlurKey = 'playbackThemeImageBlur';
  static const _homeAlbumArtBackgroundDimKey = 'homeAlbumArtBackgroundDim';
  static const _playbackAlbumArtBackgroundDimKey =
      'playbackAlbumArtBackgroundDim';
  static const _homeAlbumArtBackgroundBlurKey = 'homeAlbumArtBackgroundBlur';
  static const _playbackAlbumArtBackgroundBlurKey =
      'playbackAlbumArtBackgroundBlur';
  static const _followAlbumArtOnHomeKey = 'followAlbumArtOnHome';
  static const _followAlbumArtOnPlaybackKey = 'followAlbumArtOnPlayback';
  static const _artistGroupGridViewKey = 'artistGroupGridView';
  static const _albumGroupGridViewKey = 'albumGroupGridView';
  static const _artistGroupCoverPathsKey = 'artistGroupCoverPaths';
  static const _albumGroupCoverPathsKey = 'albumGroupCoverPaths';
  static const _desktopLyricsEnabledKey = 'desktopLyricsEnabled';
  static const _desktopLyricsLockedKey = 'desktopLyricsLocked';
  static const _desktopLyricsColorKey = 'desktopLyricsColor';
  static const _desktopLyricsFontSizeKey = 'desktopLyricsFontSize';

  int _maxLinesPerLyric = 2;
  double _fontSize = defaultLyricFontSize;
  TextAlign _lyricAlignment = TextAlign.center; // 默认居中对齐
  bool _useBlurBackground = true; // 默认启用模糊背景
  bool _useDynamicColor = true; // 默认启用动态颜色
  bool _allowAnyFormat = false; // 默认不允许任何格式
  bool _forceSingleLineLyric = false; // 默认不强制单行显示歌词
  double _lyricVerticalSpacing = 6.0; // 默认歌词垂直间距为6.0
  bool _addLyricPadding = true; // 默认启用歌词上下补位
  bool _minimizeToTray = false; // 默认不启用最小化到托盘
  bool _enableLyricBlur = false; // Android 版已移除歌词模糊效果
  double _lyricBlurStrength = 2.5; // 歌词模糊强度，范围 1.0~4.0
  bool _playbackLyricGlowEnabled = false;
  double _playbackLyricGlowRadius = 8.0;
  PlaybackInitialView _playbackInitialView = PlaybackInitialView.cover;
  bool _showAlbumName = false; // 默认不显示专辑名称
  bool _enableDynamicBackground = false; // 默认不启用动态背景
  bool _audioDeviceIsAuto = true; // 默认音频设备为自动
  String? _audioDeviceName; // 音频设备名称
  String? _audioDeviceDesc; // 音频设备描述
  bool _ignorePlaybackErrors = false; // 默认不忽略播放错误
  bool _preferExternalLyrics = false; // 默认不优先读取外置LRC歌词
  bool _autoAdjustLyricLayout = false; // 默认不自动调节歌词布局
  bool _enableLoudness = false;
  bool _enableReplayGain = false;
  bool _enableGaplessPlayback = false; // 默认不启用无缝播放
  bool _showAudioAnalysis = false; // 默认保持播放页底栏简洁

  String? _homeThemeImagePath;
  String? _playbackThemeImagePath;
  bool _homeThemeImageEnabled = false;
  bool _playbackThemeImageEnabled = false;
  double _homeThemeImageDim = 0.62;
  double _playbackThemeImageDim = 0.68;
  double _homeThemeImageBlur = 22.0;
  double _playbackThemeImageBlur = 22.0;
  double _homeAlbumArtBackgroundDim = 0.52;
  double _playbackAlbumArtBackgroundDim = 0.52;
  double _homeAlbumArtBackgroundBlur = 40.0;
  double _playbackAlbumArtBackgroundBlur = 40.0;
  bool _followAlbumArtOnHome = false;
  bool _followAlbumArtOnPlayback = false;
  bool _artistGroupGridView = false;
  bool _albumGroupGridView = false;
  Map<String, String> _artistGroupCoverPaths = {};
  Map<String, String> _albumGroupCoverPaths = {};
  bool _desktopLyricsEnabled = false;
  bool _desktopLyricsLocked = false;
  int _desktopLyricsColor = 0xFF00A9D6;
  double _desktopLyricsFontSize = 22.0;

  bool _enableGlobalHotkeys = true;
  HotKey? _playPauseHotKey;
  HotKey? _nextTrackHotKey;
  HotKey? _prevTrackHotKey;
  HotKey? _volumeUpHotKey;
  HotKey? _volumeDownHotKey;

  bool _showTaskbarProgress = false;
  bool _enableOnlineLyrics = false; // 默认不启用从网络获取歌词
  bool _enableLyricTranslation = true; // 默认显示网络歌词翻译
  bool _enableLyricSourceFallback = false; // 默认仅使用用户选择的歌词源
  String _primaryLyricSource = 'qq'; // 默认主要歌词源为qq音乐
  String _secondaryLyricSource = 'netease'; // 默认备用歌词源为网易云音乐

  // 隐藏页面列表，默认为空（都不隐藏）
  List<String> _hiddenPages = [];

  // 默认艺术家分隔符
  List<String> _artistSeparators = [';', '、', '；', '，', ','];

  int get maxLinesPerLyric => _maxLinesPerLyric;
  double get fontSize => _fontSize;
  TextAlign get lyricAlignment => _lyricAlignment;
  bool get useBlurBackground => _useBlurBackground; // 获取模糊背景设置
  bool get useDynamicColor => _useDynamicColor; // 获取动态颜色设置
  bool get allowAnyFormat => _allowAnyFormat; // 获取允许任何格式设置
  bool get forceSingleLineLyric => _forceSingleLineLyric; // 获取强制单行歌词设置
  double get lyricVerticalSpacing => _lyricVerticalSpacing; // 获取歌词垂直间距
  bool get addLyricPadding => _addLyricPadding; // 获取歌词上下补位设置
  bool get minimizeToTray => _minimizeToTray; // 获取最小化到托盘设置
  bool get enableLyricBlur => _enableLyricBlur; // 获取歌词模糊效果设置
  double get lyricBlurStrength => _lyricBlurStrength; // 获取歌词模糊强度设置
  bool get playbackLyricGlowEnabled => _playbackLyricGlowEnabled;
  double get playbackLyricGlowRadius => _playbackLyricGlowRadius;
  PlaybackInitialView get playbackInitialView => _playbackInitialView;
  bool get showTaskbarProgress => _showTaskbarProgress; // 获取任务栏进度显示设置
  bool get showAlbumName => _showAlbumName; // 获取显示专辑名称设置
  bool get enableDynamicBackground => _enableDynamicBackground; // 获取动态背景设置

  bool get enableOnlineLyrics => _enableOnlineLyrics;
  bool get enableLyricTranslation => _enableLyricTranslation;
  bool get enableLyricSourceFallback => _enableLyricSourceFallback;
  String get primaryLyricSource => _primaryLyricSource; // 获取主要歌词源
  String get secondaryLyricSource => _secondaryLyricSource; // 获取备用歌词源

  List<String> get hiddenPages => _hiddenPages; // 获取隐藏页面列表

  List<String> get artistSeparators => _artistSeparators; // 获取艺术家分隔符

  bool get audioDeviceIsAuto => _audioDeviceIsAuto;
  String? get audioDeviceName => _audioDeviceName;
  String? get audioDeviceDesc => _audioDeviceDesc;
  bool get ignorePlaybackErrors => _ignorePlaybackErrors;

  bool get preferExternalLyrics => _preferExternalLyrics; // 获取优先读取外置LRC歌词设置
  bool get autoAdjustLyricLayout => _autoAdjustLyricLayout; // 获取是否自动调节歌词布局
  // Retained for the legacy desktop lyric widget; Android no longer exposes
  // or enables the experimental elastic scrolling implementation.
  bool get enableLyricElasticScroll => false;
  bool get enableLoudness => _enableLoudness;
  bool get enableReplayGain => _enableReplayGain;
  bool get enableGaplessPlayback => _enableGaplessPlayback;
  bool get showAudioAnalysis => _showAudioAnalysis;
  String? get homeThemeImagePath => _homeThemeImagePath;
  String? get playbackThemeImagePath => _playbackThemeImagePath;
  bool get homeThemeImageEnabled => _homeThemeImageEnabled;
  bool get playbackThemeImageEnabled => _playbackThemeImageEnabled;
  double get homeThemeImageDim => _homeThemeImageDim;
  double get playbackThemeImageDim => _playbackThemeImageDim;
  double get homeThemeImageBlur => _homeThemeImageBlur;
  double get playbackThemeImageBlur => _playbackThemeImageBlur;
  double get homeAlbumArtBackgroundDim => _homeAlbumArtBackgroundDim;
  double get playbackAlbumArtBackgroundDim => _playbackAlbumArtBackgroundDim;
  double get homeAlbumArtBackgroundBlur => _homeAlbumArtBackgroundBlur;
  double get playbackAlbumArtBackgroundBlur => _playbackAlbumArtBackgroundBlur;
  bool get followAlbumArtOnHome => _followAlbumArtOnHome;
  bool get followAlbumArtOnPlayback => _followAlbumArtOnPlayback;
  bool get artistGroupGridView => _artistGroupGridView;
  bool get albumGroupGridView => _albumGroupGridView;
  Map<String, String> get artistGroupCoverPaths =>
      Map.unmodifiable(_artistGroupCoverPaths);
  Map<String, String> get albumGroupCoverPaths =>
      Map.unmodifiable(_albumGroupCoverPaths);
  bool get desktopLyricsEnabled => _desktopLyricsEnabled;
  bool get desktopLyricsLocked => _desktopLyricsLocked;
  int get desktopLyricsColor => _desktopLyricsColor;
  double get desktopLyricsFontSize => _desktopLyricsFontSize;

  bool get enableGlobalHotkeys => _enableGlobalHotkeys;
  HotKey? get playPauseHotKey => _playPauseHotKey;
  HotKey? get nextTrackHotKey => _nextTrackHotKey;
  HotKey? get prevTrackHotKey => _prevTrackHotKey;
  HotKey? get volumeUpHotKey => _volumeUpHotKey;
  HotKey? get volumeDownHotKey => _volumeDownHotKey;

  late final Future<void> initializationFuture;

  SettingsProvider() {
    initializationFuture = _loadFromPrefs();
  }

  T? _readPreference<T>(SharedPreferences prefs, String key) {
    final value = prefs.get(key);
    if (value == null) return null;
    if (value is T) return value as T;
    debugPrint('忽略类型不兼容的设置项 $key：期望 $T，实际 ${value.runtimeType}');
    return null;
  }

  double? _readDoublePreference(SharedPreferences prefs, String key) {
    final value = prefs.get(key);
    if (value == null) return null;
    if (value is num) return value.toDouble();
    debugPrint('忽略类型不兼容的数值设置项 $key：实际 ${value.runtimeType}');
    return null;
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _maxLinesPerLyric = _readPreference<int>(prefs, _prefsKey) ?? 2;
    _fontSize =
        _readDoublePreference(prefs, _fontSizeKey) ?? defaultLyricFontSize;
    _useBlurBackground =
        _readPreference<bool>(prefs, _useBlurBackgroundKey) ?? true;
    _useDynamicColor =
        _readPreference<bool>(prefs, _useDynamicColorKey) ?? true; // 加载动态颜色设置
    _allowAnyFormat =
        _readPreference<bool>(prefs, _allowAnyFormatKey) ?? false; // 加载允许任何格式设置
    _forceSingleLineLyric =
        _readPreference<bool>(prefs, _forceSingleLineLyricKey) ??
        false; // 加载强制单行歌词设置
    _showAlbumName =
        _readPreference<bool>(prefs, _showAlbumNameKey) ?? false; // 加载显示专辑名称设置
    _enableOnlineLyrics =
        _readPreference<bool>(prefs, _enableOnlineLyricsKey) ?? false;
    _enableLyricTranslation =
        _readPreference<bool>(prefs, _enableLyricTranslationKey) ?? true;
    _enableLyricSourceFallback =
        _readPreference<bool>(prefs, _enableLyricSourceFallbackKey) ?? false;
    _lyricVerticalSpacing =
        _readDoublePreference(prefs, _lyricVerticalSpacingKey) ??
        6.0; // 加载歌词垂直间距设置
    _addLyricPadding =
        _readPreference<bool>(prefs, _addLyricPaddingKey) ?? true; // 加载歌词上下补位设置
    _minimizeToTray =
        _readPreference<bool>(prefs, _minimizeToTrayKey) ?? false; // 加载最小化到托盘设置
    _enableLyricBlur = false;
    _lyricBlurStrength =
        _readDoublePreference(prefs, _lyricBlurStrengthKey) ??
        2.5; // 加载歌词模糊强度设置
    _playbackLyricGlowEnabled =
        _readPreference<bool>(prefs, _playbackLyricGlowEnabledKey) ?? false;
    _playbackLyricGlowRadius =
        (_readDoublePreference(prefs, _playbackLyricGlowRadiusKey) ?? 8.0)
            .clamp(2.0, 20.0);
    _playbackInitialView =
        _readPreference<String>(prefs, _playbackInitialViewKey) ==
            PlaybackInitialView.lyrics.name
        ? PlaybackInitialView.lyrics
        : PlaybackInitialView.cover;
    _primaryLyricSource =
        _readPreference<String>(prefs, _primaryLyricSourceKey) ??
        'qq'; // 加载主要歌词源设置
    _secondaryLyricSource =
        _readPreference<String>(prefs, _secondaryLyricSourceKey) ??
        'netease'; // 加载备用歌词源设置
    _showTaskbarProgress =
        _readPreference<bool>(prefs, _showTaskbarProgressKey) ??
        false; // 加载任务栏进度显示设置
    _enableDynamicBackground = false;

    _audioDeviceIsAuto =
        _readPreference<bool>(prefs, _audioDeviceIsAutoKey) ?? true;
    _audioDeviceName = _readPreference<String>(prefs, _audioDeviceNameKey);
    _audioDeviceDesc = _readPreference<String>(prefs, _audioDeviceDescKey);
    _ignorePlaybackErrors =
        _readPreference<bool>(prefs, _ignorePlaybackErrorsKey) ?? false;
    _preferExternalLyrics =
        _readPreference<bool>(prefs, _preferExternalLyricsKey) ?? false;
    _autoAdjustLyricLayout = false;
    await prefs.remove(_enableLyricBlurKey);
    await prefs.remove(_enableDynamicBackgroundKey);
    await prefs.remove(_autoAdjustLyricLayoutKey);
    await prefs.remove('enableLyricElasticScroll');
    _enableLoudness = _readPreference<bool>(prefs, _enableLoudnessKey) ?? false;
    _enableReplayGain =
        _readPreference<bool>(prefs, _enableReplayGainKey) ?? false;
    _enableGaplessPlayback =
        _readPreference<bool>(prefs, _enableGaplessPlaybackKey) ?? false;
    _showAudioAnalysis =
        _readPreference<bool>(prefs, _showAudioAnalysisKey) ?? false;
    _homeThemeImagePath = _readPreference<String>(
      prefs,
      _homeThemeImagePathKey,
    );
    _playbackThemeImagePath = _readPreference<String>(
      prefs,
      _playbackThemeImagePathKey,
    );
    _homeThemeImageEnabled =
        _readPreference<bool>(prefs, _homeThemeImageEnabledKey) ?? false;
    _playbackThemeImageEnabled =
        _readPreference<bool>(prefs, _playbackThemeImageEnabledKey) ?? false;
    if (_playbackThemeImageEnabled) {
      final path = _playbackThemeImagePath;
      _playbackThemeImageEnabled =
          path != null && path.isNotEmpty && await File(path).exists();
      if (!_playbackThemeImageEnabled) {
        await prefs.setBool(_playbackThemeImageEnabledKey, false);
      }
    }
    final removedNotificationThemePath = _readPreference<String>(
      prefs,
      'notificationThemeImagePath',
    );
    if (removedNotificationThemePath != null &&
        removedNotificationThemePath.isNotEmpty) {
      try {
        final removedFile = File(removedNotificationThemePath);
        if (await removedFile.exists()) await removedFile.delete();
      } catch (_) {
        // The removed feature must not block settings initialization.
      }
    }
    await prefs.remove('notificationThemeImagePath');
    await prefs.remove('notificationThemeImageEnabled');
    _homeThemeImageDim =
        (_readDoublePreference(prefs, _homeThemeImageDimKey) ?? 0.62).clamp(
          0.2,
          0.9,
        );
    _playbackThemeImageDim =
        (_readDoublePreference(prefs, _playbackThemeImageDimKey) ?? 0.68).clamp(
          0.2,
          0.9,
        );
    _homeThemeImageBlur =
        (_readDoublePreference(prefs, _homeThemeImageBlurKey) ?? 22.0).clamp(
          0.0,
          40.0,
        );
    _playbackThemeImageBlur =
        (_readDoublePreference(prefs, _playbackThemeImageBlurKey) ?? 22.0)
            .clamp(0.0, 40.0);
    _homeAlbumArtBackgroundDim =
        (_readDoublePreference(prefs, _homeAlbumArtBackgroundDimKey) ?? 0.52)
            .clamp(0.2, 0.9);
    _playbackAlbumArtBackgroundDim =
        (_readDoublePreference(prefs, _playbackAlbumArtBackgroundDimKey) ??
                0.52)
            .clamp(0.2, 0.9);
    _homeAlbumArtBackgroundBlur =
        (_readDoublePreference(prefs, _homeAlbumArtBackgroundBlurKey) ?? 40.0)
            .clamp(0.0, 40.0);
    _playbackAlbumArtBackgroundBlur =
        (_readDoublePreference(prefs, _playbackAlbumArtBackgroundBlurKey) ??
                40.0)
            .clamp(0.0, 40.0);
    _followAlbumArtOnHome =
        _readPreference<bool>(prefs, _followAlbumArtOnHomeKey) ?? false;
    _followAlbumArtOnPlayback =
        _readPreference<bool>(prefs, _followAlbumArtOnPlaybackKey) ?? false;
    _artistGroupGridView =
        _readPreference<bool>(prefs, _artistGroupGridViewKey) ?? false;
    _albumGroupGridView =
        _readPreference<bool>(prefs, _albumGroupGridViewKey) ?? false;
    _artistGroupCoverPaths = _decodeStringMap(
      _readPreference<String>(prefs, _artistGroupCoverPathsKey),
    );
    _albumGroupCoverPaths = _decodeStringMap(
      _readPreference<String>(prefs, _albumGroupCoverPathsKey),
    );
    _desktopLyricsEnabled =
        _readPreference<bool>(prefs, _desktopLyricsEnabledKey) ?? false;
    _desktopLyricsLocked =
        _readPreference<bool>(prefs, _desktopLyricsLockedKey) ?? false;
    _desktopLyricsColor =
        _readPreference<int>(prefs, _desktopLyricsColorKey) ?? 0xFF00A9D6;
    _desktopLyricsFontSize =
        _readDoublePreference(prefs, _desktopLyricsFontSizeKey) ?? 22.0;
    if (_enableLoudness && _enableReplayGain) {
      _enableReplayGain = false;
      await prefs.setBool(_enableReplayGainKey, false);
    }

    // 加载隐藏页面设置
    final hiddenPagesList = _readPreference<List<String>>(
      prefs,
      _hiddenPagesKey,
    );
    if (hiddenPagesList != null) {
      _hiddenPages = hiddenPagesList;
    }

    // 加载艺术家分隔符设置
    final separatorsList = _readPreference<List<String>>(
      prefs,
      _artistSeparatorsKey,
    );
    if (separatorsList != null && separatorsList.isNotEmpty) {
      _artistSeparators = separatorsList;
    }

    final alignmentString = _readPreference<String>(prefs, _lyricAlignmentKey);
    _lyricAlignment = alignmentString != null
        ? TextAlign.values.firstWhere(
            (e) => e.toString() == alignmentString,
            orElse: () => TextAlign.center,
          )
        : TextAlign.center;

    _enableGlobalHotkeys =
        _readPreference<bool>(prefs, _enableGlobalHotkeysKey) ?? true;
    _playPauseHotKey = _parseHotKey(
      _readPreference<String>(prefs, _playPauseHotKeyKey),
      'play_pause',
    );
    _nextTrackHotKey = _parseHotKey(
      _readPreference<String>(prefs, _nextTrackHotKeyKey),
      'next_track',
    );
    _prevTrackHotKey = _parseHotKey(
      _readPreference<String>(prefs, _prevTrackHotKeyKey),
      'prev_track',
    );
    _volumeUpHotKey = _parseHotKey(
      _readPreference<String>(prefs, _volumeUpHotKeyKey),
      'volume_up',
    );
    _volumeDownHotKey = _parseHotKey(
      _readPreference<String>(prefs, _volumeDownHotKeyKey),
      'volume_down',
    );

    notifyListeners(); // 读取完毕后刷新界面
  }

  void setMaxLinesPerLyric(int value) async {
    _maxLinesPerLyric = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, value);
  }

  void setFontSize(double size) async {
    previewFontSize(size);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, _fontSize);
  }

  /// 更新歌词字号但暂不写入磁盘，供连续缩放手势预览使用。
  void previewFontSize(double size) {
    final next = size.clamp(12.0, 32.0);
    if ((_fontSize - next).abs() < 0.01) return;
    _fontSize = next;
    notifyListeners();
  }

  void setLyricAlignment(TextAlign alignment) async {
    _lyricAlignment = alignment;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lyricAlignmentKey, alignment.toString());
  }

  void setUseBlurBackground(bool value) async {
    _useBlurBackground = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useBlurBackgroundKey, value);
  }

  Future<void> setUseDynamicColor(bool value) async {
    if (_useDynamicColor != value) {
      _useDynamicColor = value;
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_useDynamicColorKey, value);
    }
  }

  void setEnableOnlineLyrics(bool value) async {
    _enableOnlineLyrics = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableOnlineLyricsKey, value);
  }

  Future<void> setEnableLyricTranslation(bool value) async {
    if (_enableLyricTranslation == value) return;
    _enableLyricTranslation = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableLyricTranslationKey, value);
  }

  Future<void> setEnableLyricSourceFallback(bool value) async {
    if (_enableLyricSourceFallback == value) return;
    _enableLyricSourceFallback = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableLyricSourceFallbackKey, value);
  }

  void setLyricVerticalSpacing(double value) async {
    _lyricVerticalSpacing = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_lyricVerticalSpacingKey, value);
  }

  void setPrimaryLyricSource(String value) async {
    _primaryLyricSource = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_primaryLyricSourceKey, value);
  }

  void setSecondaryLyricSource(String value) async {
    _secondaryLyricSource = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_secondaryLyricSourceKey, value);
  }

  void setAllowAnyFormat(bool value) async {
    _allowAnyFormat = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_allowAnyFormatKey, value);
  }

  void setForceSingleLineLyric(bool value) async {
    _forceSingleLineLyric = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_forceSingleLineLyricKey, value);
  }

  void setAddLyricPadding(bool value) async {
    _addLyricPadding = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_addLyricPaddingKey, value);
  }

  void setAutoAdjustLyricLayout(bool value) async {
    _autoAdjustLyricLayout = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoAdjustLyricLayoutKey, value);
  }

  void setArtistSeparators(List<String> separators) async {
    _artistSeparators = separators;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    // 使用字符串列表而不是用逗号连接的字符串，避免与分隔符冲突
    await prefs.setStringList(_artistSeparatorsKey, separators);
  }

  void setMinimizeToTray(bool value) async {
    _minimizeToTray = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_minimizeToTrayKey, value);
  }

  void setEnableLyricBlur(bool value) async {
    _enableLyricBlur = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableLyricBlurKey, value);
  }

  void setLyricBlurStrength(double value) async {
    final clampedValue = value.clamp(1.0, 4.0);
    if (_lyricBlurStrength == clampedValue) return;

    _lyricBlurStrength = clampedValue;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_lyricBlurStrengthKey, clampedValue);
  }

  void setShowTaskbarProgress(bool value) async {
    _showTaskbarProgress = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showTaskbarProgressKey, value);
  }

  void setShowAlbumName(bool value) async {
    _showAlbumName = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showAlbumNameKey, value);
  }

  void setHiddenPages(List<String> hiddenPages) async {
    // 确保歌单和设置不会被隐藏
    final filteredHiddenPages = hiddenPages
        .where((page) => page != '歌单' && page != '设置')
        .toList();

    _hiddenPages = filteredHiddenPages;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_hiddenPagesKey, filteredHiddenPages);
  }

  void setEnableDynamicBackground(bool value) async {
    _enableDynamicBackground = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableDynamicBackgroundKey, value);
  }

  void setAudioDevice(String name, String desc) async {
    _audioDeviceIsAuto = false;
    _audioDeviceName = name;
    _audioDeviceDesc = desc;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_audioDeviceIsAutoKey, false);
    await prefs.setString(_audioDeviceNameKey, name);
    await prefs.setString(_audioDeviceDescKey, desc);
  }

  void setAudioDeviceToAuto() async {
    _audioDeviceIsAuto = true;
    _audioDeviceName = null;
    _audioDeviceDesc = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_audioDeviceIsAutoKey, true);
    await prefs.remove(_audioDeviceNameKey);
    await prefs.remove(_audioDeviceDescKey);
  }

  void setIgnorePlaybackErrors(bool value) async {
    _ignorePlaybackErrors = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ignorePlaybackErrorsKey, value);
  }

  void setPreferExternalLyrics(bool value) async {
    _preferExternalLyrics = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_preferExternalLyricsKey, value);
  }

  void setEnableLoudness(bool value) async {
    _enableLoudness = value;
    if (value) {
      _enableReplayGain = false;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableLoudnessKey, value);
    if (value) {
      await prefs.setBool(_enableReplayGainKey, false);
    }
  }

  void setEnableReplayGain(bool value) async {
    _enableReplayGain = value;
    if (value) {
      _enableLoudness = false;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableReplayGainKey, value);
    if (value) {
      await prefs.setBool(_enableLoudnessKey, false);
    }
  }

  void setEnableGaplessPlayback(bool value) async {
    _enableGaplessPlayback = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableGaplessPlaybackKey, value);
  }

  void setShowAudioAnalysis(bool value) async {
    _showAudioAnalysis = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showAudioAnalysisKey, value);
  }

  Future<void> setHomeThemeImage(String? path, {bool? enabled}) async {
    _homeThemeImagePath = path;
    _homeThemeImageEnabled = enabled ?? (path != null && path.isNotEmpty);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.isEmpty) {
      await prefs.remove(_homeThemeImagePathKey);
    } else {
      await prefs.setString(_homeThemeImagePathKey, path);
    }
    await prefs.setBool(_homeThemeImageEnabledKey, _homeThemeImageEnabled);
  }

  Future<void> setPlaybackThemeImage(String? path, {bool? enabled}) async {
    _playbackThemeImagePath = path;
    _playbackThemeImageEnabled = enabled ?? (path != null && path.isNotEmpty);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.isEmpty) {
      await prefs.remove(_playbackThemeImagePathKey);
    } else {
      await prefs.setString(_playbackThemeImagePathKey, path);
    }
    await prefs.setBool(
      _playbackThemeImageEnabledKey,
      _playbackThemeImageEnabled,
    );
  }

  Future<void> setHomeThemeImageEnabled(bool value) async {
    _homeThemeImageEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_homeThemeImageEnabledKey, value);
  }

  Future<void> setPlaybackThemeImageEnabled(bool value) async {
    _playbackThemeImageEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_playbackThemeImageEnabledKey, value);
  }

  Future<void> setHomeThemeImageDim(double value) async {
    _homeThemeImageDim = value.clamp(0.2, 0.9);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_homeThemeImageDimKey, _homeThemeImageDim);
  }

  Future<void> setPlaybackThemeImageDim(double value) async {
    _playbackThemeImageDim = value.clamp(0.2, 0.9);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_playbackThemeImageDimKey, _playbackThemeImageDim);
  }

  Future<void> setHomeThemeImageBlur(double value) async {
    _homeThemeImageBlur = value.clamp(0.0, 40.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_homeThemeImageBlurKey, _homeThemeImageBlur);
  }

  Future<void> setPlaybackThemeImageBlur(double value) async {
    _playbackThemeImageBlur = value.clamp(0.0, 40.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_playbackThemeImageBlurKey, _playbackThemeImageBlur);
  }

  Future<void> setPlaybackLyricGlowEnabled(bool value) async {
    if (_playbackLyricGlowEnabled == value) return;
    _playbackLyricGlowEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_playbackLyricGlowEnabledKey, value);
  }

  Future<void> setPlaybackLyricGlowRadius(double value) async {
    final next = value.clamp(2.0, 20.0);
    if ((_playbackLyricGlowRadius - next).abs() < 0.01) return;
    _playbackLyricGlowRadius = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      _playbackLyricGlowRadiusKey,
      _playbackLyricGlowRadius,
    );
  }

  Future<void> setPlaybackInitialView(PlaybackInitialView value) async {
    if (_playbackInitialView == value) return;
    _playbackInitialView = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playbackInitialViewKey, value.name);
  }

  Future<void> setHomeAlbumArtBackgroundDim(double value) async {
    _homeAlbumArtBackgroundDim = value.clamp(0.2, 0.9);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      _homeAlbumArtBackgroundDimKey,
      _homeAlbumArtBackgroundDim,
    );
  }

  Future<void> setPlaybackAlbumArtBackgroundDim(double value) async {
    _playbackAlbumArtBackgroundDim = value.clamp(0.2, 0.9);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      _playbackAlbumArtBackgroundDimKey,
      _playbackAlbumArtBackgroundDim,
    );
  }

  Future<void> setHomeAlbumArtBackgroundBlur(double value) async {
    _homeAlbumArtBackgroundBlur = value.clamp(0.0, 40.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      _homeAlbumArtBackgroundBlurKey,
      _homeAlbumArtBackgroundBlur,
    );
  }

  Future<void> setPlaybackAlbumArtBackgroundBlur(double value) async {
    _playbackAlbumArtBackgroundBlur = value.clamp(0.0, 40.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      _playbackAlbumArtBackgroundBlurKey,
      _playbackAlbumArtBackgroundBlur,
    );
  }

  Future<void> setFollowAlbumArtOnHome(bool value) async {
    if (_followAlbumArtOnHome == value) return;
    _followAlbumArtOnHome = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_followAlbumArtOnHomeKey, value);
  }

  Future<void> setFollowAlbumArtOnPlayback(bool value) async {
    if (_followAlbumArtOnPlayback == value) return;
    _followAlbumArtOnPlayback = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_followAlbumArtOnPlaybackKey, value);
  }

  Future<void> setArtistGroupGridView(bool value) async {
    if (_artistGroupGridView == value) return;
    _artistGroupGridView = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_artistGroupGridViewKey, value);
  }

  Future<void> setAlbumGroupGridView(bool value) async {
    if (_albumGroupGridView == value) return;
    _albumGroupGridView = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_albumGroupGridViewKey, value);
  }

  Future<void> setGroupCoverPath({
    required bool artist,
    required String group,
    String? songPath,
  }) async {
    final values = artist
        ? Map<String, String>.from(_artistGroupCoverPaths)
        : Map<String, String>.from(_albumGroupCoverPaths);
    if (songPath == null || songPath.isEmpty) {
      values.remove(group);
    } else {
      values[group] = songPath;
    }
    if (artist) {
      _artistGroupCoverPaths = values;
    } else {
      _albumGroupCoverPaths = values;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      artist ? _artistGroupCoverPathsKey : _albumGroupCoverPathsKey,
      jsonEncode(values),
    );
  }

  static Map<String, String> _decodeStringMap(String? source) {
    if (source == null || source.isEmpty) return {};
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) return {};
      return decoded.map(
        (key, value) => MapEntry(key, value is String ? value : ''),
      )..removeWhere((key, value) => value.isEmpty);
    } catch (_) {
      return {};
    }
  }

  Future<void> setDesktopLyricsEnabled(bool value) async {
    if (_desktopLyricsEnabled == value) return;
    _desktopLyricsEnabled = value;
    if (!value) _desktopLyricsLocked = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_desktopLyricsEnabledKey, value);
    if (!value) await prefs.setBool(_desktopLyricsLockedKey, false);
  }

  Future<void> setDesktopLyricsLocked(bool value) async {
    if (_desktopLyricsLocked == value) return;
    _desktopLyricsLocked = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_desktopLyricsLockedKey, value);
  }

  Future<void> setDesktopLyricsColor(int value) async {
    if (_desktopLyricsColor == value) return;
    _desktopLyricsColor = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_desktopLyricsColorKey, value);
  }

  Future<void> setDesktopLyricsFontSize(double value) async {
    final next = value.clamp(16.0, 38.0);
    if ((_desktopLyricsFontSize - next).abs() < 0.01) return;
    _desktopLyricsFontSize = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_desktopLyricsFontSizeKey, next);
  }

  HotKey? _parseHotKey(String? jsonStr, String type) {
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final Map<String, dynamic> json = jsonDecode(jsonStr);
        return HotKey.fromJson(json);
      } catch (e) {
        // Fallback to default
      }
    }
    return _getDefaultHotKey(type);
  }

  HotKey _getDefaultHotKey(String type) {
    switch (type) {
      case 'play_pause':
        return HotKey(
          key: PhysicalKeyboardKey.space,
          modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
          scope: HotKeyScope.system,
          identifier: 'play_pause',
        );
      case 'next_track':
        return HotKey(
          key: PhysicalKeyboardKey.arrowRight,
          modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
          scope: HotKeyScope.system,
          identifier: 'next_track',
        );
      case 'prev_track':
        return HotKey(
          key: PhysicalKeyboardKey.arrowLeft,
          modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
          scope: HotKeyScope.system,
          identifier: 'prev_track',
        );
      case 'volume_up':
        return HotKey(
          key: PhysicalKeyboardKey.arrowUp,
          modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
          scope: HotKeyScope.system,
          identifier: 'volume_up',
        );
      case 'volume_down':
        return HotKey(
          key: PhysicalKeyboardKey.arrowDown,
          modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
          scope: HotKeyScope.system,
          identifier: 'volume_down',
        );
      default:
        throw ArgumentError('Invalid hotkey type');
    }
  }

  Future<void> setEnableGlobalHotkeys(bool value) async {
    _enableGlobalHotkeys = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableGlobalHotkeysKey, value);
  }

  Future<void> setHotKey(String type, HotKey? hotKey) async {
    final prefs = await SharedPreferences.getInstance();
    final String key;
    switch (type) {
      case 'play_pause':
        _playPauseHotKey = hotKey;
        key = _playPauseHotKeyKey;
        break;
      case 'next_track':
        _nextTrackHotKey = hotKey;
        key = _nextTrackHotKeyKey;
        break;
      case 'prev_track':
        _prevTrackHotKey = hotKey;
        key = _prevTrackHotKeyKey;
        break;
      case 'volume_up':
        _volumeUpHotKey = hotKey;
        key = _volumeUpHotKeyKey;
        break;
      case 'volume_down':
        _volumeDownHotKey = hotKey;
        key = _volumeDownHotKeyKey;
        break;
      default:
        return;
    }
    notifyListeners();
    if (hotKey != null) {
      await prefs.setString(key, jsonEncode(hotKey.toJson()));
    } else {
      await prefs.remove(key);
    }
  }

  Future<void> resetToDefaultHotKeys() async {
    final prefs = await SharedPreferences.getInstance();
    _playPauseHotKey = _getDefaultHotKey('play_pause');
    _nextTrackHotKey = _getDefaultHotKey('next_track');
    _prevTrackHotKey = _getDefaultHotKey('prev_track');
    _volumeUpHotKey = _getDefaultHotKey('volume_up');
    _volumeDownHotKey = _getDefaultHotKey('volume_down');
    notifyListeners();
    await prefs.setString(
      _playPauseHotKeyKey,
      jsonEncode(_playPauseHotKey!.toJson()),
    );
    await prefs.setString(
      _nextTrackHotKeyKey,
      jsonEncode(_nextTrackHotKey!.toJson()),
    );
    await prefs.setString(
      _prevTrackHotKeyKey,
      jsonEncode(_prevTrackHotKey!.toJson()),
    );
    await prefs.setString(
      _volumeUpHotKeyKey,
      jsonEncode(_volumeUpHotKey!.toJson()),
    );
    await prefs.setString(
      _volumeDownHotKeyKey,
      jsonEncode(_volumeDownHotKey!.toJson()),
    );
  }
}
