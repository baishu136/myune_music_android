import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';
import 'package:myune_music/widgets/lyric_plain_foreground.dart';

void main() {
  testWidgets('ordinary focus colors retain the shaped paragraphs', (
    tester,
  ) async {
    var active = 3;
    late StateSetter update;
    final lines = List.generate(
      20,
      (i) => LyricLine(
        timestamp: Duration(seconds: i * 3),
        texts: ['连续滚动 office ygp 中文 $i', 'Translation $i'],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return MobileLyricsList(
                lines: lines,
                active: active,
                fontSize: 32,
                karaokeLyricsEnabled: false,
                highlightActiveLine: true,
                lineBlurEnabled: true,
                glowEnabled: true,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    update(() => active = 4);
    await tester.pump();
    final row = find.byKey(const ValueKey('mobile_lyric_4'));
    final finder = find.descendant(of: row, matching: find.byType(RichText));
    final paragraph = tester.renderObject<RenderParagraph>(finder);
    final shapedText = paragraph.text;
    final colorAtStart = DefaultTextStyle.of(
      tester.element(find.text(lines[4].texts.join('\n'))),
    ).style.color!;
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        paragraph.text,
        same(shapedText),
        reason:
            'a color-only focus tick must not rebuild native paragraphs: '
            '${shapedText.compareTo(paragraph.text)}; '
            'style ${(shapedText as TextSpan).style?.compareTo((paragraph.text as TextSpan).style!)}',
      );
      final foreground = tester.widget<Opacity>(
        find.descendant(
          of: row,
          matching: find.byKey(
            const ValueKey('mobile_lyric_foreground_opacity'),
          ),
        ),
      );
      expect(
        foreground.opacity,
        DefaultTextStyle.of(
          tester.element(find.text(lines[4].texts.join('\n'))),
        ).style.color!.a,
      );
    }
    final colorDuring = DefaultTextStyle.of(
      tester.element(find.text(lines[4].texts.join('\n'))),
    ).style.color!;
    expect(colorDuring.a, greaterThan(colorAtStart.a));
    expect(colorDuring.a, lessThan(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('foreground tint preserves text and separate glow pixels', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await (FontLoader(
        'Ink398',
      )..addFont(rootBundle.load('assets/fonts/MiSansVF.ttf'))).load();
    });
    Future<List<int>> pixels(
      String text,
      Color color,
      double sigma,
      double dpr,
      bool retained,
    ) async {
      final key = GlobalKey();
      final style = TextStyle(
        fontFamily: 'Ink398',
        fontSize: 27,
        fontWeight: FontWeight.w800,
        height: 1.2,
        letterSpacing: .3,
        color: color,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 260,
                height: 180,
                child: ColoredBox(
                  color: const Color(0xff163044),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Transform.translate(
                      offset: const Offset(.25, .5),
                      child: DefaultTextStyle(
                        style: style,
                        child: ImageFiltered(
                          enabled: sigma > 0,
                          imageFilter: ui.ImageFilter.blur(
                            sigmaX: sigma,
                            sigmaY: sigma,
                          ),
                          child: Stack(
                            fit: StackFit.passthrough,
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: Opacity(
                                  opacity: .4,
                                  child: Text(
                                    text,
                                    style: style.copyWith(
                                      color: Colors.transparent,
                                      shadows: [
                                        Shadow(
                                          color: color.withValues(alpha: .3),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              retained
                                  ? LyricPlainForeground(
                                      text: text,
                                      textAlign: TextAlign.left,
                                    )
                                  : Text(text, textAlign: TextAlign.left),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      late List<int> result;
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: dpr);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        result = data!.buffer.asUint8List().toList();
        image.dispose();
      });
      return result;
    }

    for (final text in [
      'office ygp AVffi\n中文轻轻滚动',
      'A\u0301\u0327 y\u0308\n折行的翻译歌词',
      'سلام हिन्दी',
    ]) {
      for (final color in [
        Colors.white.withValues(alpha: .15),
        Colors.white.withValues(alpha: .4),
        const Color(0xffeb6fa9).withValues(alpha: .73),
        const Color(0xff757575),
      ]) {
        for (final sigma in [0.0, 1.2]) {
          final expected = await pixels(text, color, sigma, 2, false);
          final actual = await pixels(text, color, sigma, 2, true);
          var sum = 0, maxError = 0;
          for (var i = 0; i < actual.length; i++) {
            final error = (actual[i] - expected[i]).abs();
            sum += error;
            if (error > maxError) maxError = error;
          }
          expect(
            sum / actual.length,
            lessThan(.25),
            reason: '$text / $color / $sigma',
          );
          expect(
            maxError,
            lessThanOrEqualTo(3),
            reason: '$text / $color / $sigma',
          );
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('native color glyphs and decorated text keep native painting', (
    tester,
  ) async {
    for (final entry in [
      ('彩色 😀 ❤️ 👩‍🎤', const TextStyle(color: Colors.pink)),
      (
        'underlined',
        const TextStyle(
          color: Colors.blue,
          decoration: TextDecoration.underline,
        ),
      ),
      (
        'shadow',
        const TextStyle(color: Colors.orange, shadows: [Shadow(blurRadius: 4)]),
      ),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTextStyle(
            style: entry.$2,
            child: LyricPlainForeground(
              text: entry.$1,
              textAlign: TextAlign.left,
            ),
          ),
        ),
      );
      expect(find.byType(ColorFiltered), findsNothing);
      expect(find.byType(Opacity), findsNothing);
      expect(find.text(entry.$1), findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byType(RichText),
      );
      expect((paragraph.text as TextSpan).style!.color, entry.$2.color);
    }
  });
}
