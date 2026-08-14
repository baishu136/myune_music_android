import 'package:flutter/animation.dart';

/// Shared motion for visual changes caused by a theme update.
abstract final class ThemeMotion {
  static const Duration transitionDuration = Duration(milliseconds: 380);
  static const Curve transitionCurve = Cubic(0.16, 1.0, 0.3, 1.0);
}
