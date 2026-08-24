import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Decode targets for embedded artwork. These only affect display-time image
/// decoding and Flutter's image cache; the bytes in the music file are never
/// changed.
enum ArtworkSize {
  thumbnail(192),
  medium(256),
  groupLarge(720),
  large(768),
  original(null);

  const ArtworkSize(this.basePixels);

  final int? basePixels;

  int? resolvePixels(BuildContext? context, {double? logicalSize}) {
    if (this == ArtworkSize.original) return null;
    if (this != ArtworkSize.large || logicalSize == null || context == null) {
      return basePixels;
    }

    final physicalPixels =
        (logicalSize * MediaQuery.devicePixelRatioOf(context)).round();
    return math.max(basePixels!, math.min(1024, physicalPixels));
  }
}

ImageProvider<Object> artworkImageProvider(
  BuildContext? context,
  Uint8List bytes, {
  required ArtworkSize size,
  double? logicalSize,
}) {
  final targetPixels = size.resolvePixels(context, logicalSize: logicalSize);
  if (targetPixels == null) return MemoryImage(bytes);
  return CoverMemoryImage(bytes, targetPixels: targetPixels);
}

/// Returns the smallest proportional decode size that fully covers a square.
///
/// The old strategy requested an exact square from the codec, which stretched
/// non-square artwork before [BoxFit.cover] could crop it. This computes the
/// cover crop first, then downsamples proportionally to the minimum resolution
/// needed by the destination.
({int width, int height}) coverDecodeDimensions({
  required int intrinsicWidth,
  required int intrinsicHeight,
  required int targetPixels,
}) {
  assert(intrinsicWidth > 0);
  assert(intrinsicHeight > 0);
  assert(targetPixels > 0);
  final scale = math.min(
    1.0,
    math.max(targetPixels / intrinsicWidth, targetPixels / intrinsicHeight),
  );
  return (
    width: math.max(1, (intrinsicWidth * scale).round()),
    height: math.max(1, (intrinsicHeight * scale).round()),
  );
}

/// A memory image provider optimized for cover-cropped artwork.
///
/// It preserves the source aspect ratio while decoding only the pixels that a
/// square cover can use. The final center crop remains the responsibility of
/// the [Image] widget's [BoxFit.cover], so alignment continues to work.
@immutable
class CoverMemoryImage extends ImageProvider<CoverMemoryImage> {
  const CoverMemoryImage(this.bytes, {required this.targetPixels});

  final Uint8List bytes;
  final int targetPixels;

  @override
  Future<CoverMemoryImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<CoverMemoryImage>(this);

  @override
  ImageStreamCompleter loadImage(
    CoverMemoryImage key,
    ImageDecoderCallback decode,
  ) {
    assert(key == this);
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(decode),
      scale: 1,
      debugLabel: 'CoverMemoryImage(${describeIdentity(bytes)}, $targetPixels)',
    );
  }

  Future<ui.Codec> _loadAsync(ImageDecoderCallback decode) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(
      buffer,
      getTargetSize: (intrinsicWidth, intrinsicHeight) {
        final dimensions = coverDecodeDimensions(
          intrinsicWidth: intrinsicWidth,
          intrinsicHeight: intrinsicHeight,
          targetPixels: targetPixels,
        );
        return ui.TargetImageSize(
          width: dimensions.width,
          height: dimensions.height,
        );
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CoverMemoryImage &&
      other.bytes == bytes &&
      other.targetPixels == targetPixels;

  @override
  int get hashCode => Object.hash(bytes.hashCode, targetPixels);
}

/// An artwork image with a size-specific decode/cache key.
///
/// For large foreground artwork, [progressive] first reuses the 192px provider
/// (normally already warm after navigating from a song list) and fades in the
/// high-resolution decode when it is ready.
class ArtworkImage extends StatelessWidget {
  const ArtworkImage({
    super.key,
    required this.bytes,
    required this.size,
    this.logicalSize,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.medium,
    this.gaplessPlayback = true,
    this.progressive = false,
    this.errorBuilder,
  });

  final Uint8List bytes;
  final ArtworkSize size;
  final double? logicalSize;
  final double? width;
  final double? height;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final FilterQuality filterQuality;
  final bool gaplessPlayback;
  final bool progressive;
  final ImageErrorWidgetBuilder? errorBuilder;

  Image _image(
    BuildContext context,
    ImageProvider<Object> provider, {
    ImageFrameBuilder? frameBuilder,
    ImageErrorWidgetBuilder? imageErrorBuilder,
  }) {
    return Image(
      image: provider,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      filterQuality: filterQuality,
      gaplessPlayback: gaplessPlayback,
      frameBuilder: frameBuilder,
      errorBuilder: imageErrorBuilder ?? errorBuilder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fullProvider = artworkImageProvider(
      context,
      bytes,
      size: size,
      logicalSize: logicalSize,
    );
    if (!progressive ||
        (size != ArtworkSize.large && size != ArtworkSize.groupLarge)) {
      return _image(context, fullProvider);
    }

    final previewProvider = artworkImageProvider(
      context,
      bytes,
      size: ArtworkSize.thumbnail,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        _image(context, previewProvider),
        _image(
          context,
          fullProvider,
          imageErrorBuilder: (_, __, ___) => const SizedBox.shrink(),
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              child: child,
            );
          },
        ),
      ],
    );
  }
}
