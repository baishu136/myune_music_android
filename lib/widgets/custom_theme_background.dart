import 'dart:io';

import 'package:flutter/material.dart';

class CustomThemeBackground extends StatelessWidget {
  const CustomThemeBackground({
    super.key,
    required this.path,
    required this.enabled,
    required this.dim,
    required this.child,
  });

  final String? path;
  final bool enabled;
  final double dim;
  final Widget child;

  bool get _canShow {
    final value = path;
    return enabled &&
        value != null &&
        value.isNotEmpty &&
        File(value).existsSync();
  }

  @override
  Widget build(BuildContext context) {
    if (!_canShow) return child;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          File(path!),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
        ),
        ColoredBox(
          color: (dark ? Colors.black : Colors.white).withValues(
            alpha: dim.clamp(0.0, 0.92),
          ),
        ),
        child,
      ],
    );
  }
}
