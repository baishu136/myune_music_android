import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Decode targets for embedded artwork. These only affect display-time image
/// decoding and Flutter's image cache; the bytes in the music file are never
/// changed.
enum ArtworkSize {
  thumbnail(128),
  medium(320),
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
  final source = MemoryImage(bytes);
  if (targetPixels == null) return source;
  return ResizeImage.resizeIfNeeded(targetPixels, targetPixels, source);
}

/// An artwork image with a size-specific decode/cache key.
///
/// For large foreground artwork, [progressive] first reuses the 128px provider
/// (normally already warm after navigating from a song list) and fades in the
/// 768-1024px decode when it is ready.
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
    if (!progressive || size != ArtworkSize.large) {
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
