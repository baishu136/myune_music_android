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
    expect(tester.getCenter(active).dy, inInclusiveRange(0, 220));
  });
}

class _LyricsHost extends StatefulWidget {
  const _LyricsHost({super.key});

  @override
  State<_LyricsHost> createState() => _LyricsHostState();
}

class _LyricsHostState extends State<_LyricsHost> {
  int active = 0;
  final lines = List.generate(
    50,
    (index) => LyricLine(
      timestamp: Duration(seconds: index),
      texts: ['第 ${index + 1} 行'],
    ),
  );

  void setActive(int value) => setState(() => active = value);

  @override
  Widget build(BuildContext context) =>
      MobileLyricsList(lines: lines, active: active);
}
