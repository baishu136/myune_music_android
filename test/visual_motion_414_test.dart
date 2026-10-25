import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';

void main() {
  test('smooth preference is opt-in and survives restart', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.initializationFuture;
    expect(settings.smoothKaraokeMotion, isFalse);
    await settings.setSmoothKaraokeMotion(true);
    final restored = SettingsProvider();
    await restored.initializationFuture;
    expect(restored.smoothKaraokeMotion, isTrue);
    settings.dispose();
    restored.dispose();
  });
  test(
    'smooth clock has bounded speed and follows seek pause rate at 60/90/120Hz',
    () {
      for (final hz in [60, 90, 120]) {
        final clock = KaraokeMediaClock(
          const Duration(seconds: 10),
          smoothMotion: true,
        );
        clock.setRunning(true, clock.value);
        var previous = clock.value;
        var previousSpeed = 1.0;
        for (var frame = 1; frame <= hz * 4; frame++) {
          final stamp = Duration(microseconds: (frame * 1000000 / hz).round());
          if (frame % (hz ~/ 5) == 0) {
            clock.readSource(
              const Duration(seconds: 10) +
                  stamp +
                  Duration(milliseconds: frame.isEven ? 70 : -45),
            );
          }
          clock.tick(stamp);
          final speed =
              (clock.value - previous).inMicroseconds / (1000000 / hz);
          expect(speed, inInclusiveRange(.915, 1.085));
          expect((speed - previousSpeed).abs(), lessThan(.04));
          previousSpeed = speed;
          previous = clock.value;
        }
        clock.setRunning(false, clock.value);
        clock.tick(const Duration(seconds: 8));
        expect(clock.value, previous);
        clock.seek(const Duration(seconds: 2), protectFromStaleSource: true);
        expect(clock.value, const Duration(seconds: 2));
        clock.setRunning(true, clock.value);
        clock.changeRate(2, clock.value);
        clock.tick(const Duration(milliseconds: 100));
        expect(clock.value, const Duration(milliseconds: 2200));
        clock.dispose();
      }
    },
  );
  testWidgets('real timed glyphs use continuous relays only when selected', (
    tester,
  ) async {
    await (FontLoader(
      'misans',
    )..addFont(rootBundle.load('assets/fonts/MiSansVF.ttf'))).load();
    final tokens = <LyricToken>[
      LyricToken(
        text: '歌',
        start: const Duration(seconds: 1),
        end: const Duration(milliseconds: 1100),
      ),
      LyricToken(
        text: '词',
        start: const Duration(milliseconds: 1100),
        end: const Duration(milliseconds: 2100),
      ),
      LyricToken(
        text: '连',
        start: const Duration(milliseconds: 2100),
        end: const Duration(milliseconds: 2300),
      ),
      LyricToken(
        text: '贯',
        start: const Duration(milliseconds: 2300),
        end: const Duration(milliseconds: 3300),
      ),
    ];
    final line = LyricLine(
      timestamp: const Duration(seconds: 1),
      texts: ['歌词连贯'],
      tokens: [tokens],
    );
    Widget host(bool enabled) => MaterialApp(
      home: Scaffold(
        body: MobileLyricsList(
          lines: [line],
          active: 0,
          isPlaying: false,
          position: const Duration(milliseconds: 1500),
          fontFamily: 'misans',
          fontSize: 50,
          smoothKaraokeMotion: enabled,
        ),
      ),
    );
    await tester.pumpWidget(host(false));
    dynamic painter = tester
        .widget<CustomPaint>(
          find.byKey(const ValueKey('mobile_karaoke_single_pass_paint')),
        )
        .painter;
    expect(painter.cache.sweepRelays, isEmpty);
    await tester.pumpWidget(host(true));
    painter = tester
        .widget<CustomPaint>(
          find.byKey(const ValueKey('mobile_karaoke_single_pass_paint')),
        )
        .painter;
    final dynamic cache = painter.cache;
    expect(cache.synthetic, isFalse);
    expect(cache.smoothMotion, isTrue);
    expect(cache.followerTimeline.config.fastOvershootFraction, 0);
    expect(cache.sweepRelays.length, 1);
    final dynamic timeline = cache.sweepRelays.first.timeline;
    for (final boundary in [1100000, 2100000, 2300000]) {
      final double middle = timeline.phaseAt(boundary);
      final double before = timeline.phaseAt(boundary - 10);
      final double after = timeline.phaseAt(boundary + 10);
      expect(((middle - before) - (after - middle)).abs(), lessThan(1e-7));
    }
    final starts = [
      for (final dynamic token in cache.tokens) token.range.token.start,
    ];
    expect(starts, tokens.map((t) => t.start).toList());
    final lengths = [
      for (final dynamic token in cache.tokens)
        token.fragments.first.sweep.length,
    ];
    cache.prepareImage();
    for (var i = 0; i < 80 && !cache.imageReady; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(cache.imageReady, isTrue);
    expect([
      for (final dynamic token in cache.tokens)
        token.fragments.first.sweep.length,
    ], lengths);
    final builds = debugKaraokeLayoutBuildCount;
    for (var frame = 0; frame < 120; frame++) {
      final recorder = ui.PictureRecorder();
      cache.paint(
        Canvas(recorder),
        1000000 + frame * 16667,
        1.0,
        painter.colors,
      );
      recorder.endRecording().dispose();
    }
    expect(debugKaraokeLayoutBuildCount, builds);
    void drawAt(int time) {
      final recorder = ui.PictureRecorder();
      cache.paint(Canvas(recorder), time, 1.0, painter.colors);
      recorder.endRecording().dispose();
    }

    drawAt(2500000);
    final pose = List<double>.from(cache.lifts);
    drawAt(700000);
    drawAt(2500000);
    expect(List<double>.from(cache.lifts), pose);
    await tester.pumpWidget(const SizedBox());
  });
  test('phone font limit is 60 and edits snap to integers', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.initializationFuture;
    expect(SettingsProvider.maxLyricFontSizeFor(const Size(390, 844)), 60);
    settings.previewFontSize(46.7);
    expect(settings.fontSize, 47);
    settings.dispose();
  });
}
