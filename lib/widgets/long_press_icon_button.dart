import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

class LongPressIconButton extends StatelessWidget {
  const LongPressIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    required this.onLongPress,
    this.color,
  });
  final String tooltip;
  final Widget icon;
  final Color? color;
  final VoidCallback onPressed, onLongPress;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    triggerMode: TooltipTriggerMode.manual,
    child: RawGestureDetector(
      gestures: {
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(
                duration: const Duration(milliseconds: 500),
              ),
              (recognizer) => recognizer.onLongPress = onLongPress,
            ),
      },
      child: IconButton(icon: icon, color: color, onPressed: onPressed),
    ),
  );
}
