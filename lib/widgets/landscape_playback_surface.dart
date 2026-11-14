import 'dart:math' as math;
import 'package:flutter/material.dart';

enum LandscapeCoverMode { standard, centered, duet, info }

/// Retains one cover and one lyric subtree across the three presentations.
class LandscapePlaybackSurface extends StatefulWidget {
  const LandscapePlaybackSurface({
    super.key,
    required this.landscape,
    required this.mode,
    required this.showLyrics,
    this.expandedLyrics = true,
    this.information = const SizedBox.shrink(),
    this.onFullscreenLyrics,
    this.coverScale = 1,
    this.maxCoverSize = 520,
    required this.cover,
    required this.lyrics,
    required this.title,
    required this.artist,
    required this.onModeChanged,
  });
  final bool landscape, showLyrics;
  final bool expandedLyrics;
  final double coverScale, maxCoverSize;
  final LandscapeCoverMode mode;
  final Widget cover, lyrics, information;
  final VoidCallback? onFullscreenLyrics;
  final String title, artist;
  final ValueChanged<LandscapeCoverMode> onModeChanged;

  @override
  State<LandscapePlaybackSurface> createState() =>
      _LandscapePlaybackSurfaceState();
}

class _LandscapePlaybackSurfaceState extends State<LandscapePlaybackSurface> {
  double _drag = 0;
  final _coverKey = GlobalKey();
  final _lyricsKey = GlobalKey();
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final cover = KeyedSubtree(key: _coverKey, child: widget.cover);
      final lyrics = KeyedSubtree(key: _lyricsKey, child: widget.lyrics);
      if (!widget.landscape) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage:
                  widget.mode != LandscapeCoverMode.standard &&
                  widget.showLyrics,
              child: cover,
            ),
            Offstage(
              offstage:
                  widget.mode != LandscapeCoverMode.standard &&
                  !widget.showLyrics,
              child: lyrics,
            ),
          ],
        );
      }
      final focused =
          widget.landscape && widget.mode != LandscapeCoverMode.standard;
      final duet = focused && widget.mode == LandscapeCoverMode.duet;
      final sideCover =
          duet || (focused && widget.mode == LandscapeCoverMode.info);
      final full = Offset.zero & box.biggest;
      final base = math.min(box.maxHeight, (box.maxWidth - 24) * .57);
      final size = math.min(base * .8, math.max(0.0, box.maxHeight - 72));
      final normalRect = widget.landscape
          ? Rect.fromLTWH(
              (box.maxWidth - 24) * .43 + 24,
              0,
              (box.maxWidth - 24) * .57,
              box.maxHeight,
            )
          : full;
      final coverRect = !focused
          ? normalRect
          : sideCover
          ? Rect.fromLTWH(0, 0, box.maxWidth * .43, box.maxHeight - 64)
          : Rect.fromLTWH(
              (box.maxWidth - size) / 2,
              (box.maxHeight - size - 64) / 2,
              size,
              size,
            );
      final paintedCoverSize = math.min(
        coverRect.shortestSide,
        math.min(coverRect.shortestSide, widget.maxCoverSize) *
            widget.coverScale,
      );
      final captionLeft =
          coverRect.left + (coverRect.width - paintedCoverSize) / 2;
      final lyricRect = duet
          ? Rect.fromLTWH(
              box.maxWidth * .46,
              0,
              box.maxWidth * .54,
              box.maxHeight,
            )
          : widget.landscape && !widget.expandedLyrics
          ? normalRect
          : full;
      Widget slot(String id, Rect target, Widget child) =>
          TweenAnimationBuilder<Rect?>(
            key: ValueKey((id, box.biggest)),
            tween: RectTween(end: target),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: child,
            builder: (_, rect, child) => Positioned.fromRect(
              rect: rect!,
              child: ClipRect(
                child: OverflowBox(
                  minWidth: target.width,
                  maxWidth: target.width,
                  minHeight: target.height,
                  maxHeight: target.height,
                  child: child,
                ),
              ),
            ),
          );
      return Stack(
        fit: StackFit.expand,
        children: [
          slot(
            'landscape-cover-slot',
            coverRect,
            IgnorePointer(
              ignoring: widget.showLyrics && !focused,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: !focused
                    ? null
                    : () {
                        if (widget.mode == LandscapeCoverMode.centered) {
                          widget.onModeChanged(LandscapeCoverMode.info);
                        } else if (widget.mode == LandscapeCoverMode.info) {
                          widget.onModeChanged(LandscapeCoverMode.centered);
                        }
                      },
                onHorizontalDragStart:
                    !widget.landscape || (widget.showLyrics && !focused)
                    ? null
                    : (_) => _drag = 0,
                onHorizontalDragUpdate:
                    !widget.landscape || (widget.showLyrics && !focused)
                    ? null
                    : (d) => _drag += d.delta.dx,
                onHorizontalDragEnd:
                    !widget.landscape || (widget.showLyrics && !focused)
                    ? null
                    : (details) {
                        final speed = details.primaryVelocity ?? 0;
                        final v = _drag.abs() >= 40 ? _drag.sign * 200 : speed;
                        if (v < -180 &&
                            widget.mode == LandscapeCoverMode.standard) {
                          widget.onModeChanged(LandscapeCoverMode.centered);
                        } else if (v < -180 &&
                            (widget.mode == LandscapeCoverMode.centered ||
                                widget.mode == LandscapeCoverMode.info)) {
                          widget.onModeChanged(LandscapeCoverMode.duet);
                        } else if (v < -180 &&
                            widget.mode == LandscapeCoverMode.duet) {
                          widget.onFullscreenLyrics?.call();
                        } else if (v > 180 &&
                            (widget.mode == LandscapeCoverMode.duet ||
                                widget.mode == LandscapeCoverMode.info)) {
                          widget.onModeChanged(LandscapeCoverMode.centered);
                        } else if (v > 180 &&
                            widget.mode == LandscapeCoverMode.centered) {
                          widget.onModeChanged(LandscapeCoverMode.standard);
                        }
                      },
                child: cover,
              ),
            ),
          ),
          slot(
            'landscape-lyrics-slot',
            lyricRect,
            IgnorePointer(
              ignoring: !widget.showLyrics && !duet,
              child: Opacity(
                opacity: widget.showLyrics || duet ? 1 : 0,
                child: ExcludeSemantics(
                  excluding: !widget.showLyrics && !duet,
                  child: lyrics,
                ),
              ),
            ),
          ),
          if (focused && widget.mode == LandscapeCoverMode.info)
            Positioned(
              left: box.maxWidth * .46,
              top: 0,
              right: 0,
              bottom: 0,
              child: widget.information,
            ),
          if (focused)
            Positioned(
              left: captionLeft,
              width: paintedCoverSize,
              top:
                  coverRect.top + (coverRect.height + paintedCoverSize) / 2 + 4,
              height: 60,
              child: IgnorePointer(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        widget.artist,
                        style: Theme.of(context).textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
