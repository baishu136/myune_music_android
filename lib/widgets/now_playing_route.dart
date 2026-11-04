import 'package:flutter/cupertino.dart';

import 'now_playing_cover_hero.dart';

/// Retain the player's slide/interactive back gesture and Hero flight, adding
/// depth to both pages on the same route clock. No independent controller.
class NowPlayingRoute extends CupertinoPageRoute<void> {
  NowPlayingRoute({required super.builder, super.allowSnapshotting});

  @override
  Duration get transitionDuration => nowPlayingRouteTransitionDuration;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 460);

  @override
  DelegatedTransitionBuilder get delegatedTransition => _homeTransition;

  static Widget _homeTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    bool allowSnapshotting,
    Widget? child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return child ?? const SizedBox.shrink();
    }
    final progress = secondaryAnimation.drive(
      CurveTween(curve: Curves.easeInOutCubic),
    );
    return ScaleTransition(
      key: const ValueKey('player-home-scale'),
      scale: progress.drive(Tween(begin: 1.0, end: .965)),
      child: CupertinoPageTransition.delegatedTransition(
        context,
        animation,
        secondaryAnimation,
        allowSnapshotting,
        child,
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final progress = animation.drive(CurveTween(curve: Curves.easeInOutCubic));
    return super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      ScaleTransition(
        key: const ValueKey('player-entry-scale'),
        scale: progress.drive(Tween(begin: 1.035, end: 1.0)),
        child: child,
      ),
    );
  }
}
