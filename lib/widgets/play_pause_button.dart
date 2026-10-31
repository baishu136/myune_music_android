import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'interaction_motion.dart';

class PlayPauseButton extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onPressed;
  final Color color;
  final double size;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;
  final String? tooltip;

  const PlayPauseButton({
    super.key,
    required this.isPlaying,
    required this.onPressed,
    required this.color,
    this.size = 36.0,
    this.backgroundColor,
    this.padding = const EdgeInsets.all(8),
    this.tooltip,
  });

  @override
  State<PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends InteractionMotionState<PlayPauseButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late final CurvedAnimation _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 240),
    );
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );

    // 根据初始播放状态设置动画控制器的值
    if (widget.isPlaying) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant PlayPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 当播放状态改变时，控制动画
    if (oldWidget.isPlaying != widget.isPlaying) {
      if (!motionAllowed) {
        resetMotion();
        return;
      }
      if (widget.isPlaying) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void resetMotion() {
    _controller.stop();
    final target = widget.isPlaying ? 1.0 : 0.0;
    if (_controller.value != target) _controller.value = target;
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      iconSize: widget.size,
      padding: widget.padding,
      tooltip: widget.tooltip,
      icon: AnimatedBuilder(
        animation: _progress,
        builder: (context, child) {
          final transition = math.sin(math.pi * _progress.value);
          return Transform.rotate(
            key: const ValueKey('play_pause_rotation'),
            angle: transition * math.pi / 18,
            child: Transform.scale(scale: 1 - transition * .035, child: child),
          );
        },
        child: AnimatedIcon(
          icon: AnimatedIcons.play_pause,
          progress: _progress,
          color: widget.color,
        ),
      ),
      onPressed: widget.onPressed,
    );
    if (widget.backgroundColor == null) return ButtonPressMotion(child: button);
    return ButtonPressMotion(
      child: Material(
        color: widget.backgroundColor,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: button,
      ),
    );
  }
}
