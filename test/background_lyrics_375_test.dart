import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';

import 'karaoke_continuity_test.dart' as fixture;

void main() {
  test('a pending audio output rejects an isolated old position', () {
    final clock = KaraokeMediaClock(const Duration(seconds: 2));
    addTearDown(clock.dispose);
    clock.readSource(Duration.zero);
    expect(clock.value, const Duration(seconds: 2));
    clock.readSource(const Duration(seconds: 2));
    clock.setRunning(true, const Duration(seconds: 2));
    clock.tick(const Duration(milliseconds: 16));
    expect(clock.value, const Duration(milliseconds: 2016));
  });
  test('settled ink sleeps but a backwards seek wakes repaint', () {
    final source = ValueNotifier(Duration.zero);
    final paint = KaraokePaintClock(source)..settleAfterUs = 1000000;
    var paints = 0;
    paint.addListener(() => paints++);
    source.value = const Duration(milliseconds: 999);
    source.value = const Duration(seconds: 1);
    final settled = paints;
    source.value = const Duration(seconds: 2);
    source.value = const Duration(seconds: 3);
    expect(paints, settled);
    expect(paint.value, source.value);
    source.value = const Duration(milliseconds: 500);
    expect(paints, settled + 1);
    paint.dispose();
    source.dispose();
  });
  test('repeated startup positions cannot confirm a backwards relocation', () {
    final samples = KaraokePositionSampleTracker();
    samples.reset(const Duration(seconds: 2), Duration.zero);
    for (var ms = 100; ms <= 500; ms += 100) {
      expect(
        samples.observe(Duration.zero, Duration(milliseconds: ms), 1),
        KaraokeSourceUpdate.stale,
      );
    }
    expect(
      samples.observe(
        const Duration(milliseconds: 2600),
        const Duration(milliseconds: 600),
        1,
      ),
      KaraokeSourceUpdate.continuous,
    );
  });

  test('resume preserves the pose while waiting for a fresh source', () {
    final clock = KaraokeMediaClock(const Duration(seconds: 2));
    addTearDown(clock.dispose);
    clock.setRunning(true, const Duration(seconds: 2));
    clock.tick(const Duration(milliseconds: 500));
    clock.setRunning(false, const Duration(seconds: 2));
    expect(clock.value, const Duration(milliseconds: 2500));
    clock.setRunning(true, const Duration(seconds: 2));
    expect(clock.value, const Duration(milliseconds: 2500));
    clock.tick(const Duration(milliseconds: 16));
    expect(clock.value, greaterThan(const Duration(milliseconds: 2500)));
  });

  testWidgets('only the active row advances its media clock', (tester) async {
    final source = ValueNotifier(Duration.zero);
    await tester.pumpWidget(fixture.host(source, preparing: false));
    final dynamic next = fixture.painter(tester, index: 1);
    final Duration initial = next.positionListenable.value;
    final Duration activeInitial = fixture
        .painter(tester)
        .positionListenable
        .value;
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(fixture.painter(tester, index: 1).positionListenable.value, initial);
    expect(
      fixture.painter(tester).positionListenable.value,
      greaterThan(activeInitial),
    );
    await tester.pumpWidget(const SizedBox());
    source.dispose();
  });
}
