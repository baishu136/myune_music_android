import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  testWidgets('active lyric automatically scrolls into the visible area', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mobile_lyric_0')), findsOneWidget);

    hostKey.currentState!.setActive(35);
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('mobile_lyric_35'));
    expect(active, findsOneWidget);
    expect(tester.getCenter(active).dy, closeTo(110, 24));

    hostKey.currentState!.setActive(49);
    await tester.pumpAndSettle();

    final finalLine = find.byKey(const ValueKey('mobile_lyric_49'));
    expect(finalLine, findsOneWidget);
    expect(tester.getCenter(finalLine).dy, closeTo(110, 24));
  });

  testWidgets('uses the configured lyric font size', (tester) async {
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['当前歌词']),
      LyricLine(timestamp: const Duration(seconds: 1), texts: const ['下一行']),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileLyricsList(lines: lines, active: 0, fontSize: 26),
        ),
      ),
    );

    final activeStyle = tester.widget<AnimatedDefaultTextStyle>(
      find
          .ancestor(
            of: find.text('当前歌词'),
            matching: find.byType(AnimatedDefaultTextStyle),
          )
          .first,
    );
    final inactiveStyle = tester.widget<AnimatedDefaultTextStyle>(
      find
          .ancestor(
            of: find.text('下一行'),
            matching: find.byType(AnimatedDefaultTextStyle),
          )
          .first,
    );
    expect(activeStyle.style.fontSize, 26);
    expect(inactiveStyle.style.fontSize, closeTo(21.84, 0.001));
  });

  testWidgets('keeps the active lyric centered while font size changes', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(25);
    await tester.pumpAndSettle();

    hostKey.currentState!.setFontSize(32);
    await tester.pumpAndSettle();
    final enlarged = find.byKey(const ValueKey('mobile_lyric_25'));
    expect(tester.getCenter(enlarged).dy, closeTo(110, 18));

    hostKey.currentState!.setFontSize(12);
    await tester.pumpAndSettle();
    final reduced = find.byKey(const ValueKey('mobile_lyric_25'));
    expect(tester.getCenter(reduced).dy, closeTo(110, 18));
  });

  testWidgets('applies the selected font family to lyrics', (tester) async {
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['自定义字体歌词']),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileLyricsList(
            lines: lines,
            active: 0,
            fontFamily: 'TestLyricsFont',
          ),
        ),
      ),
    );

    final style = tester.widget<AnimatedDefaultTextStyle>(
      find
          .ancestor(
            of: find.text('自定义字体歌词'),
            matching: find.byType(AnimatedDefaultTextStyle),
          )
          .first,
    );
    expect(style.style.fontFamily, 'TestLyricsFont');
  });

  testWidgets('manual lyric browsing resumes follow after six idle seconds', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(20);
    await tester.pumpAndSettle();

    await tester.drag(
      find.byType(ScrollablePositionedList),
      const Offset(0, -140),
    );
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    hostKey.currentState!.setActive(40);
    await tester.pump();

    final active = find.byKey(const ValueKey('mobile_lyric_40'));
    expect(active, findsNothing);

    await tester.pump(const Duration(seconds: 5));
    expect(active, findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(active, findsOneWidget);
    expect(tester.getCenter(active).dy, closeTo(110, 24));
  });

  testWidgets('controller recenters the active lyric immediately', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(25);
    await tester.pumpAndSettle();

    await tester.drag(
      find.byType(ScrollablePositionedList),
      const Offset(0, -160),
    );
    await tester.pump(const Duration(milliseconds: 300));

    hostKey.currentState!.recenter();
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('mobile_lyric_25'));
    expect(active, findsOneWidget);
    expect(tester.getCenter(active).dy, closeTo(110, 24));
  });

  testWidgets('edge fade is opt-in', (tester) async {
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['第一行']),
      LyricLine(timestamp: const Duration(seconds: 1), texts: const ['第二行']),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MobileLyricsList(lines: lines, active: 0)),
      ),
    );
    expect(find.byKey(const ValueKey('mobile_lyrics_edge_fade')), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileLyricsList(
            lines: lines,
            active: 0,
            edgeFadeEnabled: true,
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('mobile_lyrics_edge_fade')),
      findsOneWidget,
    );
    final fade = tester.widget<ShaderMask>(
      find.byKey(const ValueKey('mobile_lyrics_edge_fade')),
    );
    expect(fade.blendMode, BlendMode.dstIn);
  });

  testWidgets('karaoke lyric colors played and unplayed text separately', (
    tester,
  ) async {
    final line = LyricLine(
      timestamp: Duration.zero,
      texts: const ['Hello世界'],
      tokens: [
        [
          LyricToken(
            text: 'Hello',
            start: Duration.zero,
            end: const Duration(seconds: 1),
          ),
          LyricToken(
            text: '世界',
            start: const Duration(seconds: 1),
            end: const Duration(seconds: 2),
          ),
        ],
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: MobileLyricsList(
            lines: [line],
            active: 0,
            position: const Duration(milliseconds: 500),
          ),
        ),
      ),
    );

    final richText = tester.widget<Text>(
      find
          .descendant(
            of: find.byKey(const ValueKey('mobile_lyric_0')),
            matching: find.byType(Text),
          )
          .last,
    );
    final spans = (richText.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.map((span) => span.text).join(), 'Hello世界');
    expect(spans.first.style!.color, isNot(spans.last.style!.color));
    expect(spans.last.style!.color, Colors.white.withValues(alpha: .5));
  });
}

class _LyricsHost extends StatefulWidget {
  const _LyricsHost({super.key});

  @override
  State<_LyricsHost> createState() => _LyricsHostState();
}

class _LyricsHostState extends State<_LyricsHost> {
  int active = 0;
  double fontSize = 20;
  final controller = MobileLyricsListController();
  final lines = List.generate(
    50,
    (index) => LyricLine(
      timestamp: Duration(seconds: index),
      texts: ['第 ${index + 1} 行'],
    ),
  );

  void setActive(int value) => setState(() => active = value);

  void setFontSize(double value) => setState(() => fontSize = value);

  void recenter() => controller.recenter();

  @override
  Widget build(BuildContext context) => MobileLyricsList(
    controller: controller,
    lines: lines,
    active: active,
    fontSize: fontSize,
  );
}
