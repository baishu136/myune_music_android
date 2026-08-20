import 'dart:math' as math;

import 'package:flutter/material.dart';

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

class _PlayPauseButtonState extends State<PlayPauseButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
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
      if (widget.isPlaying) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
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
            angle: transition * math.pi / 3,
            child: Transform.scale(scale: 1 - transition * .08, child: child),
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
    if (widget.backgroundColor == null) return button;
    return Material(
      color: widget.backgroundColor,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: button,
    );
  }
}
