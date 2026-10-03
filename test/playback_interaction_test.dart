import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/fullscreen_lyrics_double_tap.dart';
import 'package:myune_music/widgets/playback_jump_feedback.dart';

void main() {
  testWidgets(
    'fullscreen double tap toggles without exiting; single tap returns',
    (tester) async {
      var singles = 0, doubles = 0, drags = 0;
      final enabled = ValueNotifier(true);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: enabled,
            builder: (_, value, _) => GestureDetector(
              onTap: () => singles++,
              child: FullscreenLyricsDoubleTap(
                enabled: value,
                onTogglePlayback: () => doubles++,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (_) => drags++,
                  child: const ColoredBox(
                    color: Colors.black,
                    key: ValueKey('surface'),
                    child: SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('surface')));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.byKey(const ValueKey('surface')));
      await tester.pumpAndSettle();
      expect(doubles, 1);
      expect(singles, 0);
      await tester.tap(find.byKey(const ValueKey('surface')));
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(singles, 1);
      await tester.drag(
        find.byKey(const ValueKey('surface')),
        const Offset(0, -140),
      );
      await tester.pumpAndSettle();
      expect(drags, greaterThan(0));
      expect(doubles, 1);
      expect(singles, 1);
      enabled.value = false;
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('surface')));
      await tester.pump();
      expect(singles, 2, reason: 'normal cover taps have no double-tap delay');
      await tester.pumpWidget(const SizedBox.shrink());
      enabled.dispose();
    },
  );

  testWidgets('jump feedback acknowledges, supersedes and disposes safely', (
    tester,
  ) async {
    final pending = ValueNotifier(false);
    await tester.pumpWidget(
      MaterialApp(home: PlaybackJumpFeedback(pending: pending)),
    );
    double alpha() => tester
        .widget<FadeTransition>(
          find
              .descendant(
                of: find.byType(PlaybackJumpFeedback),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;
    expect(alpha(), 0);
    pending.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(alpha(), inExclusiveRange(0, 1));
    pending.value = false;
    await tester.pump(const Duration(milliseconds: 40));
    pending.value = true; // old hide timer must not hide a newer seek
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(alpha(), 1);
    pending.value = false;
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump(const Duration(milliseconds: 200));
    expect(alpha(), 0);
    pending.value = true;
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.value = false;
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    pending.dispose();
  });
}
