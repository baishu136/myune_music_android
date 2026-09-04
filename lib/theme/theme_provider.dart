import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_fonts/system_fonts.dart';
import 'package:flutter/foundation.dart';

import '../services/font_service.dart';

const themePresetColors = <Color>[
  Color(0xFFE53935),
  Color(0xFFD81B60),
  Color(0xFF8E24AA),
  Color(0xFF5E35B1),
  Color(0xFF3949AB),
  Color(0xFF1E88E5),
  Color(0xFF039BE5),
  Color(0xFF00ACC1),
  Color(0xFF00897B),
  Color(0xFF43A047),
  Color(0xFF7CB342),
  Color(0xFFC0CA33),
  Color(0xFFFDD835),
  Color(0xFFFFB300),
  Color(0xFFFB8C00),
  Color(0xFFF4511E),
  Color(0xFF6D4C41),
  Color(0xFF757575),
  Color(0xFF546E7A),
  Color(0xFF283593),
  Color(0xFF00695C),
  Color(0xFF2E7D32),
  Color(0xFFEF6C00),
  Color(0xFFC62828),
];

const _dynamicHueRange = 7.5;
const _dynamicSaturationRange = .18;

/// Picks a visually useful color that is also harmonious with the dominant
/// cover palette. The extractor returns colors in dominance order, but the
/// first non-black color may be a small foreground accent that clashes with a
/// blurred full-cover background. A rank-weighted palette medoid favors color
/// families repeated across the cover while still respecting dominance.
Color selectRepresentativeCoverColor(List<Color> dominantColors) {
  if (dominantColors.isEmpty) {
    throw ArgumentError.value(dominantColors, 'dominantColors', '不能为空');
  }
  final candidates = <({Color color, int rank})>[];
  for (var index = 0; index < dominantColors.length && index < 8; index++) {
    final color = dominantColors[index];
    final lightness = HSLColor.fromColor(color).lightness;
    if (lightness >= .08 && lightness <= .92) {
      candidates.add((color: color, rank: index));
    }
  }
  if (candidates.isEmpty) return dominantColors.first;
  if (candidates.length == 1) return candidates.first.color;

  var best = candidates.first;
  var bestScore = double.infinity;
  for (final candidate in candidates) {
    var weightedDistance = 0.0;
    var totalWeight = 0.0;
    for (final paletteColor in candidates) {
      final weight = 1 / (1 + paletteColor.rank * .7);
      weightedDistance +=
          _paletteColorDistance(candidate.color, paletteColor.color) * weight;
      totalWeight += weight;
    }
    final score = weightedDistance / totalWeight + candidate.rank * .012;
    if (score < bestScore) {
      best = candidate;
      bestScore = score;
    }
  }
  return best.color;
}

double _paletteColorDistance(Color first, Color second) {
  final firstHsl = HSLColor.fromColor(first);
  final secondHsl = HSLColor.fromColor(second);
  // Hue is less meaningful when either color is close to neutral.
  final hueReliability =
      .15 + .85 * math.min(firstHsl.saturation, secondHsl.saturation);
  final hueDistance = _circularHueDistance(firstHsl.hue, secondHsl.hue) / 180;
  return hueDistance * hueReliability * .55 +
      (firstHsl.saturation - secondHsl.saturation).abs() * .28 +
      (firstHsl.lightness - secondHsl.lightness).abs() * .17;
}

double _circularHueDistance(double first, double second) {
  final distance = (first - second).abs() % 360;
  return distance > 180 ? 360 - distance : distance;
}

/// Keeps an extracted cover color inside the family of the closest one of the
/// original 24 theme colors without snapping it to that exact swatch.
Color constrainDynamicSeedToPresetRange(Color color) {
  final source = HSLColor.fromColor(color);
  HSLColor closest = HSLColor.fromColor(themePresetColors.first);
  var closestScore = double.infinity;

  for (final presetColor in themePresetColors) {
    final preset = HSLColor.fromColor(presetColor);
    final hueWeight = source.saturation < .12 ? 0.0 : .62;
    final hueDistance = _circularHueDistance(source.hue, preset.hue) / 180;
    final saturationDistance = source.saturation - preset.saturation;
    final lightnessDistance = source.lightness - preset.lightness;
    final score =
        hueDistance * hueDistance * hueWeight +
        saturationDistance * saturationDistance * .23 +
        lightnessDistance * lightnessDistance * .15;
    if (score < closestScore) {
      closestScore = score;
      closest = preset;
    }
  }

  if (closest.saturation < .12) {
    return source
        .withSaturation(source.saturation.clamp(0.0, .12))
        .toColor()
        .withValues(alpha: color.a);
  }

  final rawHueDelta = (source.hue - closest.hue + 540) % 360 - 180;
  final hue =
      (closest.hue + rawHueDelta.clamp(-_dynamicHueRange, _dynamicHueRange)) %
      360;
  final minSaturation = (closest.saturation - _dynamicSaturationRange).clamp(
    0.0,
    1.0,
  );
  final maxSaturation = (closest.saturation + _dynamicSaturationRange).clamp(
    0.0,
    1.0,
  );
  return source
      .withHue(hue)
      .withSaturation(source.saturation.clamp(minSaturation, maxSaturation))
      .toColor()
      .withValues(alpha: color.a);
}

