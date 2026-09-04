import 'package:flutter/animation.dart';

/// Shared motion for visual changes caused by a theme update.
abstract final class ThemeMotion {
  // A visible slow-fast-slow interpolation keeps both ends soft while making
  // the main color shift clear in the middle of the transition.
  static const Duration transitionDuration = Duration(milliseconds: 180);
  static const Curve transitionCurve = Curves.easeInOutCubic;
}
