import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class PlaybackControlSheetSurface extends StatelessWidget {
  const PlaybackControlSheetSurface({
    super.key,
    required this.fluid,
    required this.child,
    this.borderRadius = radius,
    this.borderSide,
  });
  final bool fluid;
  final Widget child;
  final BorderRadius borderRadius;
  final BorderSide? borderSide;
  static const radius = BorderRadius.vertical(top: Radius.circular(28));
  static final _blur = ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7);
  static final _fluidBlur = ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = theme.brightness == Brightness.light
        ? Colors.white
        : theme.colorScheme.outlineVariant;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        key: const ValueKey('playback-feature-backdrop-filter'),
        filter: fluid ? _fluidBlur : _blur,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(
              alpha: fluid ? .28 : .10,
            ),
            borderRadius: borderRadius,
            border: Border.fromBorderSide(
              borderSide ?? BorderSide(color: border.withValues(alpha: .72)),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: borderRadius),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ),
      ),
    );
  }
}
