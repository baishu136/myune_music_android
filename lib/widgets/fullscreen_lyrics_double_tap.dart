import 'package:flutter/material.dart';

/// Competes in Flutter's gesture arena: a recognised double tap cancels the
/// enclosing single tap; horizontal/vertical drags and multi-touch still win.
class FullscreenLyricsDoubleTap extends StatelessWidget {
  const FullscreenLyricsDoubleTap({
    super.key,
    required this.enabled,
    required this.onTogglePlayback,
    required this.child,
  });
  final bool enabled;
  final VoidCallback onTogglePlayback;
  final Widget child;
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onDoubleTap: enabled ? onTogglePlayback : null,
    child: child,
  );
}
