import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/play_pause_button.dart';

void main() {
  testWidgets('morphs smoothly between play and pause', (tester) async {
    final key = GlobalKey<_PlayPauseHostState>();
    await tester.pumpWidget(MaterialApp(home: _PlayPauseHost(key: key)));

    expect(
      tester.widget<AnimatedIcon>(find.byType(AnimatedIcon)).progress.value,
      0,
    );

    key.currentState!.setPlaying(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    final middle = tester
        .widget<AnimatedIcon>(find.byType(AnimatedIcon))
        .progress
        .value;
    expect(middle, greaterThan(0));
    expect(middle, lessThan(1));

    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedIcon>(find.byType(AnimatedIcon)).progress.value,
      1,
    );
  });
}

class _PlayPauseHost extends StatefulWidget {
  const _PlayPauseHost({super.key});

  @override
  State<_PlayPauseHost> createState() => _PlayPauseHostState();
}

class _PlayPauseHostState extends State<_PlayPauseHost> {
  bool playing = false;

  void setPlaying(bool value) => setState(() => playing = value);

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PlayPauseButton(
      isPlaying: playing,
      onPressed: () => setPlaying(!playing),
      color: Colors.black,
      backgroundColor: Colors.white,
    ),
  );
}
