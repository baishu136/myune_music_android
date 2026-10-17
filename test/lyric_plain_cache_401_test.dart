import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';

void main() {
  testWidgets(
    'colored ordinary surrounding rows reuse native RGB across alpha changes',
    (tester) async {
      var active = 2;
      late StateSetter update;
      final lines = List.generate(
        20,
        (i) => LyricLine(
          timestamp: Duration(seconds: i * 3),
          texts: ['彩色 office 中文 $i', 'Translation $i'],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return MobileLyricsList(
                  lines: lines,
                  active: active,
                  fontSize: 32,
                  activeColor: Colors.pink,
                  highlightActiveLine: false,
                  lineBlurEnabled: true,
                  glowEnabled: true,
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      update(() => active = 3);
      await tester.pump();
      final finder = find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_4')),
        matching: find.byType(RichText),
      );
      final paragraph = tester.renderObject<RenderParagraph>(finder);
      final shaped = paragraph.text;
      double opacity() => tester
          .widget<Opacity>(
            find.descendant(
              of: find.byKey(const ValueKey('mobile_lyric_4')),
              matching: find.byKey(
                const ValueKey('mobile_lyric_foreground_opacity'),
              ),
            ),
          )
          .opacity;
      final before = opacity();
      // Shared long-row focus now ends with the list at up to 680ms.
      for (var i = 0; i < 45; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(paragraph.text, same(shaped));
      }
      expect(opacity(), greaterThan(before));
      expect(opacity(), closeTo(.4, 1e-8));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
