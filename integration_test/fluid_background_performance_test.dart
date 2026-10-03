import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/widgets/playback_background/fluid_background.dart';

// Full-screen production renderer, isolated package recommended. The four
// generated covers model the reference colour families; they are NOT the actual
// albums. FrameTiming raster duration is not isolated GPU shader duration.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('fluid full-screen colour changes and hidden-route scheduling', (
    tester,
  ) async {
    final covers = <Uint8List>[];
    for (final colors in const [
      [
        Color(0xFFF1779F),
        Color(0xFF56BCAB),
        Color(0xFFEAB655),
        Color(0xFF666360),
      ],
      [Colors.black, Colors.black, Colors.black, Color(0xFF143141)],
      [
        Color(0xFF180000),
        Color(0xFF701300),
        Color(0xFFC87308),
        Color(0xFF100806),
      ],
      [Colors.black, Colors.black, Colors.black, Color(0xFFB8B8B8)],
    ]) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      for (var i = 0; i < colors.length; i++) {
        canvas.drawRect(
          Rect.fromLTWH(i * 16, 0, 16, 64),
          Paint()..color = colors[i],
        );
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(64, 64);
      covers.add(
        (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List(),
      );
      image.dispose();
      picture.dispose();
    }
    final key = GlobalKey<_SceneState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: _Scene(key: key, covers: covers),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    final stages = <Map<String, Object?>>[];
    final rssBefore = ProcessInfo.currentRss;
    final display = View.of(key.currentContext!).display;
    for (var i = 0; i < 4; i++) {
      final builds = <double>[], rasters = <double>[], vsyncs = <int>[];
      void record(List<FrameTiming> timings) {
        for (final timing in timings) {
          builds.add(timing.buildDuration.inMicroseconds / 1000);
          rasters.add(timing.rasterDuration.inMicroseconds / 1000);
          vsyncs.add(timing.timestampInMicroseconds(ui.FramePhase.vsyncStart));
        }
      }

      SchedulerBinding.instance.addTimingsCallback(record);
      key.currentState!.change(i);
      await tester.pump(const Duration(seconds: 7));
      SchedulerBinding.instance.removeTimingsCallback(record);
      final gaps = <double>[];
      for (var j = 1; j < vsyncs.length; j++) {
        gaps.add((vsyncs[j] - vsyncs[j - 1]) / 1000);
      }
      builds.sort();
      rasters.sort();
      gaps.sort();
      double p95(List<double> data) =>
          data.isEmpty ? 0 : data[((data.length - 1) * .95).round()];
      stages.add({
        'sample': [
          'vivid-pink-green',
          'dark-blue',
          'red-amber',
          'monochrome',
        ][i],
        'frames': builds.length,
        'buildP95Ms': p95(builds),
        'rasterP95Ms': p95(rasters),
        'rasterMaxMs': rasters.isEmpty ? 0 : rasters.last,
        'over16_67Ms': rasters.where((v) => v > 16.667).length,
        'over8_33Ms': rasters.where((v) => v > 8.333).length,
        'vsyncGapP95Ms': p95(gaps),
        'rssBytes': ProcessInfo.currentRss,
      });
      expect(
        find.byKey(const ValueKey('fluid-background-shader')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    key.currentState!.hide();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    binding.reportData = {
      'fluidMetrics': {
        'mode': 'profile',
        'samples': 'generated covers, not actual albums',
        'shaderOnlyGpuTiming': false,
        'quality': 'smooth',
        'advertisedDisplayHz': display.refreshRate,
        'physicalPixels': '${display.size.width}x${display.size.height}',
        'rssBefore': rssBefore,
        'rssAfter': ProcessInfo.currentRss,
        'stages': stages,
      },
    };
  });
}

class _Scene extends StatefulWidget {
  const _Scene({super.key, required this.covers});
  final List<Uint8List> covers;
  @override
  State<_Scene> createState() => _SceneState();
}

class _SceneState extends State<_Scene> {
  int index = 0;
  bool hidden = false;
  void change(int value) => setState(() => index = value);
  void hide() => setState(() => hidden = true);
  @override
  Widget build(BuildContext context) => FluidPlaybackBackground(
    artworkBytes: widget.covers[index],
    artworkIdentity: 'fluid-$index',
    artworkCacheGeneration: 347,
    fallbackSeed: Colors.teal,
    dim: .3,
    quality: FluidBackgroundQuality.smooth,
    routeTransitionActive: hidden,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            'Myune fluid — sample $index',
            style: const TextStyle(fontSize: 20),
          ),
        ),
      ),
    ),
  );
}
