import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/models/fluid_background_state.dart';
import 'package:myune_music/services/artwork_palette_cache.dart';
import 'package:myune_music/services/fluid_background_controller.dart';
import 'package:myune_music/widgets/playback_background/fluid_background_painter.dart';
import 'package:myune_music/widgets/playback_background/fluid_frame_uniforms.dart';
import 'support/fluid_field_reference.dart';

const _diagnostic = FluidPalette(
  Color(0xFFFFFF00),
  Color(0xFFFF0000),
  Color(0xFF00FF00),
  Color(0xFF0000FF),
  baseColor: Colors.black,
);

void main() {
  test(
    'clipping connects same-edge fragments but rejects interior islands',
    () {
      final clipped = Uint8List(100)..fillRange(0, 100, 255);
      for (final y in [0, 1, 2, 7, 8, 9]) {
        clipped[y * 10 + 8] = clipped[y * 10 + 9] = 0;
      }
      _checkConnected(clipped, 10, 10, 0);
      final islands = Uint8List(100)..fillRange(0, 100, 255);
      for (final y in [1, 2, 3]) {
        islands[y * 10 + 1] = islands[y * 10 + 2] = 0;
        islands[(y + 4) * 10 + 6] = islands[(y + 4) * 10 + 7] = 0;
      }
      expect(
        () => _checkConnected(islands, 10, 10, 0),
        throwsA(isA<TestFailure>()),
      );
    },
  );
  testWidgets('four connected colour fields circulate around the centre', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final shader = (await ui.FragmentProgram.fromAsset(
        'shaders/fluid_background.frag',
      )).fragmentShader();
      try {
        for (final size in [const Size(96, 160), const Size(160, 96)]) {
          final width = size.width.toInt(), height = size.height.toInt();
          double? previousAngle;
          var rotation = 0.0;
          var minimumTurn = double.infinity, maximumTurn = 0.0;
          for (var step = 0; step < 32; step++) {
            final time = fluidOrbitPeriod * step / 32;
            final packed = FluidFrameUniforms();
            packed.write(
              shader,
              size: size,
              time: time,
              motion: 1,
              dim: .3,
              source: _diagnostic,
              target: _diagnostic,
            );
            final decoder = _pigmentDecoder(packed.values);
            final pixels = await _render(
              shader,
              _diagnostic,
              size: size,
              time: time,
            );
            final labels = Uint8List(width * height);
            final fieldLabels = Uint8List(width * height);
            final fieldCounts = [0, 0, 0, 0];
            final counts = [0, 0, 0, 0];
            var redX = 0.0, redY = 0.0;
            for (var y = 0; y < height; y++) {
              for (var x = 0; x < width; x++) {
                final i = (y * width + x) * 4;
                final ux = (x + .5) / width, uy = (y + .5) / height;
                final fieldWeights = fluidReferenceWeights(
                  packed.values,
                  ux,
                  uy,
                );
                final coverage = fluidReferenceCoverage(fieldWeights);
                var fieldWinner = 0;
                for (var field = 1; field < 4; field++) {
                  if (fieldWeights[field] > fieldWeights[fieldWinner]) {
                    fieldWinner = field;
                  }
                }
                fieldLabels[y * width + x] = fieldWinner;
                fieldCounts[fieldWinner]++;
                if (coverage < .035) {
                  labels[y * width + x] = 4;
                  expect(pixels[i + 3], 255);
                  continue;
                }
                final edge =
                    ((math.sqrt(math.pow(ux - .5, 2) + math.pow(uy - .48, 2)) -
                                .35) /
                            .75)
                        .clamp(0.0, 1.0);
                final veil =
                    .84 * (1 - .02 * edge * edge * (3 - 2 * edge)) * .925;
                final rgb = [
                  pixels[i] / (255 * veil),
                  pixels[i + 1] / (255 * veil),
                  pixels[i + 2] / (255 * veil),
                  1.0,
                ];
                // RGB+yellow is affine-independent. Recover each field's
                // contribution, rather than mislabelling a soft yellow/red
                // join as a second red field just because red is brightest.
                final channels = List<double>.generate(4, (c) {
                  var weight = 0.0;
                  for (var j = 0; j < 4; j++) {
                    weight += decoder[c][j] * rgb[j];
                  }
                  return weight;
                });
                var strongest = 0;
                for (var c = 1; c < 4; c++) {
                  if (channels[c] > channels[strongest]) strongest = c;
                }
                labels[y * width + x] = strongest;
                counts[strongest]++;
                if (strongest == 0) {
                  redX += (x + .5) / width;
                  redY += (y + .5) / height;
                }
                expect(pixels[i + 3], 255);
              }
            }
            for (var c = 0; c < 4; c++) {
              expect(counts[c], lessThan(width * height * .70));
              // Transferred pigment can appear on a recipient's edge. The
              // original field must stay connected; coloured ink need not
              // remain confined to that field after deliberate transmission.
              if (fieldCounts[c] > 4) {
                _checkConnected(fieldLabels, width, height, c);
              }
            }
            if (counts[0] == 0) continue;
            final angle = math.atan2(
              redY / counts[0] - .5,
              redX / counts[0] - .5,
            );
            if (previousAngle != null) {
              var delta = angle - previousAngle;
              while (delta < -math.pi) {
                delta += math.pi * 2;
              }
              while (delta > math.pi) {
                delta -= math.pi * 2;
              }
              rotation += delta;
              minimumTurn = math.min(minimumTurn, delta);
              maximumTurn = math.max(maximumTurn, delta);
            }
            previousAngle = angle;
          }
          expect(rotation, greaterThan(5.5), reason: 'not a fixed stripe');
          expect(rotation, lessThan(7));
          // The source orbit is monotonic; a clipped, breathing physical colour
          // region can move its centroid slightly backwards at the viewport edge.
          expect(minimumTurn, greaterThan(-.10));
          expect(
            maximumTurn - minimumTurn,
            greaterThan(.15),
            reason: 'visible angular speed is not fixed',
          );
          debugPrint(
            'Orbit $size: centroid rotation=$rotation, '
            'angular step range=$minimumTurn..$maximumTurn',
          );
        }
      } finally {
        shader.dispose();
      }
    });
  });

  testWidgets('colour joins stay broad and frames move without snapping', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final shader = (await ui.FragmentProgram.fromAsset(
        'shaders/fluid_background.frag',
      )).fragmentShader();
      try {
        var largestStep = 0, largestFrameStep = 0;
        var totalTravel = 0;
        for (var step = 0; step < 24; step++) {
          final time = fluidPhaseCycle * step / 24;
          final pixels = await _render(shader, _diagnostic, time: time);
          final next = await _render(shader, _diagnostic, time: time + 1 / 24);
          final later = await _render(shader, _diagnostic, time: time + 4);
          for (var y = 0; y < 160; y++) {
            for (var x = 0; x < 96; x++) {
              final i = (y * 96 + x) * 4;
              for (var c = 0; c < 3; c++) {
                final frameStep = (pixels[i + c] - next[i + c]).abs();
                if (frameStep > largestFrameStep) largestFrameStep = frameStep;
                totalTravel += (pixels[i + c] - later[i + c]).abs();
                if (x < 95) {
                  final spatialStep = (pixels[i + c] - pixels[i + 4 + c]).abs();
                  if (spatialStep > largestStep) largestStep = spatialStep;
                }
              }
            }
          }
        }
        expect(largestStep, lessThanOrEqualTo(12));
        // Colour changes now run at twice the previous rate and shape at 1.6x.
        expect(largestFrameStep, lessThanOrEqualTo(12));
        expect(totalTravel / (24 * 96 * 160 * 3), greaterThan(2));
        debugPrint(
          'Orbit flow: spatial=$largestStep, 24Hz frame='
          '$largestFrameStep, four-second travel='
          '${totalTravel / (24 * 96 * 160 * 3)}',
        );
      } finally {
        shader.dispose();
      }
    });
  });

  testWidgets('export actual shader stills and continuous animation frames', (
    tester,
  ) async {
    const path = String.fromEnvironment('ORDERED_FLUID_ARTIFACT_DIRECTORY');
    if (path.isEmpty) return;
    await tester.runAsync(() async {
      final directory = Directory(path);
      await directory.create(recursive: true);
      final shader = (await ui.FragmentProgram.fromAsset(
        'shaders/fluid_background.frag',
      )).fragmentShader();
      final palette = buildWeightedFluidPalette(const [
        FluidColorSample(Color(0xFFEF2683), .40),
        FluidColorSample(Color(0xFF25BFA3), .30),
        FluidColorSample(Color(0xFFF09D2C), .20),
        FluidColorSample(Color(0xFF58687B), .10),
      ], fallbackSeed: Colors.blue);
      try {
        for (var frame = 0; frame < 120; frame++) {
          await _render(
            shader,
            palette,
            size: const Size(240, 400),
            time: frame / 10,
            png: '$path/frame-${frame.toString().padLeft(3, '0')}.png',
          );
        }
        for (final entry in {
          'colourful': palette,
          'cool': buildWeightedFluidPalette(const [
            FluidColorSample(Color(0xFF167EA4), .55),
            FluidColorSample(Color(0xFF202868), .30),
            FluidColorSample(Color(0xFF605798), .15),
          ], fallbackSeed: Colors.orange),
          'dark': buildFluidPalette(const [
            Color(0xFF081C24),
            Colors.black,
          ], fallbackSeed: Colors.blue),
          'monochrome': buildFluidPalette(const [
            Color(0xFF444444),
          ], fallbackSeed: Colors.pink),
        }.entries) {
          for (var step = 0; step < 4; step++) {
            await _render(
              shader,
              entry.value,
              size: const Size(384, 640),
              time: step * fluidPhaseCycle / 4,
              png: '$path/${entry.key}-$step.png',
            );
          }
        }
      } finally {
        shader.dispose();
      }
    });
  });
}

