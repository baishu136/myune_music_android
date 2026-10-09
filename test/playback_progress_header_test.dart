import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/playback_progress_header.dart';

class _TrackedValueNotifier<T> extends ValueNotifier<T> {
  _TrackedValueNotifier(super.value);
  bool get hasActiveListeners => hasListeners;
}

void main() {
  testWidgets('clock text only rebuilds on visible changes and seek preview', (
    tester,
  ) async {
    final position = _TrackedValueNotifier(const Duration(seconds: 42));
    final preview = _TrackedValueNotifier<double?>(null);
    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PlaybackClockBuilder(
          positionListenable: position,
          previewPositionListenable: preview,
          totalDuration: const Duration(seconds: 174),
          builder: (_, clock) {
            builds++;
            return Text(clock.elapsed);
          },
        ),
      ),
    );
    expect(builds, 1);
    for (var ms = 42100; ms < 43000; ms += 100) {
      position.value = Duration(milliseconds: ms);
      await tester.pump();
    }
    expect(builds, 1);
    position.value = const Duration(seconds: 43);
    await tester.pump();
    expect(builds, 2);
    preview.value = 60000;
    await tester.pump();
    expect(find.text('1:00'), findsOneWidget);
    position.value = const Duration(seconds: 45);
    await tester.pump();
    expect(builds, 3);
    preview.value = null;
    await tester.pump();
    expect(find.text('0:45'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(position.hasActiveListeners, isFalse);
    expect(preview.hasActiveListeners, isFalse);
    position.dispose();
    preview.dispose();
  });
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
