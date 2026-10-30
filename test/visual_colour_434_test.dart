import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
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
  test('fluid saturation gains another ten percent over the current boost', () {
    for (final saturation in [.08, .3, .6, .95]) {
      final original = HSLColor.fromAHSL(1, 205, saturation, .43).toColor();
      final before = HSLColor.fromColor(original);
      final after = HSLColor.fromColor(fluidSaturationBoost(original));
      expect(
        after.saturation,
        closeTo(math.min(1, before.saturation * 1.21), .006),
      );
      expect(after.lightness, closeTo(before.lightness, .004));
      expect(
        fluidSaturationBoost(original),
        before.withSaturation(math.min(1, before.saturation * 1.21)).toColor(),
      );
    }
    for (final neutral in [Colors.black, Colors.white, Colors.grey]) {
      expect(fluidSaturationBoost(neutral), neutral);
    }
  });

  const neutral = Color(0xffa0a0a0),
      blue = Color(0xff4285df),
      red = Color(0xffdf4268);
  final songs = List.generate(
    2,
    (i) => Song(title: '歌曲$i', artist: '歌手$i', filePath: '/song/$i.flac'),
  );
  Widget host(_Player player, Color accent, {bool reduced = false}) =>
      ChangeNotifierProvider<PlaylistContentNotifier>.value(
        value: player,
        child: MaterialApp(
          themeAnimationDuration: Duration.zero,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: accent,
            ).copyWith(primary: accent),
          ),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: Scaffold(
              body: Column(
                children: [
                  for (final song in songs)
                    SongPlaybackLabel(
                      songPath: song.normalizedPath,
                      text: song.title,
                      style: const TextStyle(color: neutral, fontSize: 18),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
  Color colour(WidgetTester tester, int index) {
    final finder = find.text('歌曲$index');
    final text = tester.widget<Text>(finder);
    return text.style?.color ??
        DefaultTextStyle.of(tester.element(finder)).style.color!;
  }

  testWidgets(
    'old and new song labels use a short continuous colour transition',
    (tester) async {
      final player = _Player()..song = songs[0];
      await tester.pumpWidget(host(player, blue));
      await tester.pumpAndSettle();
      player.change(songs[1]);
      await tester.pump();
      expect(colour(tester, 1), neutral);
      await tester.pump(const Duration(milliseconds: 40));
      expect(colour(tester, 1), isNot(neutral));
      expect(colour(tester, 1), isNot(blue));
      await tester.pump(const Duration(milliseconds: 110));
      expect(colour(tester, 1), blue);
      expect(colour(tester, 0), neutral);
      await tester.pumpWidget(const SizedBox());
      player.dispose();
    },
  );

  testWidgets(
    'latest colour continues from the visible colour and unrelated notifications cannot restart it',
    (tester) async {
      final player = _Player()..song = songs[0];
      await tester.pumpWidget(host(player, blue));
      await tester.pumpAndSettle();
      player.change(songs[1]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final visible = colour(tester, 1);
      await tester.pumpWidget(host(player, red));
      expect(colour(tester, 1), visible);
      for (var i = 0; i < 15; i++) {
        player.change(songs[1]);
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(colour(tester, 1), red);
      expect(colour(tester, 0), neutral);
      await tester.pumpWidget(const SizedBox());
      player.dispose();
    },
  );

  testWidgets('reduced animation reaches the current accent immediately', (
    tester,
  ) async {
    final player = _Player()..song = songs[0];
    await tester.pumpWidget(host(player, blue, reduced: true));
    player.change(songs[1]);
    await tester.pump();
    expect(colour(tester, 1), blue);
    expect(colour(tester, 0), neutral);
    await tester.pumpWidget(const SizedBox());
    player.dispose();
  });
}
