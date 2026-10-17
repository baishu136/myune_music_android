import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';
import 'package:myune_music/widgets/lyric_scroll_motion.dart';

void main() {
  testWidgets(
    'ALL creates a cached timed painter for network LRC; turning it off restores stable plain rows',
    (tester) async {
      final position = ValueNotifier(const Duration(milliseconds: 800));
      final lines = List.generate(
        6,
        (i) => LyricLine(
          timestamp: Duration(seconds: i * 3),
          texts: ['网络歌词 English $i'],
          allowSyntheticKaraoke: false,
        ),
      );
      Widget host(bool karaoke) => MaterialApp(
        home: SizedBox(
          width: 400,
          height: 500,
          child: MobileLyricsList(
            lines: lines,
            active: 0,
            contentIdentity: 'same-song',
            position: position.value,
            positionListenable: position,
            karaokeLyricsEnabled: karaoke,
            karaokeLyricsMode: KaraokeLyricsMode.all,
            isPlaying: false,
          ),
        ),
      );
      await tester.pumpWidget(host(true));
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('mobile_lyric_0'));
      expect(
        find.descendant(
          of: row,
          matching: find.byKey(
            const ValueKey('mobile_karaoke_single_pass_paint'),
          ),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(host(false));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: row,
          matching: find.byKey(
            const ValueKey('mobile_karaoke_single_pass_paint'),
          ),
        ),
        findsNothing,
      );
      final ink = find.descendant(of: row, matching: find.byType(RichText));
      final paragraph = tester.renderObject<RenderParagraph>(ink);
      final rect = tester.getRect(ink), text = paragraph.text;
      for (var i = 0; i < 24; i++) {
        position.value += const Duration(milliseconds: 16);
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getRect(ink), rect);
        expect(paragraph.text, same(text));
      }
      await tester.pumpWidget(const SizedBox());
      position.dispose();
    },
  );
  for (final hz in [60, 90, 120]) {
    test(
      'plain settling at $hz Hz retains velocity at redirection and has no threshold jump',
      () {
        final motion = LyricScrollMotion(frequency: 8.8, dampingRatio: .9)
          ..retarget(180);
        for (var i = 0; i < hz * 3 && !motion.isSettled; i++) {
          final before = motion.offset, velocity = motion.velocity;
          final after = motion.advance(1 / hz);
          if ((180 - before).abs() < .35 && velocity.abs() < 1.2) {
            expect((after - before).abs(), lessThan(.09));
          }
        }
        expect(motion.offset, 180);
        expect(motion.velocity, 0);
        motion.retarget(180.3);
        motion.advance(.02);
        final offset = motion.offset, velocity = motion.velocity;
        motion.retarget(250);
        expect(motion.offset, offset);
        expect(motion.velocity, velocity);
        expect(motion.advance(1 / hz), greaterThan(offset));
      },
    );
  }
  test(
    'explicit ALL estimates ordinary network lyrics, timed-only does not',
    () {
      final line = LyricLine(
        timestamp: Duration.zero,
        texts: ['普通网络歌词'],
        allowSyntheticKaraoke: false,
      );
      expect(canAnimateLyricLine(line, true, KaraokeLyricsMode.all), isTrue);
      expect(
        canAnimateLyricLine(line, true, KaraokeLyricsMode.timedOnly),
        isFalse,
      );
      expect(canAnimateLyricLine(line, false, KaraokeLyricsMode.all), isFalse);
    },
  );
  test(
    'subpixel settling is a continuous move rather than an immediate snap',
    () {
      final motion = LyricScrollMotion(frequency: 8.8, dampingRatio: .9)
        ..retarget(.3);
      expect(motion.isSettled, isFalse);
      final first = motion.advance(1 / 120);
      expect(first, inExclusiveRange(0, .3));
      expect(motion.velocity, greaterThan(0));
      for (var i = 0; i < 20; i++) {
        motion.advance(1 / 120);
      }
      expect(motion.offset, .3);
      expect(motion.velocity, 0);
      expect(motion.isSettled, isTrue);
    },
  );
}
