import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';

void main() {
  test(
    'sample filter rejects an isolated outlier and confirms sustained relocation',
    () {
      final samples = KaraokePositionSampleTracker();
      samples.reset(const Duration(seconds: 5), Duration.zero);
      expect(
        samples.observe(
          const Duration(milliseconds: 4600),
          const Duration(milliseconds: 100),
          1,
        ),
        KaraokeSourceUpdate.stale,
      );
      expect(
        samples.observe(
          const Duration(milliseconds: 5200),
          const Duration(milliseconds: 200),
          1,
        ),
        KaraokeSourceUpdate.continuous,
      );
      expect(
        samples.observe(
          const Duration(milliseconds: 4600),
          const Duration(milliseconds: 300),
          1,
        ),
        KaraokeSourceUpdate.stale,
      );
      expect(
        samples.observe(
          const Duration(milliseconds: 4700),
          const Duration(milliseconds: 400),
          1,
        ),
        KaraokeSourceUpdate.discontinuity,
      );
    },
  );
  for (final hz in [60, 120]) {
    test(
      'delayed position samples keep near-normal forward progress at $hz Hz',
      () {
        final clock = KaraokeMediaClock(Duration.zero);
        addTearDown(clock.dispose);
        clock.setRunning(true, Duration.zero);
        final step = (1000000 / hz).round();
        final count = hz ~/ 5;
        for (var i = 1; i <= count; i++) {
          clock.tick(Duration(microseconds: i * step));
        }
        clock.readSource(Duration(microseconds: count * step - 80000));
        for (var i = 1; i <= hz ~/ 5; i++) {
          final before = clock.value.inMicroseconds;
          clock.tick(Duration(microseconds: (count + i) * step));
          expect(
            (clock.value.inMicroseconds - before) / step,
            inInclusiveRange(.88, 1.12),
          );
        }
      },
    );
  }

  test('180ms delayed sample cannot rewind or act as a seek', () {
    final clock = KaraokeMediaClock(Duration.zero);
    addTearDown(clock.dispose);
    clock.setRunning(true, Duration.zero);
    clock.tick(const Duration(milliseconds: 400));
    clock.readSource(const Duration(milliseconds: 220));
    expect(clock.value, const Duration(milliseconds: 400));
    clock.tick(const Duration(milliseconds: 416));
    expect(clock.value, greaterThan(const Duration(milliseconds: 400)));
  });

  test('ticker epoch restart preserves media pose and resumes forward', () {
    final clock = KaraokeMediaClock(Duration.zero);
    addTearDown(clock.dispose);
    clock.setRunning(true, Duration.zero);
    clock.tick(const Duration(seconds: 1));
    clock.seek(const Duration(milliseconds: 210));
    clock.setRunning(true, const Duration(milliseconds: 210));
    clock.tick(Duration.zero);
    expect(clock.value, const Duration(milliseconds: 210));
    clock.tick(const Duration(milliseconds: 50));
    expect(clock.value, const Duration(milliseconds: 260));
  });

  test('a long frame after a delayed sample advances without rewinding', () {
    final clock = KaraokeMediaClock(Duration.zero);
    addTearDown(clock.dispose);
    clock.setRunning(true, Duration.zero);
    clock.tick(const Duration(milliseconds: 400));
    clock.readSource(const Duration(milliseconds: 220));
    clock.tick(const Duration(milliseconds: 550));
    expect(clock.value.inMilliseconds, inInclusiveRange(538, 550));
  });

  test('explicit small forward and backward seeks remain immediate', () {
    final clock = KaraokeMediaClock(const Duration(seconds: 5));
    addTearDown(clock.dispose);
    clock.setRunning(true, clock.value);
    clock.tick(const Duration(milliseconds: 100));
    for (final target in [5020, 5150, 5100]) {
      clock.seek(Duration(milliseconds: target), protectFromStaleSource: true);
      expect(clock.value, Duration(milliseconds: target));
    }
  });

  testWidgets('position jitter does not install a seek lock in the real list', (
    tester,
  ) async {
    final source = ValueNotifier(Duration.zero);
    await tester.pumpWidget(host(source, preparing: false));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    source.value = const Duration(milliseconds: 210);
    await tester.pump();
    expect(karaokeRow(tester).seekTargetPosition, isNull);
    final Duration before = painter(tester).positionListenable.value;
    await tester.pump(const Duration(milliseconds: 50));
    expect(painter(tester).positionListenable.value, greaterThan(before));
    await tester.pumpWidget(const SizedBox());
    source.dispose();
  });

  testWidgets('cover entry calibrates once and retains the current row', (
    tester,
  ) async {
    final source = ValueNotifier(const Duration(seconds: 3));
    await tester.pumpWidget(host(source, preparing: false, visible: false));
    await tester.pump(const Duration(milliseconds: 200));
    source.value = const Duration(seconds: 4);
    await tester.pumpWidget(host(source, preparing: true));
    final dynamic cache = painter(tester).cache;
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 32));
    final Duration before = painter(tester).positionListenable.value;
    await tester.pumpWidget(host(source, preparing: true));
    expect(
      painter(tester).positionListenable.value,
      greaterThanOrEqualTo(before),
    );
    await tester.pumpWidget(host(source, preparing: false));
    expect(painter(tester).cache, same(cache));
    final Duration shown = painter(tester).positionListenable.value;
    await tester.pump(const Duration(milliseconds: 16));
    expect(painter(tester).positionListenable.value, greaterThan(shown));
    await tester.pumpWidget(const SizedBox());
    source.dispose();
  });

  testWidgets(
    'cold next-line vector fallback already contains the correct highlight',
    (tester) async {
      final source = ValueNotifier(Duration.zero);
      await tester.pumpWidget(host(source, preparing: false));
      final dynamic ink = painter(tester, index: 1), cache = ink.cache;
      final layouts = debugKaraokeTextLayoutCount;
      expect(cache.imageReady, isFalse);
      final recorder = ui.PictureRecorder();
      cache.paint(Canvas(recorder), 11500000, 1.0, ink.colors);
      recorder.endRecording().dispose();
      expect(cache.highlights.any((double v) => v > 0), isTrue);
      expect(
        debugKaraokeTextLayoutCount,
        layouts,
        reason: 'no lazy shaping during paint',
      );
      await tester.pumpWidget(const SizedBox());
      source.dispose();
    },
  );
}

