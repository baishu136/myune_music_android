import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:myune_music/services/artwork_thumbnail_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('runtime thumbnail worker returns encoded artwork', () async {
    final source = image.Image(width: 640, height: 480);
    image.fill(source, color: image.ColorRgb8(40, 120, 220));
    final encoded = Uint8List.fromList(image.encodeJpg(source));

    final bytes = await const ArtworkThumbnailService(
      size: 192,
    ).create(encoded);
    final decoded = bytes == null ? null : image.decodeImage(bytes);

    expect(bytes, isNotNull);
    expect(decoded?.width, 192);
    expect(decoded?.height, 192);
  });

  test('thumbnail is center-cropped without stretching', () {
    final source = image.Image(width: 240, height: 120);
    image.fillRect(
      source,
      x1: 0,
      y1: 0,
      x2: 119,
      y2: 119,
      color: image.ColorRgb8(255, 0, 0),
    );
    image.fillRect(
      source,
      x1: 120,
      y1: 0,
      x2: 239,
      y2: 119,
      color: image.ColorRgb8(0, 0, 255),
    );
    final encoded = Uint8List.fromList(image.encodePng(source));

    final bytes = createArtworkThumbnail(encoded, 128);
    final decoded = image.decodeImage(bytes!);

    expect(decoded?.width, 128);
    expect(decoded?.height, 128);
    expect(decoded!.getPixel(8, 64).r, greaterThan(decoded.getPixel(8, 64).b));
    expect(
      decoded.getPixel(120, 64).b,
      greaterThan(decoded.getPixel(120, 64).r),
    );
  });

  test('large source is sampled near the requested working edge', () {
    expect(
      artworkWorkingDecodeDimensions(
        intrinsicWidth: 4000,
        intrinsicHeight: 3000,
        workingPixels: 512,
      ),
      (width: 683, height: 512),
    );
    expect(
      artworkWorkingDecodeDimensions(
        intrinsicWidth: 3000,
        intrinsicHeight: 4000,
        workingPixels: 384,
      ),
      (width: 384, height: 512),
    );
  });

  test('extreme panoramas keep their sampled intermediate bounded', () {
    final dimensions = artworkWorkingDecodeDimensions(
      intrinsicWidth: 12000,
      intrinsicHeight: 1000,
      workingPixels: 512,
    );

    expect(dimensions.width, 2048);
    expect(dimensions.height, 171);
  });
}