Color adaptDynamicSeedColor(Color color, Brightness brightness) {
  final rangedColor = constrainDynamicSeedToPresetRange(color);
  final hsl = HSLColor.fromColor(rangedColor);
  final targetLightness = brightness == Brightness.dark
      ? hsl.lightness.clamp(.62, 1.0)
      : hsl.lightness.clamp(0.0, .38);
  return hsl
      .withLightness(targetLightness)
      .toColor()
      .withValues(alpha: color.a);
}

class ThemeProvider with ChangeNotifier {
  static const TextStyle defaultStyle = TextStyle(fontWeight: FontWeight.w400);

  static const TextTheme misansTextTheme = TextTheme(
    displayLarge: defaultStyle,
    displayMedium: defaultStyle,
    displaySmall: defaultStyle,
    headlineLarge: defaultStyle,
    headlineMedium: defaultStyle,
    headlineSmall: defaultStyle,
    titleLarge: defaultStyle,
    titleMedium: defaultStyle,
    titleSmall: defaultStyle,
    bodyLarge: defaultStyle,
    bodyMedium: defaultStyle,
    bodySmall: defaultStyle,
    labelLarge: defaultStyle,
    labelMedium: defaultStyle,
    labelSmall: defaultStyle,
  );

  static final int _defaultSeedColorValue = Colors.blue.toARGB32(); // 默认蓝色
  Color _currentSeedColor = Color(
    _defaultSeedColorValue,
  ); // 当前正在使用的主题种子色（可能是动态色或手动色）
  Color _lastManualSeedColor = Color(
    _defaultSeedColorValue,
  ); // 用户最后一次手动选择的种子色，用于在关闭动态配色时恢复
  Color? _dynamicSourceColor;
  bool _animateThemeChanges = true;

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;
  ThemeMode get effectiveThemeMode => _themeMode;
  bool get isDarkMode => effectiveThemeMode == ThemeMode.dark;
  Brightness get resolvedBrightness => switch (effectiveThemeMode) {
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
    ThemeMode.system =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
  };

  static const String _seedColorKey = 'user_seed_color';
  static const String _lastManualSeedColorKey =
      'user_last_manual_seed_color'; // 用户手动选择的种子色，用于在关闭动态配色时恢复

  static const String _fontFamilyKey = 'user_font_family';
  static const String _fontOnlyLyricsKey = 'user_font_only_lyrics';
  String _currentFontFamily = 'Misans'; // 默认字体
  bool _fontOnlyLyrics = false;

  late ThemeData _lightThemeData;
  late ThemeData _darkThemeData;
  final LinkedHashMap<String, ({ThemeData light, ThemeData dark})>
  _themeDataCache = LinkedHashMap();
  static const _maximumThemeDataCacheEntries = 12;

  ThemeProvider() {
    _rebuildThemeData();
    initialize();
  }

  Color get currentSeedColor => _currentSeedColor;

  /// Dynamic cover colors must be visible on the song-change frame. Manual
  /// theme changes retain the configured Material transition.
  bool get animateThemeChanges => _animateThemeChanges;

  Color get lastManualSeedColor => _lastManualSeedColor;

  String get currentFontFamily => _currentFontFamily;

  bool get fontOnlyLyrics => _fontOnlyLyrics;

  String get _interfaceFontFamily =>
      _fontOnlyLyrics ? 'Misans' : _currentFontFamily;

  ColorScheme get currentColorScheme {
    return _buildColorScheme(Brightness.light);
  }

  ThemeData get lightThemeData => _lightThemeData;

  ThemeData get darkThemeData => _darkThemeData;

  ColorScheme _buildColorScheme(Brightness brightness, {Color? seedColor}) {
    final seed = seedColor ?? _currentSeedColor;
    final generated = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    final onSeed = seed.computeLuminance() > .45 ? Colors.black : Colors.white;
    return generated.copyWith(
      primary: seed,
      onPrimary: onSeed,
      surfaceTint: seed,
    );
  }

