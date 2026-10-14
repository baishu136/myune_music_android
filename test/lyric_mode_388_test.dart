import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/services/lyric_content.dart';

void main() {
  test(
    'ALL does not estimate network LRC, while local ALL and real word timing remain supported',
    () {
      final local = LyricLine(timestamp: Duration.zero, texts: ['歌词']);
      final network = local.withSyntheticKaraoke(false);
      expect(
        canAnimateLyricLine(network, true, KaraokeLyricsMode.all),
        isFalse,
      );
      expect(canAnimateLyricLine(local, true, KaraokeLyricsMode.all), isTrue);
      expect(
        canAnimateLyricLine(local, true, KaraokeLyricsMode.timedOnly),
        isFalse,
      );
      final timed = LyricLine(
        timestamp: Duration.zero,
        texts: ['歌词'],
        allowSyntheticKaraoke: false,
        tokens: [
          [
            LyricToken(
              text: '歌',
              start: Duration.zero,
              end: const Duration(seconds: 1),
            ),
          ],
        ],
      );
      expect(
        canAnimateLyricLine(timed, true, KaraokeLyricsMode.timedOnly),
        isTrue,
      );
      expect(canAnimateLyricLine(timed, false, KaraokeLyricsMode.all), isFalse);
    },
  );
  test(
    'semantic equality retains repeat results but detects timing and source-policy updates',
    () {
      LyricLine line(int end) => LyricLine(
        timestamp: Duration.zero,
        texts: ['词', '翻译'],
        tokens: [
          [
            LyricToken(
              text: '词',
              start: Duration.zero,
              end: Duration(milliseconds: end),
            ),
          ],
        ],
        allowSyntheticKaraoke: false,
      );
      expect(sameLyricContent([line(100)], [line(100)]), isTrue);
      expect(sameLyricContent([line(100)], [line(101)]), isFalse);
      expect(
        sameLyricContent([line(100)], [line(100).withSyntheticKaraoke(true)]),
        isFalse,
      );
    },
  );
  test('whitespace-only or backwards timing is not usable word timing', () {
    expect(
      hasUsableKaraokeTiming(
        LyricLine(
          timestamp: Duration.zero,
          texts: ['words'],
          tokens: [
            [
              LyricToken(
                text: ' ',
                start: Duration.zero,
                end: const Duration(seconds: 1),
              ),
            ],
          ],
        ),
      ),
      isFalse,
    );
    expect(
      hasUsableKaraokeTiming(
        LyricLine(
          timestamp: Duration.zero,
          texts: ['ab'],
          tokens: [
            [
              LyricToken(
                text: 'a',
                start: const Duration(seconds: 2),
                end: const Duration(seconds: 3),
              ),
              LyricToken(
                text: 'b',
                start: const Duration(seconds: 2),
                end: const Duration(seconds: 1),
              ),
            ],
          ],
        ),
      ),
      isFalse,
    );
  });
  testWidgets(
    'plain fallback keeps full playing-line highlight with karaoke switch enabled',
    (tester) async {
      final lines = List.generate(
        5,
        (i) => LyricLine(
          timestamp: Duration(seconds: i * 4),
          texts: ['普通歌词$i'],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 500,
            child: MobileLyricsList(
              lines: lines,
              active: 2,
              position: const Duration(seconds: 9),
              activeColor: Colors.green,
              brightForeground: true,
              karaokeLyricsEnabled: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final active = find.text('普通歌词2');
      expect(active, findsOneWidget);
      final style = tester
          .widget<AnimatedDefaultTextStyle>(
            find
                .ancestor(
                  of: active,
                  matching: find.byWidgetPredicate(
                    (w) => w is AnimatedDefaultTextStyle,
                  ),
                )
                .first,
          )
          .style;
      expect(style.color!.toARGB32(), Colors.green.toARGB32());
      final inactive = find.text('普通歌词1');
      final dim = tester
          .widget<AnimatedDefaultTextStyle>(
            find
                .ancestor(
                  of: inactive,
                  matching: find.byWidgetPredicate(
                    (w) => w is AnimatedDefaultTextStyle,
                  ),
                )
                .first,
          )
          .style
          .color!;
      expect(dim.a, closeTo(.40, .003));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
