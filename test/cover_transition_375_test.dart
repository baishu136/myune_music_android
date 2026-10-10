import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:myune_music/widgets/gaussian_artwork_surface.dart';

void main() {
  testWidgets(
    'decoded cover fades with bounded layers and latest rapid target',
    (tester) async {
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
              child: GaussianArtworkSurface(
                provider: MemoryImage(bytes),
                sigma: 8,
                transitionDuration: const Duration(milliseconds: 450),
              ),
            ),
          ),
        ),
      );
      Future<void> decode() async {
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
      }

      Future<List<int>> center() async => (await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        final bytes = data!.buffer.asUint8List();
        return [bytes[2112], bytes[2113], bytes[2114], bytes[2115]];
      }))!;
      final red = cover(255, 0, 0), blue = cover(0, 0, 255);
      await tester.pumpWidget(host(red));
      await decode();
      final state = tester.state(find.byType(Image));
      expect((await center()).first, 255);
      await tester.pumpWidget(host(blue));
      await decode();
      expect(tester.state(find.byType(Image)), same(state));
      expect(
        (await center()).first,
        255,
        reason: 'decode starts fade from old image',
      );
      await tester.pump(const Duration(milliseconds: 225));
      final mid = await center();
      expect(mid[0], inInclusiveRange(110, 145));
      expect(mid[2], inInclusiveRange(110, 145));
      expect(mid[3], 255);
      await tester.pumpWidget(host(cover(255, 255, 0)));
      await decode();
      await tester.pumpWidget(host(cover(0, 255, 0)));
      await decode();
      expect(find.byType(ImageFiltered), findsNWidgets(2));
      await tester.pump(const Duration(milliseconds: 225));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(await center(), [0, 255, 0, 255]);
      expect(find.byType(ImageFiltered), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
