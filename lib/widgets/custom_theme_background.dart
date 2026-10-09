import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/theme_motion.dart';
import '../theme/theme_provider.dart';
import 'gaussian_artwork_surface.dart';

/// Maps the persisted 0–40 strength to a Gaussian standard deviation.
double backgroundGaussianSigma(double strength) {
  final normalized = strength.clamp(0.0, 40.0);
  if (normalized <= 0) return 0;
  return (normalized * 2.25).clamp(0.0, 90.0);
}

class CustomThemeBackground extends StatefulWidget {
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

  @override
  State<CustomThemeBackground> createState() => _CustomThemeBackgroundState();
}

class _CustomThemeBackgroundState extends State<CustomThemeBackground> {
  Uint8List? _coverSource;

  Uint8List? get _stableCover {
    final next = widget.coverBytes;
    if (!identical(next, _coverSource) && !listEquals(next, _coverSource)) {
      _coverSource = next;
    }
    return _coverSource;
  }

  bool get _canShowCover =>
      widget.coverEnabled &&
      widget.coverBytes != null &&
      widget.coverBytes!.isNotEmpty;
  bool get _canShowCustomImage =>
      widget.enabled && widget.path != null && widget.path!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final showCover = _canShowCover;
    if (!showCover && !_canShowCustomImage) return widget.child;
    final mode = context.watch<ThemeProvider?>()?.effectiveThemeMode;
    final dark = widget.brightnessOverride != null
        ? widget.brightnessOverride == Brightness.dark
        : switch (mode) {
            ThemeMode.light => false,
            ThemeMode.dark => true,
            ThemeMode.system =>
              MediaQuery.platformBrightnessOf(context) == Brightness.dark,
            null => Theme.of(context).brightness == Brightness.dark,
          };
    // Retain original texels for mipmapped minification. A low-resolution
    // bilinear intermediate can alias fine ink before Gaussian can remove it.
    final ImageProvider<Object> provider = showCover
        ? MemoryImage(_stableCover!)
        : FileImage(File(widget.path!));
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          key: ValueKey(
            showCover
                ? 'cover-follow-background'
                : 'custom-theme-background-${widget.path}',
          ),
          child: GaussianArtworkSurface(
            provider: provider,
            sigma: backgroundGaussianSigma(
              showCover ? widget.coverBlurSigma : widget.blurSigma,
            ),
            imageKey: const ValueKey('theme-background-image'),
            errorBuilder: showCover
                ? null
                : (_, __, ___) => ColoredBox(
                    color: Theme.of(context).scaffoldBackgroundColor,
                  ),
          ),
        ),
        AnimatedContainer(
          duration: ThemeMotion.transitionDuration,
          curve: ThemeMotion.transitionCurve,
          color: (dark ? Colors.black : Colors.white).withValues(
            alpha: (showCover ? widget.coverDim : widget.dim).clamp(0.0, 0.92),
          ),
        ),
        widget.child,
      ],
    );
  }
}
