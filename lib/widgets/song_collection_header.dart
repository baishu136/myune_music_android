import 'dart:math' as math;
import 'package:flutter/material.dart';

class SongCollectionHeader extends StatelessWidget {
  const SongCollectionHeader({
    super.key,
    required this.title,
    required this.songCount,
    required this.playCount,
    required this.artwork,
    this.onPlayAll,
    this.featured = false,
  });

  final String title;
  final int songCount, playCount;
  final Widget artwork;
  final VoidCallback? onPlayAll;
  final bool featured;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            !featured &&
            (constraints.maxWidth < 330 ||
                MediaQuery.textScalerOf(context).scale(14) > 23);
        final cover = ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox.square(
            dimension: math.min(
              featured ? 136.0 : 208.0,
              constraints.maxWidth * (featured ? .38 : .44),
            ),
            child: artwork,
          ),
        );
        final metadata = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: featured ? 2 : 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 6,
              children: [
                if (onPlayAll != null)
                  IconButton.filledTonal(
                    tooltip: '播放全部',
                    onPressed: onPlayAll,
                    icon: const Icon(Icons.play_arrow_rounded),
                    iconSize: 30,
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('共 $songCount 首歌曲'),
                    Text('已收听 $playCount 次'),
                  ],
                ),
              ],
            ),
          ],
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [cover, const SizedBox(height: 14), metadata],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            cover,
            const SizedBox(width: 16),
            Expanded(child: metadata),
          ],
        );
      },
    ),
  );
}
