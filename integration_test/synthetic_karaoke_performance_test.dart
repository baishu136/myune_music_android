import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show FramePhase;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/widgets/playback_background/fluid_background.dart';

// Run on a physical Android device in PROFILE mode at both 60 and 120 Hz:
// flutter drive --profile --driver=test_driver/integration_test.dart
//   --target=integration_test/synthetic_karaoke_performance_test.dart -d <device>
// This fixture measures the real Flutter build/raster pipeline. RSS is process
// memory, not an isolated GPU-memory measurement. No music/library is needed.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('synthetic karaoke frame budgets and warmed memory', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var i = 0; i < 3; i++) {
      canvas.drawRect(
        Rect.fromLTWH(i * 24, 0, 24, 72),
        Paint()
          ..color = const [
            Color(0xFFEF2683),
            Color(0xFF25BFA3),
            Color(0xFFF09D2C),
          ][i],
      );
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(72, 72);
    final cover = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
    final key = GlobalKey<_FixtureState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        showPerformanceOverlay: true,
        home: _Fixture(key: key, cover: cover),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    final rssBefore = ProcessInfo.currentRss;
    final build = <double>[];
    final raster = <double>[];
    final boundaryBuild = <double>[];
    final boundaryRaster = <double>[];
    final gaps = <double>[];
    int? lastVsync;
    void record(List<FrameTiming> frames) {
      for (final frame in frames) {
        build.add(frame.buildDuration.inMicroseconds / 1000);
        raster.add(frame.rasterDuration.inMicroseconds / 1000);
        final vsync = frame.timestampInMicroseconds(FramePhase.vsyncStart);
        if (lastVsync != null) gaps.add((vsync - lastVsync!) / 1000);
        lastVsync = vsync;
        if (key.currentState!.boundaries.any(
          (stamp) => vsync >= stamp && vsync - stamp <= 650000,
        )) {
          boundaryBuild.add(frame.buildDuration.inMicroseconds / 1000);
          boundaryRaster.add(frame.rasterDuration.inMicroseconds / 1000);
        }
      }
    }

    SchedulerBinding.instance.addTimingsCallback(record);
    final refresh = View.of(key.currentContext!).display.refreshRate;
    try {
      await binding.traceAction(() async {
        for (final rate in [.75, 1.0, 1.5, 2.0]) {
          key.currentState!.changeRate(rate);
          await tester.pump(const Duration(seconds: 3));
        }
        key.currentState!.seekTo(const Duration(seconds: 30));
        await tester.pump(const Duration(seconds: 2));
        key.currentState!.seekTo(const Duration(seconds: 3));
        await tester.pump(const Duration(seconds: 2));
        await tester.drag(
          find.byKey(const ValueKey('mobile_lyrics_scroll_view')),
          const Offset(0, -150),
        );
        await tester.pump(const Duration(seconds: 5));
      }, reportKey: 'synthetic_karaoke_timeline');
    } finally {
      SchedulerBinding.instance.removeTimingsCallback(record);
    }
    expect(build.length, greaterThan(100));
    build.sort();
    raster.sort();
    boundaryBuild.sort();
    boundaryRaster.sort();
    gaps.sort();
    double p95(List<double> values) =>
        values[((values.length - 1) * .95).round()];
    final budget = 1000 / refresh;
    binding.reportData!['synthetic_karaoke_metrics'] = {
      'mode': 'profile',
      'fixture': 'generated cover + lyrics, not a real song/full player',
      'displayHz': refresh,
      'budgetMs': budget,
      'frames': build.length,
      'buildP95Ms': p95(build),
      'rasterP95Ms': p95(raster),
      'buildOverBudget': build.where((t) => t > budget).length,
      'rasterOverBudget': raster.where((t) => t > budget).length,
      'buildMaxMs': build.last,
      'rasterMaxMs': raster.last,
      'boundaryFrames': boundaryBuild.length,
      'boundaryBuildP95Ms': boundaryBuild.isEmpty ? null : p95(boundaryBuild),
      'boundaryRasterP95Ms': boundaryRaster.isEmpty
          ? null
          : p95(boundaryRaster),
      'boundaryBuildMaxMs': boundaryBuild.isEmpty ? null : boundaryBuild.last,
      'boundaryRasterMaxMs': boundaryRaster.isEmpty
          ? null
          : boundaryRaster.last,
      'boundaryBuildOver12Ms': boundaryBuild.where((t) => t > 12).length,
      'boundaryRasterOver12Ms': boundaryRaster.where((t) => t > 12).length,
      'vsyncGapP95Ms': gaps.isEmpty ? null : p95(gaps),
      'vsyncGapMaxMs': gaps.isEmpty ? null : gaps.last,
      'rssBeforeBytes': rssBefore,
      'rssAfterBytes': ProcessInfo.currentRss,
    };
    // Also persist in the app's private temporary directory. Some OEM builds
    // suppress service-port logs; standalone profile runs must still retain
    // failed-budget evidence without disabling VM-service authentication.
    await File(
      '${Directory.systemTemp.path}/myune_karaoke_profile.json',
    ).writeAsString(jsonEncode(binding.reportData));
    expect(p95(build), lessThanOrEqualTo(budget));
    expect(p95(raster), lessThanOrEqualTo(budget));
    await tester.pumpWidget(const SizedBox());
  });
}