void _checkConnected(Uint8List labels, int width, int height, int colour) {
  final visited = Uint8List(labels.length);
  final components = <int>[];
  for (var start = 0; start < labels.length; start++) {
    if (visited[start] != 0 || labels[start] != colour) continue;
    final queue = [start];
    visited[start] = 1;
    for (var head = 0; head < queue.length; head++) {
      final pixel = queue[head], x = pixel % width, y = pixel ~/ width;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
          final next = ny * width + nx;
          if (visited[next] == 0 && labels[next] == colour) {
            visited[next] = 1;
            queue.add(next);
          }
        }
      }
    }
    // Ignore sub-LSB ties. A roaming field can leave and re-enter through
    // the same viewport edge; merge only those clipped boundary fragments.
    // Interior islands remain separate and fail exactly as before.
    if (queue.length > 4) {
      var edges = 0;
      for (final pixel in queue) {
        final x = pixel % width, y = pixel ~/ width;
        if (x == 0) edges |= 1;
        if (x == width - 1) edges |= 2;
        if (y == 0) edges |= 4;
        if (y == height - 1) edges |= 8;
      }
      for (var i = components.length - 1; i >= 0; i--) {
        if (edges & components[i] != 0) {
          edges |= components.removeAt(i);
        }
      }
      components.add(edges);
    }
  }
  expect(components.length, 1, reason: 'disconnected colour $colour');
}

