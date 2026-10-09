import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Marks the neutral home palette only. Coloured and neutral themes use the
/// same translucent surface parameters.
@immutable
class HomeChromeStyle extends ThemeExtension<HomeChromeStyle> {
  const HomeChromeStyle({required this.brightness});
  final Brightness brightness;

  static const light = HomeChromeStyle(brightness: Brightness.light);
  static const dark = HomeChromeStyle(brightness: Brightness.dark);

  @override
  HomeChromeStyle copyWith({Brightness? brightness}) =>
      HomeChromeStyle(brightness: brightness ?? this.brightness);

  @override
  HomeChromeStyle lerp(covariant HomeChromeStyle? other, double t) =>
      other == null || t < .5 ? this : other;
}

enum HomeGlassRole { navigation, playback, controls, playlist }

/// All home surfaces retain one 70%-opaque fill with no gradient, extra
/// opacity layer or layout inset. Legacy filters stay dormant; home surfaces
/// no longer blur their backdrop, independently of custom-image blur.
abstract final class HomeGlassProfile {
  static const backgroundOpacity = .70;
  static const maximumSigma = 20.0;

  static bool blurEnabled(HomeGlassRole role) => false;

  static double blurStrength(HomeGlassRole role) =>
      role == HomeGlassRole.navigation ? .70 : .20;

  static double sigma(HomeGlassRole role) => maximumSigma * blurStrength(role);

  // Two bounded instances, never created/interpolated during animation frames.
  static final _navigationFilter = ui.ImageFilter.blur(
    sigmaX: sigma(HomeGlassRole.navigation),
    sigmaY: sigma(HomeGlassRole.navigation),
    tileMode: TileMode.clamp,
  );
  static final _playbackFilter = ui.ImageFilter.blur(
    sigmaX: sigma(HomeGlassRole.playback),
    sigmaY: sigma(HomeGlassRole.playback),
    tileMode: TileMode.clamp,
  );

  static ui.ImageFilter filter(HomeGlassRole role) =>
      role == HomeGlassRole.navigation ? _navigationFilter : _playbackFilter;
}

/// Stable translucent local surface. No Padding,
/// border or height constraint to change layout/touch coordinates. Footer
/// corners stay square; controls/playlists clip their existing shape.
/// The retained disabled filter never blurs the backdrop.
class HomeGlassSurface extends StatelessWidget {
  const HomeGlassSurface({
    super.key,
    required this.child,
    this.role = HomeGlassRole.navigation,
    this.cornerRadius = 0,
    this.enabled = true,
    this.fillColor,
  });
  final Widget child;
  final HomeGlassRole role;
  final double cornerRadius;
  final bool enabled;
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill =
        fillColor ??
        (role == HomeGlassRole.navigation
            ? theme.colorScheme.surfaceContainer
            : theme.colorScheme.surfaceContainerHigh);
    final radius =
        enabled &&
            (role == HomeGlassRole.controls || role == HomeGlassRole.playlist)
        ? cornerRadius
        : 0.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: !enabled
          ? Clip.none
          : radius > 0
          ? Clip.antiAlias
          : Clip.hardEdge,
      child: BackdropFilter(
        enabled: enabled && HomeGlassProfile.blurEnabled(role),
        filter: HomeGlassProfile.filter(role),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: enabled
                ? fill.withValues(alpha: HomeGlassProfile.backgroundOpacity)
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// One 70%-opaque fill outside AnimatedSwitcher covers the action group.
/// Backdrop filtering is disabled on controls. No margin or
/// padding: the original button positions and hit targets are preserved.
class HomeGlassControls extends StatelessWidget {
  const HomeGlassControls({
    super.key,
    required this.child,
    this.cornerRadius = 24,
    this.enabled = true,
  });
  final Widget child;
  final double cornerRadius;
  final bool enabled;

  @override
  Widget build(BuildContext context) => HomeGlassSurface(
    role: HomeGlassRole.controls,
    cornerRadius: cornerRadius,
    enabled: enabled,
    child: Material(color: Colors.transparent, child: child),
  );
}

/// Keep the ink/touch behaviour of the original Material surface, but let the
/// translucent fill show through in every theme.
class HomeGlassMaterial extends StatelessWidget {
  const HomeGlassMaterial({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => HomeGlassSurface(
    role: HomeGlassRole.playback,
    child: Material(color: Colors.transparent, child: child),
  );
}

/// One translucent, non-blurred surface per visible playlist tile.
/// The selected tint uses the current theme; dimensions/InkWell stay external.
class HomePlaylistSurface extends StatelessWidget {
  const HomePlaylistSurface({
    super.key,
    required this.child,
    this.selected = false,
    this.cornerRadius = 14,
  });
  final Widget child;
  final bool selected;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return HomeGlassSurface(
      role: HomeGlassRole.playlist,
      cornerRadius: cornerRadius,
      fillColor: selected ? scheme.secondaryContainer : scheme.surfaceContainer,
      child: Material(color: Colors.transparent, child: child),
    );
  }
}
