import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:myune_music/widgets/custom_theme_background.dart';
import 'package:myune_music/widgets/gaussian_artwork_surface.dart';

Future<void> resolveImage(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(tester.takeException(), isNull);
}

Future<Uint8List> pixels(
  WidgetTester tester,
  Uint8List bytes, {
  double sigma = 8,
  double width = 64,
  double height = 64,
  GlobalKey? captureKey,
  bool unmount = true,
}) async {
  final key = captureKey ?? GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: width,
            height: height,
            child: GaussianArtworkSurface(
              provider: MemoryImage(bytes),
              sigma: sigma,
            ),
          ),
        ),
      ),
    ),
  );
  await resolveImage(tester);
  final result = await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    const artifactRoot = String.fromEnvironment('GAUSSIAN_ARTIFACT_ROOT');
    if (artifactRoot.isNotEmpty) {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(artifactRoot)..createSync(recursive: true);
      File(
        '${directory.path}/frame-${_snapshot++}.png',
      ).writeAsBytesSync(png!.buffer.asUint8List());
    }
    image.dispose();
    return Uint8List.fromList(data!.buffer.asUint8List());
  });
  if (unmount) await tester.pumpWidget(const SizedBox());
  return result!;
}

Uint8List encode(img.Image image) => Uint8List.fromList(img.encodePng(image));
int _snapshot = 0;

void main() {
  testWidgets('fine periodic ink retains its area average after minification', (
    tester,
  ) async {
    final source = img.Image(width: 768, height: 768, numChannels: 4);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        final ink = x % 3 == 0 ? 255 : 0;
        source.setPixelRgba(x, y, ink, ink, ink, 255);
      }
    }
    final result = await pixels(tester, encode(source));
    final samples = <int>[];
    for (var y = 8; y < 56; y++) {
      for (var x = 8; x < 56; x++) {
        samples.add(result[(y * 64 + x) * 4]);
      }
    }
    expect(samples.reduce((a, b) => a + b) / samples.length, closeTo(85, 10));
    expect(
      samples.reduce((a, b) => a > b ? a : b) -
          samples.reduce((a, b) => a < b ? a : b),
      lessThan(8),
    );
  });

  testWidgets('source ink outside the viewport participates in the Gaussian', (
    tester,
  ) async {
    final source = img.Image(width: 192, height: 192, numChannels: 4);
    img.fill(source, color: img.ColorRgba8(0, 0, 0, 255));
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < 8; x++) {
        source.setPixelRgba(x, y, 255, 0, 0, 255);
      }
    }
    // At sigma 45, zoom 1.10 clips over eight source pixels on each side.
    // The red ink is entirely outside the visible crop before convolution.
    final result = await pixels(
      tester,
      encode(source),
      sigma: 45,
      width: 32,
      height: 32,
    );
    expect(result[(16 * 32) * 4], greaterThan(5));
    expect(result[(16 * 32) * 4 + 1], 0);
  });

  testWidgets(
    'transparent texture remains uniform through every blurred edge',
    (tester) async {
      final source = img.Image(width: 32, height: 32, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(0, 255, 0, 128));
      final result = await pixels(tester, encode(source), sigma: 30);
      for (final (x, y) in [
        (0, 0),
        (63, 0),
        (0, 63),
        (63, 63),
        (32, 32),
        (0, 32),
      ]) {
        final offset = (y * 64 + x) * 4;
        expect(result[offset], 0);
        expect(result[offset + 1], closeTo(255, 1));
        expect(result[offset + 3], closeTo(128, 1));
      }
    },
  );

  testWidgets(
    'wide artwork preserves centered cover framing and aspect ratio',
    (tester) async {
      final source = img.Image(width: 192, height: 96, numChannels: 4);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          source.setPixelRgba(x, y, x, y * 2, 0, 255);
        }
      }
      final result = await pixels(
        tester,
        encode(source),
        sigma: 0,
        width: 96,
        height: 96,
      );
      for (final (x, y) in [(0, 0), (95, 95), (48, 48), (0, 48)]) {
        final offset = (y * 96 + x) * 4;
        expect(result[offset], closeTo(x + 48, 1));
        expect(result[offset + 1], closeTo(y * 2, 1));
      }
    },
  );

  testWidgets(
    'elapsed playback and foreground changes retain the native Gaussian and image',
    (tester) async {
      final source = img.Image(width: 32, height: 32, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(255, 0, 0, 255));
      final bytes = encode(source);
      Widget background(Uint8List cover, String label) => MaterialApp(
        home: CustomThemeBackground(
          path: null,
          enabled: false,
          dim: .6,
          coverEnabled: true,
          coverBytes: cover,
          coverBlurSigma: 32,
          child: Text(label),
        ),
      );
      await tester.pumpWidget(background(bytes, 'cover'));
      await resolveImage(tester);
      final state = tester.state(find.byType(Image));
      final provider = tester.widget<Image>(find.byType(Image)).image;
      final filter = tester
          .widget<ImageFiltered>(find.byType(ImageFiltered))
          .imageFilter;
      final painter = tester
          .widget<CustomPaint>(
            find.byWidgetPredicate(
              (widget) => widget is CustomPaint && widget.painter != null,
            ),
          )
          .painter!;
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(seconds: 30));
      }
      await tester.pumpWidget(background(Uint8List.fromList(bytes), 'lyrics'));
      expect(tester.state(find.byType(Image)), same(state));
      expect(tester.widget<Image>(find.byType(Image)).image, provider);
      expect(
        tester.widget<ImageFiltered>(find.byType(ImageFiltered)).enabled,
        isTrue,
      );
      expect(
        tester.widget<ImageFiltered>(find.byType(ImageFiltered)).imageFilter,
        same(filter),
      );
      final next = tester
          .widget<CustomPaint>(
            find.byWidgetPredicate(
              (widget) => widget is CustomPaint && widget.painter != null,
            ),
          )
          .painter!;
      expect(next.shouldRepaint(painter), isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'replacing artwork displays the current song without remounting the image',
    (tester) async {
      final captureKey = GlobalKey();
      State? imageState;
      for (final color in [
        img.ColorRgba8(255, 0, 0, 255),
        img.ColorRgba8(0, 0, 255, 255),
      ]) {
        final source = img.Image(width: 32, height: 32, numChannels: 4);
        img.fill(source, color: color);
        final result = await pixels(
          tester,
          encode(source),
          captureKey: captureKey,
          unmount: false,
        );
        imageState ??= tester.state(find.byType(Image));
        expect(tester.state(find.byType(Image)), same(imageState));
        expect(result[(32 * 64 + 32) * 4], closeTo(color.r, 1));
        expect(result[(32 * 64 + 32) * 4 + 2], closeTo(color.b, 1));
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
