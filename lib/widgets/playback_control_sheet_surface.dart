import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class PlaybackControlSheetSurface extends StatelessWidget {
  const PlaybackControlSheetSurface({
    super.key,
    required this.fluid,
    required this.child,
  });
  final bool fluid;
  final Widget child;
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
      borderRadius: radius,
      child: BackdropFilter(
        key: const ValueKey('playback-feature-backdrop-filter'),
        filter: fluid ? _fluidBlur : _blur,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(
              alpha: fluid ? .28 : .10,
            ),
            borderRadius: radius,
            border: Border.all(color: border.withValues(alpha: .72)),
          ),
          child: Material(
            color: Colors.transparent,
            shape: const RoundedRectangleBorder(borderRadius: radius),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ),
      ),
    );
  }
}
