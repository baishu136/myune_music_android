import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'playback_interaction_guard.dart';

class LongPressIconButton extends StatefulWidget {
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
  State<LongPressIconButton> createState() => _LongPressIconButtonState();
}

class _LongPressIconButtonState extends State<LongPressIconButton> {
  late final PlaybackInteractionGuard _guard;
  @override
  void initState() {
    super.initState();
    _guard = PlaybackInteractionGuard(onCancel: () {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _guard.updateContext(context);
  }

  @override
  void dispose() {
    _guard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.tooltip,
    triggerMode: TooltipTriggerMode.manual,
    child: Listener(
      onPointerDown: _guard.pointerDown,
      onPointerUp: _guard.pointerEnd,
      onPointerCancel: _guard.pointerEnd,
      child: RawGestureDetector(
        gestures: {
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(
                  duration: const Duration(milliseconds: 500),
                ),
                (recognizer) => recognizer.onLongPress = () {
                  if (_guard.allows) widget.onLongPress();
                },
              ),
        },
        child: IconButton(
          icon: widget.icon,
          color: widget.color,
          onPressed: () {
            if (_guard.allows) widget.onPressed();
          },
        ),
      ),
    ),
  );
}
