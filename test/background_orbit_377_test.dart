import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:myune_music/widgets/custom_theme_background.dart';

void main() {
  testWidgets(
    'cover colour span changes actual fade duration without remount',
    (tester) async {
      Uint8List cover(int r, int g, int b, {int alpha = 255}) {
        final image = img.Image(width: 16, height: 16, numChannels: 4);
        img.fill(image, color: img.ColorRgba8(r, g, b, alpha));
        return Uint8List.fromList(img.encodePng(image));
      }

      Widget host(Uint8List bytes) => MaterialApp(
        home: SizedBox(
          width: 64,
          height: 64,
          child: CustomThemeBackground(
            path: null,
            enabled: false,
            dim: 0,
            coverEnabled: true,
            coverBytes: bytes,
            coverDim: 0,
            coverBlurSigma: 0,
            child: const SizedBox(),
          ),
        ),
      );
      Future<void> ready() async {
        for (var i = 0; i < 12; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
      }

      Duration duration() {
        final fade = tester
            .widgetList<FadeTransition>(find.byType(FadeTransition))
            .firstWhere((w) => w.opacity is CurvedAnimation);
        return ((fade.opacity as CurvedAnimation).parent as AnimationController)
            .duration!;
      }

      await tester.pumpWidget(host(cover(255, 0, 0)));
      await ready();
      final state = tester.state(find.byType(Image));
      await tester.pumpWidget(host(cover(248, 3, 0)));
      await ready();
      final near = duration();
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(cover(0, 0, 255)));
      await ready();
      final far = duration();
      expect(near, lessThan(far));
      expect(near.inMilliseconds, inInclusiveRange(280, 400));
      expect(far.inMilliseconds, inInclusiveRange(1200, 1400));
      debugPrint(
        'Adaptive cover fade: near=${near.inMilliseconds}ms, '
        'far=${far.inMilliseconds}ms',
      );
      expect(tester.state(find.byType(Image)), same(state));
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(cover(255, 0, 0, alpha: 128)));
      await ready();
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(cover(0, 0, 255, alpha: 128)));
      await ready();
      final translucent = duration();
      expect(translucent.inMilliseconds, inInclusiveRange(900, 1000));
      debugPrint(
        'Adaptive translucent cover fade: '
        '${translucent.inMilliseconds}ms',
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('adaptive rapid covers retain two layers and the latest target', (
    tester,
  ) async {
    final key = GlobalKey();
    Uint8List cover(int r, int g, int b) {
      final image = img.Image(width: 16, height: 16, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(r, g, b, 255));
      return Uint8List.fromList(img.encodePng(image));
    }

    Widget host(Uint8List bytes) => MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 32,
            height: 32,
            child: CustomThemeBackground(
              path: null,
              enabled: false,
              dim: 0,
              coverEnabled: true,
              coverBytes: bytes,
              coverDim: 0,
              coverBlurSigma: 8,
              child: const SizedBox(),
            ),
          ),
        ),
      ),
    );
    Future<void> ready() async {
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
    }

    await tester.pumpWidget(host(cover(255, 0, 0)));
    await ready();
    await tester.pumpWidget(host(cover(0, 0, 255)));
    await ready();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(host(cover(0, 255, 0)));
    await ready();
    final gold = cover(255, 220, 0);
    await tester.pumpWidget(host(gold));
    await ready();
    expect(find.byType(ImageFiltered), findsNWidgets(2));
    await tester.pump(const Duration(milliseconds: 1400));
    await ready();
    await tester.pumpAndSettle();
    expect(find.byType(ImageFiltered), findsOneWidget);
    final pixels = (await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      try {
        return (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }))!;
    const i = (16 * 32 + 16) * 4;
    expect(pixels.sublist(i, i + 4), [255, 220, 0, 255]);
    await tester.pumpWidget(host(Uint8List.fromList(gold)));
    await ready();
    expect(find.byType(ImageFiltered), findsOneWidget);
    // Tear down while a new image/profile can still be completing.
    await tester.pumpWidget(host(cover(0, 0, 255)));
    await tester.pumpWidget(const SizedBox());
    await ready();
    expect(tester.takeException(), isNull);
  });
}
