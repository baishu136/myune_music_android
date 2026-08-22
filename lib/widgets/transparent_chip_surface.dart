import 'package:flutter/material.dart';

/// Makes a Material chip's canvas genuinely transparent within this subtree.
///
/// [RawChip] creates an internal canvas [Material] whose fallback color comes
/// from [ThemeData.canvasColor]. A transparent chip fill alone does not hide
/// that canvas. This widget scopes the transparent canvas to only the wrapped
/// chip so the rest of the application keeps its normal Material surfaces.
class TransparentChipSurface extends StatelessWidget {
  const TransparentChipSurface({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(canvasColor: Colors.transparent),
      child: child,
    );
  }
}
