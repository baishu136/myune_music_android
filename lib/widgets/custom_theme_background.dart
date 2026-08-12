import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class CustomThemeBackground extends StatelessWidget {
  const CustomThemeBackground({
    super.key,
    required this.path,
    required this.enabled,
    required this.dim,
    required this.child,
    this.coverBytes,
    this.coverEnabled = false,
    this.coverBlurSigma = 22,
    this.coverDim = 0.56,
  });

  final String? path;
  final bool enabled;
  final double dim;
  final Widget child;
  final Uint8List? coverBytes;
  final bool coverEnabled;
  final double coverBlurSigma;
  final double coverDim;

  bool get _canShowCover =>
      coverEnabled && coverBytes != null && coverBytes!.isNotEmpty;

  bool get _canShowCustomImage {
    final value = path;
    return enabled &&
        value != null &&
        value.isNotEmpty &&
        File(value).existsSync();
  }

  @override
  Widget build(BuildContext context) {
    final showCover = _canShowCover;
    if (!showCover && !_canShowCustomImage) return child;
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget image = showCover
        ? Image.memory(
            coverBytes!,
            key: const ValueKey('cover-follow-background'),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
          )
        : Image.file(
            File(path!),
            key: ValueKey('custom-theme-background-$path'),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
          );
    if (showCover && coverBlurSigma > 0) {
      image = ClipRect(
        child: Transform.scale(
          scale: 1.08,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: coverBlurSigma,
              sigmaY: coverBlurSigma,
            ),
            child: image,
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: image),
        ColoredBox(
          color: (dark ? Colors.black : Colors.white).withValues(
            alpha: (showCover ? coverDim : dim).clamp(0.0, 0.92),
          ),
        ),
        child,
      ],
    );
  }
}
