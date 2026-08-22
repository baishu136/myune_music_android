import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/artwork_image.dart';

void main() {
  test('cover decode preserves landscape artwork proportions', () {
    final size = coverDecodeDimensions(
      intrinsicWidth: 1200,
      intrinsicHeight: 800,
      targetPixels: 128,
    );

    expect(size, (width: 192, height: 128));
    expect(size.width / size.height, 1.5);
  });

  test('cover decode preserves portrait artwork proportions', () {
    final size = coverDecodeDimensions(
      intrinsicWidth: 800,
      intrinsicHeight: 1200,
      targetPixels: 320,
    );

    expect(size, (width: 320, height: 480));
    expect(size.width / size.height, closeTo(2 / 3, 0.001));
  });

  test('cover decode never upscales small artwork', () {
    final size = coverDecodeDimensions(
      intrinsicWidth: 96,
      intrinsicHeight: 64,
      targetPixels: 128,
    );

    expect(size, (width: 96, height: 64));
  });
}
