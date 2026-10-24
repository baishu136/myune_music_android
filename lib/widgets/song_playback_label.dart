import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../page/playlist/playlist_content_notifier.dart';
import '../theme/home_theme_scope.dart';

/// Only the old and new playing rows rebuild when the track changes.
class SongPlaybackLabel extends StatelessWidget {
  const SongPlaybackLabel({
    super.key,
    required this.songPath,
    required this.text,
    this.style,
  });

  final String songPath;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Selector<PlaylistContentNotifier, bool>(
    selector: (_, player) => player.currentSong?.normalizedPath == songPath,
    builder: (context, current, _) {
      final theme = Theme.of(context);
      final accent =
          theme.extension<HomePlaybackAccent>()?.color ??
          theme.colorScheme.primary;
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: current
            ? (style ?? const TextStyle()).copyWith(color: accent)
            : style,
      );
    },
  );
}
