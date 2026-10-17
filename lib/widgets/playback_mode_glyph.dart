import 'package:flutter/material.dart';
import '../services/playback_navigation.dart';

IconData playbackModeIcon(PlayMode mode) => switch (mode) {
  PlayMode.sequence => Icons.repeat,
  PlayMode.shuffle => Icons.shuffle,
  PlayMode.repeatOne => Icons.repeat_one,
  PlayMode.repeatShuffle => Icons.repeat,
};

class PlaybackModeGlyph extends StatelessWidget {
  const PlaybackModeGlyph({
    super.key,
    required this.mode,
    this.size = 24,
    this.color,
  });
  final PlayMode mode;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => mode != PlayMode.repeatShuffle
      ? Icon(playbackModeIcon(mode), size: size, color: color)
      : SizedBox.square(
          dimension: size,
          child: CustomPaint(
            key: const ValueKey('repeat-shuffle-glyph'),
            painter: _RepeatShufflePainter(
              color ?? IconTheme.of(context).color ?? Colors.white,
            ),
          ),
        );
}

class _RepeatShufflePainter extends CustomPainter {
  const _RepeatShufflePainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(5, 6)
        ..lineTo(8, 6)
        ..cubicTo(12, 6, 13, 18, 18, 18)
        ..lineTo(21, 18)
        ..moveTo(18, 15)
        ..lineTo(21, 18)
        ..lineTo(18, 21)
        ..moveTo(5, 18)
        ..lineTo(8, 18)
        ..cubicTo(12, 18, 13, 6, 18, 6)
        ..lineTo(21, 6)
        ..moveTo(18, 3)
        ..lineTo(21, 6)
        ..lineTo(18, 9)
        ..moveTo(5, 6)
        ..cubicTo(.5, 6, .5, 18, 5, 18),
      pen,
    );
    pen.strokeWidth = 1.5;
    canvas.drawPath(
      Path()
        ..moveTo(5.2, 10)
        ..lineTo(6.6, 9.2)
        ..lineTo(6.6, 14.8)
        ..moveTo(5.4, 14.8)
        ..lineTo(7.8, 14.8),
      pen,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RepeatShufflePainter oldDelegate) =>
      oldDelegate.color != color;
}
