import 'package:flutter/material.dart';

import '../widgets/home_glass_surface.dart';

@immutable
class HomePlaybackAccent extends ThemeExtension<HomePlaybackAccent> {
  const HomePlaybackAccent(this.color);
  final Color color;

  @override
  HomePlaybackAccent copyWith({Color? color}) =>
      HomePlaybackAccent(color ?? this.color);

  @override
  HomePlaybackAccent lerp(HomePlaybackAccent? other, double t) =>
      HomePlaybackAccent(Color.lerp(color, other?.color ?? color, t)!);
}

// Generated once, not on song changes/animation frames. Only the home subtree
// receives this scheme; the app theme and pushed playback route remain intact.
final _neutralHomeSchemes = {
  for (final brightness in Brightness.values)
    brightness:
        ColorScheme.fromSeed(
          seedColor: Colors.grey,
          brightness: brightness,
          dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
        ).copyWith(
          surface: brightness == Brightness.light
              ? Colors.white
              : const Color(0xFF121212),
          surfaceContainerLowest: brightness == Brightness.light
              ? Colors.white
              : const Color(0xFF0E0E0E),
          surfaceContainerLow: brightness == Brightness.light
              ? Colors.white
              : const Color(0xFF161616),
          surfaceContainer: brightness == Brightness.light
              ? Colors.white
              : const Color(0xFF1A1A1A),
          surfaceContainerHigh: brightness == Brightness.light
              ? Colors.white
              : const Color(0xFF202020),
          surfaceContainerHighest: brightness == Brightness.light
              ? Colors.white
              : const Color(0xFF282828),
          surfaceTint: Colors.transparent,
          primary: brightness == Brightness.light
              ? const Color(0xFF303030)
              : const Color(0xFFE8E8E8),
          onPrimary: brightness == Brightness.light
              ? Colors.white
              : const Color(0xFF181818),
          secondaryContainer: brightness == Brightness.light
              ? const Color(0xFFDADADA)
              : const Color(0xFF3B3B3B),
          onSecondaryContainer: brightness == Brightness.light
              ? const Color(0xFF202020)
              : const Color(0xFFF2F2F2),
          onSurface: brightness == Brightness.light
              ? const Color(0xFF202020)
              : const Color(0xFFF2F2F2),
          onSurfaceVariant: brightness == Brightness.light
              ? const Color(0xFF595959)
              : const Color(0xFFBFBFBF),
          outline: brightness == Brightness.light
              ? const Color(0xFF757575)
              : const Color(0xFF999999),
          outlineVariant: brightness == Brightness.light
              ? const Color(0xFFD2D2D2)
              : const Color(0xFF484848),
        ),
};

ThemeData neutralHomeTheme(ThemeData source) {
  final scheme = _neutralHomeSchemes[source.brightness]!;
  return source.copyWith(
    colorScheme: scheme,
    primaryColor: scheme.primary,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    // Replace inherited seed-tinted foregrounds, preserving font/size/weight.
    textTheme: source.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    iconTheme: source.iconTheme.copyWith(color: scheme.onSurface),
    iconButtonTheme: IconButtonThemeData(
      style: (source.iconButtonTheme.style ?? const ButtonStyle()).copyWith(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? scheme.onSurface.withValues(alpha: .38)
              : scheme.onSurface,
        ),
      ),
    ),
    floatingActionButtonTheme: source.floatingActionButtonTheme.copyWith(
      foregroundColor: scheme.onSurface,
    ),
    extensions: [
      ...source.extensions.values.where(
        (value) => value is! HomeChromeStyle && value is! HomePlaybackAccent,
      ),
      HomePlaybackAccent(source.colorScheme.primary),
      source.brightness == Brightness.light
          ? HomeChromeStyle.light
          : HomeChromeStyle.dark,
    ],
    appBarTheme: source.appBarTheme.copyWith(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: source.navigationBarTheme.copyWith(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.secondaryContainer,
    ),
    navigationRailTheme: source.navigationRailTheme.copyWith(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.secondaryContainer,
    ),
  );
}

ThemeData whiteHomeBackgroundTheme(ThemeData source) {
  if (source.brightness != Brightness.light) return source;
  final scheme = source.colorScheme.copyWith(
    surface: Colors.white,
    surfaceDim: Colors.white,
    surfaceBright: Colors.white,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white,
    surfaceContainer: Colors.white,
    surfaceContainerHigh: Colors.white,
    surfaceContainerHighest: Colors.white,
    surfaceTint: Colors.transparent,
  );
  return source.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.white,
    canvasColor: Colors.white,
    cardColor: Colors.white,
    appBarTheme: source.appBarTheme.copyWith(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: source.navigationBarTheme.copyWith(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    navigationRailTheme: source.navigationRailTheme.copyWith(
      backgroundColor: Colors.white,
    ),
  );
}

class HomeThemeScope extends StatefulWidget {
  const HomeThemeScope({
    super.key,
    required this.disabled,
    required this.builder,
  });
  final bool disabled;
  final WidgetBuilder builder;

  @override
  State<HomeThemeScope> createState() => _HomeThemeScopeState();
}

class _HomeThemeScopeState extends State<HomeThemeScope> {
  ThemeData? _source;
  ThemeData? _home;
  ThemeData? _neutral;

  @override
  Widget build(BuildContext context) {
    final source = Theme.of(context);
    if (!identical(source, _source)) {
      _source = source;
      _home = whiteHomeBackgroundTheme(source);
      _neutral = null;
    }
    if (widget.disabled) _neutral ??= neutralHomeTheme(_home!);
    // Keep the same wrapper even when toggled, preserving page/scroll State.
    return Theme(
      data: widget.disabled ? _neutral! : _home!,
      child: Builder(builder: widget.builder),
    );
  }
}