final lines = [
  LyricLine(
    timestamp: Duration.zero,
    texts: ['continuous lyrics', 'translation'],
  ),
  LyricLine(timestamp: const Duration(seconds: 10), texts: ['next words']),
  LyricLine(timestamp: const Duration(seconds: 13), texts: ['last row']),
];

Widget host(
  ValueNotifier<Duration> source, {
  required bool preparing,
  bool visible = true,
}) => MaterialApp(
  home: Scaffold(
    body: TickerMode(
      enabled: visible,
      child: SizedBox(
        width: 360,
        height: 640,
        child: MobileLyricsList(
          lines: lines,
          active: 0,
          position: source.value,
          positionListenable: visible ? source : null,
          isPlaying: visible,
          entryPreparing: preparing,
          karaokeLyricsMode: KaraokeLyricsMode.all,
        ),
      ),
    ),
  ),
);

dynamic painter(WidgetTester tester, {int index = 0}) => tester
    .widget<CustomPaint>(
      find.descendant(
        of: find.byKey(ValueKey('mobile_lyric_$index')),
        matching: find.byKey(
          const ValueKey('mobile_karaoke_single_pass_paint'),
        ),
      ),
    )
    .painter;

dynamic karaokeRow(WidgetTester tester) => tester.widget(
  find.descendant(
    of: find.byKey(const ValueKey('mobile_lyric_0')),
    matching: find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_KaraokeLyricText',
    ),
  ),
);
