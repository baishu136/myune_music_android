import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/theme_motion.dart';
import '../theme/theme_provider.dart';
import 'artwork_image.dart';

/// Maps the existing user-facing 0–40 strength to a true Gaussian standard
/// deviation. A wider sigma removes recognizable cover details while keeping
/// the setting range and persisted values backward compatible.
double backgroundGaussianSigma(double strength) {
  final normalized = strength.clamp(0.0, 40.0);
  if (normalized <= 0) return 0;
  return (normalized * 2.25).clamp(0.0, 90.0);
}

final Map<double, ui.ImageFilter> _backgroundBlurFilters = {};

ui.ImageFilter _cachedBackgroundBlur(double sigma) {
  final cacheKey = (sigma * 4).round() / 4;
  return _backgroundBlurFilters.putIfAbsent(
    cacheKey,
    () => ui.ImageFilter.blur(
      sigmaX: cacheKey,
      sigmaY: cacheKey,
      tileMode: TileMode.mirror,
    ),
  );
}

class CustomThemeBackground extends StatelessWidget {
  const CustomThemeBackground({
    super.key,
    required this.path,
    required this.enabled,
    required this.dim,
    required this.child,
    this.coverBytes,
    this.coverEnabled = false,
    this.blurSigma = 22,
    this.coverBlurSigma = 22,
    this.coverDim = 0.56,
    this.brightnessOverride,
  });

  final String? path;
  final bool enabled;
  final double dim;
  final Widget child;
  final Uint8List? coverBytes;
  final bool coverEnabled;
  final double blurSigma;
  final double coverBlurSigma;
  final double coverDim;
  final Brightness? brightnessOverride;

  bool get _canShowCover =>
      coverEnabled && coverBytes != null && coverBytes!.isNotEmpty;

  bool get _canShowCustomImage {
    final value = path;
    return enabled && value != null && value.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final showCover = _canShowCover;
    if (!showCover && !_canShowCustomImage) return child;
    final mode = context.watch<ThemeProvider?>()?.effectiveThemeMode;
    final dark = brightnessOverride != null
        ? brightnessOverride == Brightness.dark
        : switch (mode) {
            ThemeMode.light => false,
            ThemeMode.dark => true,
            ThemeMode.system =>
              MediaQuery.platformBrightnessOf(context) == Brightness.dark,
            null => Theme.of(context).brightness == Brightness.dark,
          };
    final effectiveBlur = backgroundGaussianSigma(
      showCover ? coverBlurSigma : blurSigma,
    );
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final customImageCacheWidth = effectiveBlur > 0
        ? 512
        : (viewportWidth * devicePixelRatio).round().clamp(720, 2048);
    Widget image = showCover
        ? ArtworkImage(
            bytes: coverBytes!,
            size: ArtworkSize.medium,
            key: const ValueKey('cover-follow-background'),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
          )
        : Image.file(
            File(path!),
            key: ValueKey('custom-theme-background-$path'),
            fit: BoxFit.cover,
            cacheWidth: customImageCacheWidth,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) =>
                ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
          );
    if (effectiveBlur > 0) {
      image = ClipRect(
        child: Transform.scale(
          scale: (1 + effectiveBlur / 450).clamp(1.0, 1.20),
          child: ImageFiltered(
            imageFilter: _cachedBackgroundBlur(effectiveBlur),
            child: image,
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: image),
        AnimatedContainer(
          duration: ThemeMotion.transitionDuration,
          curve: ThemeMotion.transitionCurve,
          color: (dark ? Colors.black : Colors.white).withValues(
            alpha: (showCover ? coverDim : dim).clamp(0.0, 0.92),
          ),
        ),
        child,
      ],
    );
  }
}
