import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/theme/home_theme_scope.dart';
import 'package:myune_music/widgets/song_playback_label.dart';
import 'package:provider/provider.dart';

class _Player extends ChangeNotifier implements PlaylistContentNotifier {
  Song? song;
  @override
  Song? get currentSong => song;
  void change(Song? value) {
    song = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'playing labels follow tracks and preserve the real theme accent',
    (tester) async {
      final player = _Player();
      final songs = List.generate(
        3,
        (i) => Song(title: '歌曲$i', artist: '歌手$i', filePath: '/music/$i.flac'),
      );
      for (final brightness in Brightness.values) {
        final source = ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.pink,
            brightness: brightness,
          ),
        );
        final home = neutralHomeTheme(source);
        await tester.pumpWidget(
          ChangeNotifierProvider<PlaylistContentNotifier>.value(
            value: player,
            child: MaterialApp(
              theme: home,
              home: Scaffold(
                body: Column(
                  children: [
                    for (final song in songs)
                      SongPlaybackLabel(
                        songPath: song.normalizedPath,
                        text: song.title,
                        style: home.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        player.change(songs[0]);
        await tester.pump();
        Text label(int i) => tester.widget<Text>(find.text('歌曲$i'));
        expect(label(0).style!.color, source.colorScheme.primary);
        expect(label(1).style!.color, home.textTheme.bodySmall!.color);
        final untouched = tester.element(find.text('歌曲2')).widget;
        player.change(songs[1]);
        await tester.pump();
        expect(label(0).style!.color, home.textTheme.bodySmall!.color);
        expect(label(1).style!.color, source.colorScheme.primary);
        expect(
          identical(tester.element(find.text('歌曲2')).widget, untouched),
          isTrue,
        );
        player.change(null);
        await tester.pump();
        expect(label(1).style!.color, home.textTheme.bodySmall!.color);
      }
      await tester.pumpWidget(const SizedBox());
      player.dispose();
    },
  );
}
