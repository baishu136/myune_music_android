import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';

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
}

class _LyricsHost extends StatefulWidget {
  const _LyricsHost({super.key});

  @override
  State<_LyricsHost> createState() => _LyricsHostState();
}

class _LyricsHostState extends State<_LyricsHost> {
  int active = 0;
  double fontSize = 20;
  final lines = List.generate(
    50,
    (index) => LyricLine(
      timestamp: Duration(seconds: index),
      texts: ['第 ${index + 1} 行'],
    ),
  );

  void setActive(int value) => setState(() => active = value);

  void setFontSize(double value) => setState(() => fontSize = value);

  @override
  Widget build(BuildContext context) =>
      MobileLyricsList(lines: lines, active: active, fontSize: fontSize);
}
