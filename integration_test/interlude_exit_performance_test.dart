import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FramePhase;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';

/// ARM64 profile only. Real list + repeated interlude exits, no song/library
/// writes. Persist timings even on failed budgets; display Hz is not proof of
/// actual vsync cadence. Re-run with the device requesting 60 and 120 Hz.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('interlude exit profile frame budgets', (tester) async {
    final key = GlobalKey<_InterludeFixtureState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        showPerformanceOverlay: true,
        home: _InterludeFixture(key: key),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    final rssBefore = ProcessInfo.currentRss;
    final frames = <Map<String, num>>[];
    void record(List<FrameTiming> batch) {
      for (final frame in batch) {
        frames.add({
          'vsyncUs': frame.timestampInMicroseconds(FramePhase.vsyncStart),
          'buildMs': frame.buildDuration.inMicroseconds / 1000,
          'rasterMs': frame.rasterDuration.inMicroseconds / 1000,
        });
      }
    }

    SchedulerBinding.instance.addTimingsCallback(record);
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(milliseconds: 500));
    SchedulerBinding.instance.removeTimingsCallback(record);
    final state = key.currentState!;
    final exitFrames = frames
        .where(
          (frame) => state.exits.any(
            (stamp) =>
                frame['vsyncUs']! >= stamp &&
                frame['vsyncUs']! - stamp <= 600000,
          ),
        )
        .toList();
    Map<String, Object?> stats(List<Map<String, num>> rows) {
      final build = rows.map((f) => f['buildMs']!.toDouble()).toList()..sort();
      final raster = rows.map((f) => f['rasterMs']!.toDouble()).toList()
        ..sort();
      double? p95(List<double> list) =>
          list.isEmpty ? null : list[((list.length - 1) * .95).round()];
      return {
        'frames': rows.length,
        'buildP95Ms': p95(build),
        'rasterP95Ms': p95(raster),
        'buildMaxMs': build.isEmpty ? null : build.last,
        'rasterMaxMs': raster.isEmpty ? null : raster.last,
        'buildOver16_67Ms': build.where((x) => x > 1000 / 60).length,
        'rasterOver16_67Ms': raster.where((x) => x > 1000 / 60).length,
        'buildOver8_33Ms': build.where((x) => x > 1000 / 120).length,
        'rasterOver8_33Ms': raster.where((x) => x > 1000 / 120).length,
      };
    }

    final displayHz = View.of(key.currentContext!).display.refreshRate;
    final report = {
      'mode': 'profile',
      'fixture': 'real list, repeated 2s interlude / 2s mixed lyric, no audio',
      'displayHz': displayHz,
      'all': stats(frames),
      'transition600ms': stats(exitFrames),
      'rssBeforeBytes': rssBefore,
      'rssAfterBytes': ProcessInfo.currentRss,
      'exitStampsUs': state.exits,
      'frames': frames,
    };
    binding.reportData = report;
    await File(
      '${Directory.systemTemp.path}/myune_interlude_profile.json',
    ).writeAsString(jsonEncode(report));
    expect(exitFrames.length, greaterThan(30));
    // Strict all-frame acceptance, not merely a passing P95. Preserve failure.
    expect(
      exitFrames.every(
        (f) =>
            f['buildMs']! <= 1000 / displayHz &&
            f['rasterMs']! <= 1000 / displayHz,
      ),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
  });
}

class _InterludeFixture extends StatefulWidget {
  const _InterludeFixture({super.key});
  @override
  State<_InterludeFixture> createState() => _InterludeFixtureState();
}

class _InterludeFixtureState extends State<_InterludeFixture>
    with SingleTickerProviderStateMixin {
  final position = ValueNotifier(Duration.zero);
  final exits = <int>[];
  late final Ticker ticker;
  var active = 0;
  final lines = List.generate(
    24,
    (index) => index.isEven
        ? LyricLine(
            timestamp: Duration(seconds: index * 2),
            texts: const [],
            isInterlude: true,
            interludeDuration: const Duration(seconds: 2),
          )
        : LyricLine(
            timestamp: Duration(seconds: index * 2),
            texts: const [
              '前奏消散 中文 softly follows the song',
              '翻译静态 Translation',
            ],
          ),
  );
  @override
  void initState() {
    super.initState();
    ticker = createTicker((elapsed) {
      position.value = elapsed;
      final next = (elapsed.inSeconds ~/ 2).clamp(0, lines.length - 1);
      if (next != active) {
        if (active.isEven && next == active + 1) {
          exits.add(
            SchedulerBinding
                .instance
                .currentSystemFrameTimeStamp
                .inMicroseconds,
          );
        }
        setState(() => active = next);
      }
    })..start();
  }

  @override
  void dispose() {
    ticker.dispose();
    position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: MobileLyricsList(
      lines: lines,
      active: active,
      positionListenable: position,
      isPlaying: true,
      karaokeLyricsMode: KaraokeLyricsMode.all,
      fontFamily: 'misans',
      fontSize: 28,
      activeColor: Colors.white,
      lineBlurEnabled: true,
    ),
  );
}