class _Fixture extends StatefulWidget {
  const _Fixture({super.key, required this.cover});
  final Uint8List cover;
  @override
  State<_Fixture> createState() => _FixtureState();
}

class _FixtureState extends State<_Fixture>
    with SingleTickerProviderStateMixin {
  final position = ValueNotifier(Duration.zero);
  final rate = ValueNotifier(1.0);
  final seek = ValueNotifier<Duration?>(null);
  late final Ticker ticker;
  Duration lastElapsed = Duration.zero;
  int active = 0;
  final boundaries = <int>[];
  final lines = List.generate(
    48,
    (i) => LyricLine(
      timestamp: Duration(seconds: i * 2),
      texts: [
        switch (i % 4) {
          0 => '快速中文句子里的文字自然逐个推进',
          1 => 'I am supercalifragilisticexpialidocious and I go softly',
          2 => '中文 mixed English 日本語 한국어 👨‍👩‍👧‍👦 é',
          _ => 'طريق الموسيقى शांत संगीत',
        },
        '静态翻译行 / Translation $i',
      ],
    ),
  );
  @override
  void initState() {
    super.initState();
    ticker = createTicker((elapsed) {
      final delta = elapsed - lastElapsed;
      lastElapsed = elapsed;
      position.value += Duration(
        microseconds: (delta.inMicroseconds * rate.value).round(),
      );
      final next = (position.value.inSeconds ~/ 2).clamp(0, lines.length - 1);
      if (next != active) {
        boundaries.add(
          SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds,
        );
        setState(() => active = next);
      }
    })..start();
  }

  void changeRate(double value) => rate.value = value;
  void seekTo(Duration value) {
    position.value = value;
    seek.value = value;
    setState(() => active = (value.inSeconds ~/ 2).clamp(0, lines.length - 1));
  }

  @override
  void dispose() {
    ticker.dispose();
    position.dispose();
    rate.dispose();
    seek.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: FluidPlaybackBackground(
      artworkBytes: widget.cover,
      artworkIdentity: 'profile-generated-pigments',
      artworkCacheGeneration: 361,
      fallbackSeed: Colors.pink,
      dim: .3,
      quality: FluidBackgroundQuality.smooth,
      routeTransitionActive: false,
      child: MobileLyricsList(
        lines: lines,
        active: active,
        positionListenable: position,
        playbackRateListenable: rate,
        seekPositionListenable: seek,
        karaokeLyricsMode: KaraokeLyricsMode.all,
        fontFamily: 'misans',
        fontSize: 28,
        activeColor: Colors.white,
        lineBlurEnabled: true,
      ),
    ),
  );
}