  ThemeData _buildThemeData(Brightness brightness, Color seedColor) {
    final scheme = _buildColorScheme(brightness, seedColor: seedColor);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: _interfaceFontFamily,
      textTheme: misansTextTheme,
    ).makeMouseClickable();
  }

  ({ThemeData light, ThemeData dark}) _themePairFor(Color seedColor) {
    final key = '${seedColor.toARGB32()}:$_interfaceFontFamily';
    final cached = _themeDataCache.remove(key);
    if (cached != null) {
      _themeDataCache[key] = cached;
      return cached;
    }
    final pair = (
      light: _buildThemeData(Brightness.light, seedColor),
      dark: _buildThemeData(Brightness.dark, seedColor),
    );
    _themeDataCache[key] = pair;
    while (_themeDataCache.length > _maximumThemeDataCacheEntries) {
      _themeDataCache.remove(_themeDataCache.keys.first);
    }
    return pair;
  }

  void _rebuildThemeData() {
    final pair = _themePairFor(_currentSeedColor);
    _lightThemeData = pair.light;
    _darkThemeData = pair.dark;
  }

  void prewarmDynamicSeedColor(Color sourceColor) {
    final adjusted = adaptDynamicSeedColor(sourceColor, resolvedBrightness);
    _themePairFor(adjusted);
  }

  Future<void> setSeedColor(Color newColor, {bool isManual = false}) async {
    _animateThemeChanges = true;
    final seedChanged = _currentSeedColor != newColor;
    if (isManual) {
      _dynamicSourceColor = null;
    }
    if (seedChanged) {
      _currentSeedColor = newColor;
      _rebuildThemeData();
      notifyListeners();
      await _saveSeedColor(newColor);
    }
    if (isManual) {
      _lastManualSeedColor = newColor;
      await _saveLastManualSeedColor(newColor);
    }
  }

  Future<void> setDynamicSeedColor(Color sourceColor) async {
    _animateThemeChanges = false;
    _dynamicSourceColor = sourceColor;
    final adjusted = adaptDynamicSeedColor(sourceColor, resolvedBrightness);
    if (_currentSeedColor == adjusted) return;
    _currentSeedColor = adjusted;
    _rebuildThemeData();
    notifyListeners();
    await _saveSeedColor(adjusted);
  }

  Future<void> _loadSeedColor() async {
    final prefs = await SharedPreferences.getInstance();
    final int? savedColorValue = prefs.getInt(_seedColorKey);
    if (savedColorValue != null) {
      _currentSeedColor = Color(savedColorValue);
    }
  }

  Future<void> _saveSeedColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seedColorKey, color.toARGB32());
  }

  Future<void> _saveLastManualSeedColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastManualSeedColorKey, color.toARGB32());
  }

  Future<void> _loadLastManualSeedColor() async {
    final prefs = await SharedPreferences.getInstance();
    final int? savedColorValue = prefs.getInt(_lastManualSeedColorKey);
    if (savedColorValue != null) {
      _lastManualSeedColor = Color(savedColorValue);
    }
  }

  Future<void> restoreLastManualColor() async {
    _animateThemeChanges = true;
    _dynamicSourceColor = null;
    final prefs = await SharedPreferences.getInstance();
    final int? savedColorValue = prefs.getInt(_lastManualSeedColorKey);
    final color = savedColorValue != null
        ? Color(savedColorValue)
        : Color(_defaultSeedColorValue);
    final seedChanged = _currentSeedColor != color;
    if (seedChanged) {
      _currentSeedColor = color;
      _rebuildThemeData();
      notifyListeners();
      await _saveSeedColor(color);
    }
  }

  // 迁移手动选择的种子色键名
  // 如果用户手动选择的种子色键名不存在，从种子色键中获取颜色值并迁移到用户手动选择的种子色键名
  // 这是为了在应用升级时，用户手动选择的种子色能够被恢复
  Future<void> _migrateManualColorKey() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_lastManualSeedColorKey)) {
      final existingSeed = prefs.getInt(_seedColorKey);
      if (existingSeed != null) {
        await prefs.setInt(_lastManualSeedColorKey, existingSeed);
      }
    }
  }

  Future<void> toggleDarkMode() {
    final nextMode = switch (_themeMode) {
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
      ThemeMode.system => ThemeMode.light,
    };
    return setThemeMode(nextMode);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    final dynamicColor = _dynamicSourceColor;
    if (dynamicColor != null) {
      _currentSeedColor = adaptDynamicSeedColor(
        dynamicColor,
        resolvedBrightness,
      );
      _rebuildThemeData();
      await _saveSeedColor(_currentSeedColor);
    }
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_theme_mode', _themeModeToString(_themeMode));
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  ThemeMode _stringToThemeMode(String? modeString) {
    switch (modeString) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> _loadDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    final String? modeString = prefs.getString('user_theme_mode');
    _themeMode = _stringToThemeMode(modeString);
  }

  Future<void> _loadFontFamily() async {
    final prefs = await SharedPreferences.getInstance();
    final savedFont = prefs.getString(_fontFamilyKey);
    if (savedFont != null && savedFont.isNotEmpty) {
      _currentFontFamily = savedFont;
    }
  }

  Future<void> _loadFontOnlyLyrics() async {
    final prefs = await SharedPreferences.getInstance();
    _fontOnlyLyrics = prefs.getBool(_fontOnlyLyricsKey) ?? false;
  }

  void setFontFamily(String fontFamily) async {
    if (_currentFontFamily == fontFamily) return; // 没变就直接退出
    _currentFontFamily = fontFamily;
    _rebuildThemeData();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fontFamilyKey, fontFamily);
  }

  void resetFontFamily() async {
    _currentFontFamily = 'Misans'; // 默认字体
    _rebuildThemeData();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_fontFamilyKey);
  }

  Future<void> setFontOnlyLyrics(bool value) async {
    if (_fontOnlyLyrics == value) return;
    _fontOnlyLyrics = value;
    _rebuildThemeData();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_fontOnlyLyricsKey, value);
  }

  Future<void> initialize() async {
    await Future.wait([
      _loadSeedColor(),
      _loadDarkMode(),
      _loadFontFamily(),
      _loadFontOnlyLyrics(),
    ]);
    await _migrateManualColorKey();
    await _loadLastManualSeedColor();
    if (_currentFontFamily != 'Misans') {
      final loaded = await FontService().loadFontByName(_currentFontFamily);
      if (!loaded) _currentFontFamily = 'Misans';
    }
    _rebuildThemeData();
    notifyListeners();
  }

  Future<void> loadCurrentFont(SystemFonts systemFonts) async {
    if (_currentFontFamily != 'Misans') {
      await systemFonts.loadFont(_currentFontFamily);
      notifyListeners();
    }
  }
}