List<List<double>> _pigmentDecoder(Float32List packed) {
  final matrix = <List<double>>[
    [for (var f = 0; f < 4; f++) packed[14 + f * 3], 1, 0, 0, 0],
    [for (var f = 0; f < 4; f++) packed[15 + f * 3], 0, 1, 0, 0],
    [for (var f = 0; f < 4; f++) packed[16 + f * 3], 0, 0, 1, 0],
    [1, 1, 1, 1, 0, 0, 0, 1],
  ];
  for (var col = 0; col < 4; col++) {
    var pivot = col;
    for (var row = col + 1; row < 4; row++) {
      if (matrix[row][col].abs() > matrix[pivot][col].abs()) pivot = row;
    }
    final swap = matrix[col];
    matrix[col] = matrix[pivot];
    matrix[pivot] = swap;
    final scale = matrix[col][col];
    for (var j = 0; j < 8; j++) {
      matrix[col][j] /= scale;
    }
    for (var row = 0; row < 4; row++) {
      if (row == col) continue;
      final factor = matrix[row][col];
      for (var j = 0; j < 8; j++) {
        matrix[row][j] -= factor * matrix[col][j];
      }
    }
  }
  return matrix.map((row) => row.sublist(4)).toList();
}

Future<Uint8List> _render(
  ui.FragmentShader shader,
  FluidPalette palette, {
  double time = 0,
  Size size = const Size(96, 160),
  String? png,
}) async {
  final controller = FluidBackgroundController(
    vsync: const TestVSync(),
    initialPalette: palette,
  );
  final setup = ui.PictureRecorder();
  FluidBackgroundPainter(
    shader: shader,
    controller: controller,
    dim: .3,
  ).paint(Canvas(setup), size);
  setup.endRecording().dispose();
  FluidFrameUniforms().write(
    shader,
    size: size,
    time: time,
    motion: 1,
    dim: .3,
    source: palette,
    target: palette,
  );
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(Offset.zero & size, Paint()..shader = shader);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  try {
    if (png != null) {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(png).writeAsBytes(bytes!.buffer.asUint8List());
    }
    return (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
    controller.dispose();
  }
}
