import 'package:flutter/material.dart';

class LyricSeekGuide extends StatelessWidget {
  const LyricSeekGuide({
    super.key,
    required this.timeLabel,
    required this.contentColor,
    required this.centerY,
    this.timeOnLeft = false,
  });

  final String timeLabel;
  final Color contentColor;
  final double centerY;
  final bool timeOnLeft;

  Widget _timeSlot(BuildContext context) => SizedBox(
    key: const ValueKey('mobile_lyrics_progress_time_slot'),
    width: 56,
    height: 48,
    child: Center(
      child: Text(
        timeLabel,
        key: const ValueKey('mobile_lyrics_progress_time'),
        maxLines: 1,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: contentColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: Transform.translate(
      offset: Offset(0, centerY - 24),
      child: SizedBox(
        key: const ValueKey('mobile_lyrics_progress_guide'),
        width: double.infinity,
        height: 48,
        child: Align(
          alignment: timeOnLeft ? Alignment.centerLeft : Alignment.centerRight,
          child: _timeSlot(context),
        ),
      ),
    ),
  );
}
