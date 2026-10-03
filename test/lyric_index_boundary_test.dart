import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';

void main() {
  for (final karaoke in [false, true]) {
    for (final interlude in [false, true]) {
      testWidgets(
        'first boundary survives no-current index (karaoke=$karaoke, dots=$interlude)',
        (tester) async {
          var active = -1;
          late StateSetter update;
          final lines = [
            LyricLine(
              timestamp: const Duration(seconds: 3),
              texts: [interlude ? '' : '第一句歌词'],
              isInterlude: interlude,
              interludeDuration: interlude ? const Duration(seconds: 2) : null,
            ),
            LyricLine(timestamp: const Duration(seconds: 5), texts: ['下一句']),
          ];
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  height: 360,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: StatefulBuilder(
                      builder: (context, setState) {
                        update = setState;
                        return MobileLyricsList(
                          lines: lines,
                          active: active,
                          isPlaying: true,
                          position: Duration(
                            seconds: active < 0 ? 0 : 3 + active * 2,
                          ),
                          karaokeLyricsEnabled: karaoke,
                          karaokeLyricsMode: KaraokeLyricsMode.all,
                          lineBlurEnabled: true,
                          edgeFadeEnabled: true,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          // The player's binary search emits -1 before the first timestamp,
          // including after a backward seek. Reuse the exact same lyric list.
          for (final index in [0, 1, -1, 0, 1]) {
            update(() => active = index);
            await tester.pump();
            expect(tester.takeException(), isNull);
            expect(find.byType(ErrorWidget), findsNothing);
            for (var frame = 0; frame < 32; frame++) {
              await tester.pump(const Duration(microseconds: 16667));
              expect(tester.takeException(), isNull);
            }
            expect(
              find.byKey(ValueKey('mobile_lyric_${index < 0 ? 0 : index}')),
              findsOneWidget,
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