class DesktopButtonTheme {
  const DesktopButtonTheme._(); // 防止实例化

  static const WidgetStateProperty<MouseCursor> clickableCursor =
      WidgetStatePropertyAll(SystemMouseCursors.click);

  static const TextButtonThemeData textButtonTheme = TextButtonThemeData(
    style: ButtonStyle(mouseCursor: clickableCursor),
  );

  static const ElevatedButtonThemeData elevatedButtonTheme =
      ElevatedButtonThemeData(style: ButtonStyle(mouseCursor: clickableCursor));

  static const OutlinedButtonThemeData outlinedButtonTheme =
      OutlinedButtonThemeData(style: ButtonStyle(mouseCursor: clickableCursor));
}

// 代码来源: https://github.com/flutter/flutter/issues/182466#issuecomment-3932182424
// 旨在修复Flutter 3.40+ 鼠标点击光标被移除的问题
// 参考 https://github.com/flutter/flutter/issues/182466
// TODO: 请等待Flutter修复该问题

extension on ThemeData {
  ThemeData makeMouseClickable() {
    final WidgetStateMouseCursor clickable =
        defaultTargetPlatform != TargetPlatform.android
        ? WidgetStateMouseCursor.clickable
        : WidgetStateMouseCursor.adaptiveClickable;
    return copyWith(
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: (elevatedButtonTheme.style ?? const ButtonStyle()).copyWith(
          mouseCursor: clickable,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: (filledButtonTheme.style ?? const ButtonStyle()).copyWith(
          mouseCursor: clickable,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: (outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(
          mouseCursor: clickable,
        ),
      ),
      floatingActionButtonTheme: floatingActionButtonTheme.copyWith(
        mouseCursor: clickable,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: (iconButtonTheme.style ?? const ButtonStyle()).copyWith(
          mouseCursor: clickable,
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: (menuButtonTheme.style ?? const ButtonStyle()).copyWith(
          mouseCursor: clickable,
        ),
      ),
      menuTheme: MenuThemeData(
        submenuIcon: menuTheme.submenuIcon,
        style: (menuTheme.style ?? const MenuStyle()).copyWith(
          mouseCursor: clickable,
        ),
      ),
      checkboxTheme: checkboxTheme.copyWith(mouseCursor: clickable),
      popupMenuTheme: popupMenuTheme.copyWith(mouseCursor: clickable),
      segmentedButtonTheme: segmentedButtonTheme.copyWith(
        style: (segmentedButtonTheme.style ?? const ButtonStyle()).copyWith(
          mouseCursor: clickable,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: (textButtonTheme.style ?? const ButtonStyle()).copyWith(
          mouseCursor: clickable,
        ),
      ),
    );
  }
}
