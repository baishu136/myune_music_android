import 'package:flutter/material.dart';

/// The cover only participates in the route Hero while the cover page is the
/// visible playback surface. A retained, transparent cover must not fly back
/// over the home page when the user exits from lyrics.
bool shouldEnableNowPlayingCoverHero({
  required bool showLyrics,
  required bool routeTransitionComplete,
  required bool initialCoverHeroReady,
}) => !showLyrics && (routeTransitionComplete || initialCoverHeroReady);

class NowPlayingCoverHero extends StatelessWidget {
  const NowPlayingCoverHero({
    super.key,
    required this.normalizedSongPath,
    required this.child,
    this.enabled = true,
  });

  final String normalizedSongPath;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return HeroMode(
      enabled: enabled,
      child: Hero(
        tag: 'now-playing-cover-$normalizedSongPath',
        transitionOnUserGestures: true,
        // Keep one endpoint's already-decoded image for the complete flight.
        // This prevents the overlay from swapping between 192px and large
        // providers while its bounds are changing every frame.
        flightShuttleBuilder:
            (
              flightContext,
              animation,
              direction,
              fromHeroContext,
              toHeroContext,
            ) {
              final endpoint = direction == HeroFlightDirection.push
                  ? toHeroContext.widget
                  : fromHeroContext.widget;
              final endpointHero = endpoint as Hero;
              return RepaintBoundary(child: endpointHero.child);
            },
        child: child,
      ),
    );
  }
}
