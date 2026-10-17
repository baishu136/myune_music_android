import 'package:flutter/material.dart';

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
    child: GestureDetector(
      onLongPress: onLongPress,
      child: IconButton(icon: icon, color: color, onPressed: onPressed),
    ),
  );
}
