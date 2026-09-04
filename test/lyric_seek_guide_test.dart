import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/lyric_seek_guide.dart';

void main() {
  testWidgets('seek guide reaches the edge and moves time opposite alignment', (
    tester,
  ) async {
    Widget buildGuide({required bool timeOnLeft}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            key: const ValueKey('guide_bounds'),
            width: 360,
            height: 240,
            child: Stack(
              children: [
                LyricSeekGuide(
                  timeLabel: '1:23',
                  contentColor: Colors.white,
                  centerY: 120,
                  timeOnLeft: timeOnLeft,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(buildGuide(timeOnLeft: false));

    final bounds = tester.getRect(find.byKey(const ValueKey('guide_bounds')));
    final timeSlot = tester.getRect(
      find.byKey(const ValueKey('mobile_lyrics_progress_time_slot')),
    );
    final timeText = tester.getRect(
      find.byKey(const ValueKey('mobile_lyrics_progress_time')),
    );
    expect(bounds.right - timeSlot.right, closeTo(0, .01));
    expect(bounds.right - timeSlot.center.dx, closeTo(28, .01));
    expect(timeSlot.center.dy, closeTo(bounds.top + 120, .01));
    expect(timeText.center.dy, closeTo(bounds.top + 120, .01));
    expect(
      find.byKey(const ValueKey('mobile_lyrics_progress_line')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('mobile_lyrics_progress_seek')),
      findsNothing,
    );

    await tester.pumpWidget(buildGuide(timeOnLeft: true));

    final leftTimeBounds = tester.getRect(
      find.byKey(const ValueKey('guide_bounds')),
    );
    final leftTimeSlot = tester.getRect(
      find.byKey(const ValueKey('mobile_lyrics_progress_time_slot')),
    );
    expect(leftTimeSlot.left - leftTimeBounds.left, closeTo(0, .01));
  });
}
