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

typedef PlaybackClockValue = ({String elapsed, String total, int remaining});

/// Filters visual clock text only. Playback, seek and lyric clocks stay full rate.
class PlaybackClockBuilder extends StatefulWidget {
  const PlaybackClockBuilder({
    super.key,
    required this.positionListenable,
    required this.previewPositionListenable,
    required this.totalDuration,
    required this.builder,
  });
  final ValueListenable<Duration> positionListenable;
  final ValueListenable<double?> previewPositionListenable;
  final Duration totalDuration;
  final Widget Function(BuildContext, PlaybackClockValue) builder;

  @override
  State<PlaybackClockBuilder> createState() => _PlaybackClockBuilderState();
}

class _PlaybackClockBuilderState extends State<PlaybackClockBuilder> {
  late PlaybackClockValue _value;
  PlaybackClockValue _read() {
    final preview = widget.previewPositionListenable.value;
    final totalMs = widget.totalDuration.inMilliseconds.clamp(0, 359999999);
    final position = Duration(
      milliseconds:
          (preview?.round() ?? widget.positionListenable.value.inMilliseconds)
              .clamp(0, totalMs),
    );
    return (
      elapsed: playbackClockLabel(position),
      total: playbackClockLabel(widget.totalDuration),
      remaining: playbackRemainingSeconds(position, widget.totalDuration),
    );
  }

  void _changed() {
    final next = _read();
    if (next != _value) setState(() => _value = next);
  }

  @override
  void initState() {
    super.initState();
    _value = _read();
    widget.positionListenable.addListener(_changed);
    widget.previewPositionListenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant PlaybackClockBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.positionListenable, widget.positionListenable)) {
      oldWidget.positionListenable.removeListener(_changed);
      widget.positionListenable.addListener(_changed);
    }
    if (!identical(
      oldWidget.previewPositionListenable,
      widget.previewPositionListenable,
    )) {
      oldWidget.previewPositionListenable.removeListener(_changed);
      widget.previewPositionListenable.addListener(_changed);
    }
    _value = _read();
  }

  @override
  void dispose() {
    widget.positionListenable.removeListener(_changed);
    widget.previewPositionListenable.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
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
    return PlaybackClockBuilder(
      positionListenable: positionListenable,
      previewPositionListenable: previewPositionListenable,
      totalDuration: totalDuration,
      builder: (context, clock) {
        final remainingSeconds = clock.remaining;
        final elapsedLabel = clock.elapsed;
        final totalLabel = clock.total;

        return Semantics(
          label: '已播放 $elapsedLabel，歌曲时长 $totalLabel，剩余 $remainingSeconds 秒',
          child: Opacity(
            opacity: .5,
            child: Text(
              '${remainingSeconds}s',
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        );
      },
    );
  }
}
