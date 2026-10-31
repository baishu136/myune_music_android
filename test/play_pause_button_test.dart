import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/play_pause_button.dart';

void main() {
  testWidgets('press feedback keeps the hit area and does not delay playback', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayPauseButton(
            isPlaying: false,
            onPressed: () => calls++,
            color: Colors.black,
          ),
        ),
      ),
    );
    final before = tester.getRect(find.byType(IconButton));
    final layoutSize = tester.getSize(find.byType(IconButton));
    final pointer = await tester.startGesture(before.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final feedback = find.byKey(const ValueKey('button-press-transform'));
    expect(feedback, findsOneWidget);
    expect(
      tester.widget<Transform>(feedback).transform.storage[0],
      lessThan(1),
    );
    expect(tester.getSize(find.byType(IconButton)), layoutSize);
    expect(tester.widget<Transform>(feedback).transformHitTests, isFalse);
    await pointer.up();
    expect(calls, 1);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Transform>(feedback).transform.storage[0],
      closeTo(1, .001),
    );
  });
  testWidgets(
    'reduced motion changes the icon immediately without running a ticker',
    (tester) async {
      var playing = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: PlayPauseButton(
                  isPlaying: playing,
                  onPressed: () {},
                  color: Colors.black,
                ),
              );
            },
          ),
        ),
      );
      update(() => playing = true);
      await tester.pump();
      expect(
        tester.widget<AnimatedIcon>(find.byType(AnimatedIcon)).progress.value,
        1,
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );
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
    expect(
      tester
          .widget<Transform>(find.byKey(const ValueKey('play_pause_rotation')))
          .transform
          .getRotation(),
      isNot(0),
    );

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
