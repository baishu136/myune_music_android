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
        ..moveTo(3, 10)
        ..lineTo(3, 7)
        ..quadraticBezierTo(3, 5, 5, 5)
        ..lineTo(20, 5)
        ..moveTo(17, 2)
        ..lineTo(20, 5)
        ..lineTo(17, 8)
        ..moveTo(21, 14)
        ..lineTo(21, 17)
        ..quadraticBezierTo(21, 19, 19, 19)
        ..lineTo(4, 19)
        ..moveTo(7, 16)
        ..lineTo(4, 19)
        ..lineTo(7, 22),
      pen,
    );
    pen.strokeWidth = 1.35;
    canvas.drawPath(
      Path()
        ..moveTo(8, 9)
        ..lineTo(9, 9)
        ..cubicTo(11.5, 9, 12.5, 15, 15.5, 15)
        ..moveTo(14, 13.5)
        ..lineTo(15.5, 15)
        ..lineTo(14, 16.5)
        ..moveTo(8, 15)
        ..lineTo(9, 15)
        ..cubicTo(11.5, 15, 12.5, 9, 15.5, 9)
        ..moveTo(14, 7.5)
        ..lineTo(15.5, 9)
        ..lineTo(14, 10.5),
      pen,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RepeatShufflePainter oldDelegate) =>
      oldDelegate.color != color;
}
