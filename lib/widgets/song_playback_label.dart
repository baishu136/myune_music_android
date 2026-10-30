import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../page/playlist/playlist_content_notifier.dart';
import '../theme/home_theme_scope.dart';

Color songPlaybackAccent(ThemeData theme) =>
    theme.extension<HomePlaybackAccent>()?.color ?? theme.colorScheme.primary;

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
      final accent = songPlaybackAccent(theme);
      final base = DefaultTextStyle.of(context).style.merge(style);
      return TweenAnimationBuilder<Color?>(
        key: ValueKey(songPath),
        // Other inherited text attributes must not restart the colour tween.
        tween: ColorTween(end: current ? accent : base.color),
        duration: (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
            ? Duration.zero
            : const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        builder: (context, colour, child) => DefaultTextStyle.merge(
          style: base.copyWith(color: colour),
          child: child!,
        ),
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
    },
  );
}
