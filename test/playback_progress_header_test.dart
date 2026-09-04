import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/playback_progress_header.dart';

void main() {
  test('playback progress values clamp and format consistently', () {
    expect(playbackClockLabel(const Duration(seconds: 42)), '0:42');
    expect(playbackClockLabel(const Duration(seconds: 174)), '2:54');
    expect(
      playbackRemainingSeconds(
        const Duration(milliseconds: 42900),
        const Duration(seconds: 174),
      ),
      132,
    );
    expect(
      playbackRemainingSeconds(
        const Duration(seconds: 200),
        const Duration(seconds: 174),
      ),
      0,
    );
  });

  testWidgets('header follows playback and seek-preview positions', (
    tester,
  ) async {
    final position = ValueNotifier(const Duration(seconds: 42));
    final preview = ValueNotifier<double?>(null);
    addTearDown(position.dispose);
    addTearDown(preview.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: PlaybackProgressHeader(
              positionListenable: position,
              previewPositionListenable: preview,
              totalDuration: const Duration(seconds: 174),
            ),
          ),
        ),
      ),
    );

    expect(find.text('0:42'), findsNothing);
    expect(find.text('2:54'), findsNothing);
    expect(find.text('132s'), findsOneWidget);
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, .5);

    preview.value = const Duration(seconds: 60).inMilliseconds.toDouble();
    await tester.pump();

    expect(find.text('1:00'), findsNothing);
    expect(find.text('114s'), findsOneWidget);
  });
}
