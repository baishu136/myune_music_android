import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../models/fluid_background_state.dart';
import '../artwork_image.dart';
import '../custom_theme_background.dart';
import 'fluid_background.dart';

class PlaybackBackground extends StatefulWidget {
  const PlaybackBackground({
    super.key,
    required this.style,
    required this.artworkIdentity,
    required this.artworkCacheGeneration,
    required this.routeTransitionActive,
    this.routeTransitionListenable,
    required this.fluidQuality,
    required this.fallbackSeed,
    required this.path,
    required this.customImageEnabled,
    required this.customImageDim,
    required this.customImageBlur,
    required this.coverBytes,
    required this.coverEnabled,
    required this.coverDim,
    required this.coverBlur,
    required this.usePlaybackTheme,
    required this.child,
    this.paletteArtworkBytes,
    this.rhythmFrames,
  });

  final PlaybackArtworkBackgroundStyle style;
  final String artworkIdentity;
  final int artworkCacheGeneration;
  final bool routeTransitionActive;
  final ValueListenable<bool>? routeTransitionListenable;
  final FluidBackgroundQuality fluidQuality;
  final Color fallbackSeed;
  final String? path;
  final bool customImageEnabled;
  final double customImageDim;
  final double customImageBlur;
  final Uint8List? coverBytes;
  final Uint8List? paletteArtworkBytes;
  final Stream<FftFrame>? rhythmFrames;
  final bool coverEnabled;
  final double coverDim;
  final double coverBlur;
  final bool usePlaybackTheme;
  final Widget child;

  @override
  State<PlaybackBackground> createState() => _PlaybackBackgroundState();
}

class _PlaybackBackgroundState extends State<PlaybackBackground> {
  late PlaybackArtworkBackgroundStyle _displayedStyle;
  late PlaybackArtworkBackgroundStyle _requestedStyle;
  int _styleChangeGeneration = 0;

  bool get _useFluid =>
      _displayedStyle == PlaybackArtworkBackgroundStyle.fluid &&
      widget.coverEnabled;

  @override
  void initState() {
    super.initState();
    _displayedStyle = widget.style;
    _requestedStyle = widget.style;
  }

  @override
  void didUpdateWidget(covariant PlaybackBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.style == _requestedStyle) return;
    _requestedStyle = widget.style;
    if (_requestedStyle == _displayedStyle) {
      _styleChangeGeneration++;
      return;
    }
    _prepareStyleSwitch(_requestedStyle);
  }

  Future<void> _prepareStyleSwitch(PlaybackArtworkBackgroundStyle next) async {
    final generation = ++_styleChangeGeneration;
    // The fluid renderer always has a synchronous gradient fallback. A
    // blurred cover must decode first; retaining the old background until
    // then prevents a transparent frame during the style switch.
    if (next == PlaybackArtworkBackgroundStyle.blurred &&
        widget.coverEnabled &&
        widget.coverBytes != null &&
        widget.coverBytes!.isNotEmpty) {
      try {
        await precacheImage(
          artworkImageProvider(
            context,
            widget.coverBytes!,
            size: ArtworkSize.medium,
          ),
          context,
        ).timeout(const Duration(milliseconds: 220));
      } catch (_) {
        // The normal image error path remains available after the transition.
      }
    }
    if (!mounted || generation != _styleChangeGeneration) return;
    setState(() => _displayedStyle = next);
  }

  Widget _buildBackground() {
    if (_useFluid) {
      return FluidPlaybackBackground(
        key: const ValueKey('playback-background-fluid'),
        artworkBytes: widget.paletteArtworkBytes ?? widget.coverBytes,
        artworkIdentity: widget.artworkIdentity,
        artworkCacheGeneration: widget.artworkCacheGeneration,
        fallbackSeed: widget.fallbackSeed,
        dim: widget.coverDim,
        quality: widget.fluidQuality,
        routeTransitionActive: widget.routeTransitionActive,
        routeTransitionListenable: widget.routeTransitionListenable,
        rhythmFrames: widget.rhythmFrames,
        child: const SizedBox.expand(),
      );
    }
    return CustomThemeBackground(
      key: const ValueKey('playback-background-cover'),
      path: widget.path,
      enabled: widget.customImageEnabled,
      dim: widget.customImageDim,
      blurSigma: widget.customImageBlur,
      coverBytes: widget.coverBytes,
      coverEnabled: widget.coverEnabled,
      coverDim: widget.coverDim,
      coverBlurSigma: widget.coverBlur,
      brightnessOverride: widget.usePlaybackTheme ? Brightness.dark : null,
      child: const SizedBox.expand(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: widget.fallbackSeed),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          reverseDuration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            fit: StackFit.expand,
            children: [
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          ),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: RepaintBoundary(child: child),
          ),
          child: _buildBackground(),
        ),
        widget.child,
      ],
    );
  }

  @override
  void dispose() {
    _styleChangeGeneration++;
    super.dispose();
  }
}
