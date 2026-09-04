import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

String playbackClockLabel(Duration value) {
  final safeMilliseconds = value.inMilliseconds.clamp(0, 359999999);
  final safe = Duration(milliseconds: safeMilliseconds);
  return '${safe.inMinutes}:${safe.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}

int playbackRemainingSeconds(Duration position, Duration totalDuration) {
  final totalMs = totalDuration.inMilliseconds.clamp(0, 359999999);
  final positionMs = position.inMilliseconds.clamp(0, totalMs);
  return ((totalMs - positionMs) / Duration.millisecondsPerSecond).ceil();
}

class PlaybackProgressHeader extends StatelessWidget {
  const PlaybackProgressHeader({
    super.key,
    required this.positionListenable,
    required this.previewPositionListenable,
    required this.totalDuration,
  });

  final ValueListenable<Duration> positionListenable;
  final ValueListenable<double?> previewPositionListenable;
  final Duration totalDuration;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double?>(
      valueListenable: previewPositionListenable,
      builder: (context, previewPositionMs, _) {
        return ValueListenableBuilder<Duration>(
          valueListenable: positionListenable,
          builder: (context, position, _) {
            final displayedPosition = previewPositionMs == null
                ? position
                : Duration(milliseconds: previewPositionMs.round());
            final totalMs = totalDuration.inMilliseconds.clamp(0, 359999999);
            final clampedPosition = Duration(
              milliseconds: displayedPosition.inMilliseconds.clamp(0, totalMs),
            );
            final remainingSeconds = playbackRemainingSeconds(
              clampedPosition,
              totalDuration,
            );
            final elapsedLabel = playbackClockLabel(clampedPosition);
            final totalLabel = playbackClockLabel(totalDuration);

            return Semantics(
              label:
                  '已播放 $elapsedLabel，歌曲时长 $totalLabel，剩余 $remainingSeconds 秒',
              child: Opacity(
                opacity: .5,
                child: Text(
                  '${remainingSeconds}s',
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
