import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'artwork_image.dart';

const nowPlayingCoverReplacementDuration = Duration(milliseconds: 320);

/// Resolve the latest source on its own notifications, not a captured parent
/// snapshot. Keep ONE Image element across pending -> prepared provider changes
/// so gaplessPlayback can actually retain the previous decoded frame.
class NowPlayingCoverImage extends StatelessWidget {
  const NowPlayingCoverImage({
    super.key,
    required this.changes,
    required this.readImage,
    required this.size,
    this.onImageError,
    this.transitionsEnabled = true,
  });

  final Listenable changes;
  final ImageProvider<Object>? Function() readImage;
  final double size;
  final ValueChanged<ImageProvider<Object>>? onImageError;
  final bool transitionsEnabled;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: changes,
    builder: (context, _) {
      Widget placeholder() => ColoredBox(
        key: const ValueKey('now-playing-cover-placeholder'),
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Center(child: Icon(Icons.music_note, size: size * .5)),
      );
      final image = readImage();
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.square(
          dimension: size,
          child: image == null
              ? placeholder()
              : Image(
                  key: const ValueKey('now-playing-cover-image'),
                  image: image,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                  excludeFromSemantics: true,
                  // Image still owns resolution/listening and retains its old
                  // decoded frame while pending. Animate decoded pixels, NOT
                  // provider keys: a new key can arrive before any image does.
                  frameBuilder: (context, child, frame, synchronous) =>
                      Semantics(
                        image: true,
                        child: _DecodedCoverTransition(
                          image: (child as RawImage).image,
                          content: _coverContent(image),
                          ready: frame != null,
                          invertColors: child.invertColors,
                          size: size,
                          enabled:
                              transitionsEnabled &&
                              !MediaQuery.disableAnimationsOf(context),
                        ),
                      ),
                  errorBuilder: (context, error, stack) {
                    // A failed byte candidate is rejected outside build. The
                    // normal source notifier can then publish its fallback.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (context.mounted) {
                        onImageError?.call(image);
                      }
                    });
                    return placeholder();
                  },
                ),
        ),
      );
    },
  );
}

/// Only two displayed frames and one latest queued frame; clones retain the
/// backing pixels when Image releases its previous ImageInfo. They are disposed
/// on completion/replacement/unmount. The queue preserves the visible blend on
/// rapid switches rather than abruptly dropping an in-flight old layer.
class _DecodedCoverTransition extends StatefulWidget {
  const _DecodedCoverTransition({
    required this.image,
    required this.content,
    required this.ready,
    required this.invertColors,
    required this.size,
    required this.enabled,
  });
  final ui.Image? image;
  final Object? content;
  final bool ready;
  final bool invertColors;
  final double size;
  final bool enabled;

  @override
  State<_DecodedCoverTransition> createState() =>
      _DecodedCoverTransitionState();
}

class _DecodedCoverTransitionState extends State<_DecodedCoverTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: nowPlayingCoverReplacementDuration,
    value: 1,
  )..addStatusListener(_onStatus);
  late final CurvedAnimation _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );
  late final Animation<double> _incomingScale = _opacity.drive(
    Tween(begin: 1.16, end: 1.0),
  );
  late final Animation<double> _outgoingScale = _opacity.drive(
    Tween(begin: 1.0, end: .84),
  );
  ui.Image? _current;
  ui.Image? _previous;
  ui.Image? _queued;
  Object? _currentContent, _queuedContent;

  @override
  void initState() {
    super.initState();
    _current = widget.image?.clone();
    _currentContent = widget.ready ? widget.content : null;
  }

  bool _same(ui.Image? a, ui.Image? b) =>
      a == null || b == null ? a == b : a.isCloneOf(b);

  @override
  void didUpdateWidget(covariant _DecodedCoverTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    final image = widget.image;
    if (!widget.enabled) {
      _controller.stop();
      _previous?.dispose();
      _previous = null;
      _queued?.dispose();
      _queued = null;
      if (!_same(image, _current)) {
        _current?.dispose();
        _current = image?.clone();
      }
      _currentContent = widget.ready ? widget.content : _currentContent;
      _queuedContent = null;
      _controller.value = 1;
      return;
    }
    if (!widget.ready) {
      // A newer pending request invalidates an obsolete decoded queue entry.
      // Never label gapless old pixels as the new requested artwork.
      if (widget.content != _queuedContent) {
        _queued?.dispose();
        _queued = null;
        _queuedContent = null;
      }
      return;
    }
    // Gapless pending frames and source/cache notifications don't restart it.
    if (_same(image, _current) || widget.content == _currentContent) {
      if (!_same(image, _current)) {
        _current?.dispose();
        _current = image?.clone();
      }
      _currentContent = widget.content;
      _queued?.dispose();
      _queued = null;
      _queuedContent = null;
      return;
    }
    if (image == null ||
        _same(image, _queued) ||
        widget.content == _queuedContent) {
      return;
    }
    if (_controller.isAnimating) {
      _queued?.dispose();
      _queued = image.clone();
      _queuedContent = widget.content;
    } else {
      _replace(image.clone(), widget.content);
    }
  }

  void _replace(ui.Image image, Object? content) {
    _currentContent = content;
    _previous?.dispose();
    _previous = _current;
    _current = image;
    if (_previous == null) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _previous?.dispose();
    _previous = null;
    final queued = _queued;
    _queued = null;
    final content = _queuedContent;
    _queuedContent = null;
    if (queued != null) _replace(queued, content);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatus);
    _opacity.dispose();
    _controller.dispose();
    _current?.dispose();
    _previous?.dispose();
    _queued?.dispose();
    super.dispose();
  }

  Widget _pixels(ui.Image? image, String key) => RawImage(
    key: ValueKey(key),
    image: image,
    width: widget.size,
    height: widget.size,
    fit: BoxFit.cover,
    filterQuality: FilterQuality.high,
    invertColors: widget.invertColors,
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_previous != null)
          ScaleTransition(
            key: const ValueKey('now-playing-cover-outgoing-scale'),
            scale: _outgoingScale,
            child: RepaintBoundary(
              child: _pixels(_previous, 'now-playing-cover-previous'),
            ),
          ),
        // Keep the old cover opaque below the incoming fade. Two opposing alpha
        // fades would darken the midpoint. No layout or per-frame source reads.
        FadeTransition(
          key: const ValueKey('now-playing-cover-fade'),
          opacity: _opacity,
          child: ScaleTransition(
            key: const ValueKey('now-playing-cover-incoming-scale'),
            scale: _incomingScale,
            child: RepaintBoundary(
              child: _pixels(_current, 'now-playing-cover-current'),
            ),
          ),
        ),
      ],
    );
  }
}

final _coverHashes = Expando<int>();
Object _coverContent(ImageProvider image) {
  if (image is ResizeImage) return _coverContent(image.imageProvider);
  if (image is CoverMemoryImage) return _CoverContent(image.bytes);
  if (image is MemoryImage) return _CoverContent(image.bytes);
  return image;
}

class _CoverContent {
  _CoverContent(this.bytes)
    : hash = _coverHashes[bytes] ??= Object.hashAll(bytes);
  final List<int> bytes;
  final int hash;
  @override
  int get hashCode => hash;
  @override
  bool operator ==(Object other) =>
      other is _CoverContent &&
      hash == other.hash &&
      (identical(bytes, other.bytes) || listEquals(bytes, other.bytes));
}
