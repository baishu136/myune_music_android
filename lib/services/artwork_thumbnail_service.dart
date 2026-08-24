import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as image;

import '../widgets/artwork_image.dart';

/// Creates the only artwork representation used by scrolling collections.
/// Heavy decoding/cropping is kept off the UI isolate.
class ArtworkThumbnailService {
  const ArtworkThumbnailService({this.size = 256});

  final int size;

  Future<Uint8List?> create(Uint8List source) async {
    if (source.isEmpty) return null;

    // Let Flutter's codec sample the encoded source before any pixel buffer is
    // materialized. A 256px thumbnail therefore works from a roughly 512px
    // intermediate instead of fully decoding a multi-megapixel cover.
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? decoded;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(source);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final workingPixels = size * 2;
      final dimensions = artworkWorkingDecodeDimensions(
        intrinsicWidth: descriptor.width,
        intrinsicHeight: descriptor.height,
        workingPixels: workingPixels,
      );
      codec = await descriptor.instantiateCodec(
        targetWidth: dimensions.width,
        targetHeight: dimensions.height,
      );
      final frame = await codec.getNextFrame();
      decoded = frame.image;
      final rgba = await decoded.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) return null;
      // Capture only sendable scalar values before entering the worker
      // isolate. Referencing [decoded] in the closure captures a dart:ui Image,
      // which cannot cross isolate boundaries and made thumbnail creation fail.
      final decodedWidth = decoded.width;
      final decodedHeight = decoded.height;
      final bytes = rgba.buffer.asUint8List(
        rgba.offsetInBytes,
        rgba.lengthInBytes,
      );
      return Isolate.run(
        () => createArtworkThumbnailFromRgba(
          bytes,
          decodedWidth,
          decodedHeight,
          size,
        ),
      );
    } catch (_) {
      return null;
    } finally {
      decoded?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}

/// Keeps the short edge near 384/512px while preserving aspect ratio before
/// the final square crop. The long edge is bounded to avoid pathological
/// panoramic artwork producing a very large intermediate buffer.
({int width, int height}) artworkWorkingDecodeDimensions({
  required int intrinsicWidth,
  required int intrinsicHeight,
  required int workingPixels,
}) {
  final dimensions = coverDecodeDimensions(
    intrinsicWidth: intrinsicWidth,
    intrinsicHeight: intrinsicHeight,
    targetPixels: workingPixels,
  );
  final longest = dimensions.width > dimensions.height
      ? dimensions.width
      : dimensions.height;
  final maximumLongest = workingPixels * 4;
  if (longest <= maximumLongest) return dimensions;
  final scale = maximumLongest / longest;
  return (
    width: (dimensions.width * scale).round().clamp(1, maximumLongest),
    height: (dimensions.height * scale).round().clamp(1, maximumLongest),
  );
}

/// Visible for unit tests. The crop is applied before compression so artwork
/// never gets stretched into a square.
Uint8List? createArtworkThumbnail(Uint8List source, int size) {
  final decoded = image.decodeImage(source);
  if (decoded == null) return null;
  final oriented = image.bakeOrientation(decoded);
  final square = image.copyResizeCropSquare(
    oriented,
    size: size,
    interpolation: image.Interpolation.average,
  );
  return Uint8List.fromList(image.encodeJpg(square, quality: 82));
}

Uint8List createArtworkThumbnailFromRgba(
  Uint8List rgba,
  int width,
  int height,
  int size,
) {
  final decoded = image.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
    order: image.ChannelOrder.rgba,
  );
  final square = image.copyResizeCropSquare(
    decoded,
    size: size,
    interpolation: image.Interpolation.average,
  );
  return Uint8List.fromList(image.encodeJpg(square, quality: 84));
}
