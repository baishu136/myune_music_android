import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:provider/provider.dart';
import '../statistics_page/statistics.dart';
import '../../widgets/single_line_lyrics.dart';
import '../../widgets/custom_theme_background.dart';
import '../../widgets/home_glass_surface.dart';
import '../../theme/home_background_policy.dart';
import '../playlist/playlist_content_notifier.dart';
import '../setting/settings_provider.dart';

class StatisticsPage extends StatelessWidget {
  const StatisticsPage({super.key, this.ranking});
  final StatisticsRanking? ranking;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final library = context.read<PlaylistContentNotifier>();
    final songPath = context.select<PlaylistContentNotifier, String?>(
      (value) => value.currentSong?.normalizedPath,
    );
    final background = homeBackgroundPolicy(
      settings,
      hasSong: songPath != null,
    );
    final theme = Theme.of(context);
    final scaffold = Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: background.hasBackground ? Colors.transparent : null,
        appBar: AppBar(
          title: const SingleLineLyricView(
            maxLinesPerLyric: 2,
            textAlign: TextAlign.left,
            alignment: Alignment.topLeft,
          ),
          backgroundColor: Colors.transparent,
          flexibleSpace: const HomePlaylistSurface(
            cornerRadius: 0,
            child: SizedBox.expand(),
          ),
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        body: Column(
          children: [
            const Divider(height: 1, thickness: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Statistics(
                  ranking: ranking,
                  backgroundEnabled: background.hasBackground,
                  onOpenRanking: (kind) => Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => StatisticsPage(ranking: kind),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    Widget withBackground() {
      final song = library.currentSong;
      return CustomThemeBackground(
        path: settings.homeThemeImagePath,
        enabled: background.customImage,
        dim: settings.homeThemeImageDim,
        blurSigma: settings.homeThemeImageBlur,
        coverEnabled: background.albumCover,
        coverBytes: !background.albumCover || song == null
            ? null
            : library.displayCoverForSong(song),
        coverDim: settings.homeAlbumArtBackgroundDim,
        coverBlurSigma: settings.homeAlbumArtBackgroundBlur,
        child: scaffold,
      );
    }

    return !background.albumCover || songPath == null
        ? withBackground()
        : AnimatedBuilder(
            animation: library.coverListenableForSongPath(songPath),
            builder: (_, _) => withBackground(),
          );
  }
}
