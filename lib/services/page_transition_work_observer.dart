import 'package:flutter/widgets.dart';
import 'interaction_performance_controller.dart';

/// Applies the existing idle-work protection to ALL page routes, not only the
/// player. No UI listeners, global setState or per-frame callbacks are added.
class PageTransitionWorkObserver extends NavigatorObserver {
  void _protect(Route<dynamic>? route, {bool reverse = false}) {
    if (route is! TransitionRoute<dynamic>) return;
    final duration = reverse
        ? route.reverseTransitionDuration
        : route.transitionDuration;
    if (duration == Duration.zero) return;
    InteractionPerformanceController.instance.pulse(
      InteractionPhase.transition,
      settleAfter: duration + const Duration(milliseconds: 32),
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // The initial route is installed at its endpoint, with no push animation.
    if (previousRoute != null) _protect(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _protect(route, reverse: true);
  @override
  void didStartUserGesture(
    Route<dynamic> route,
    Route<dynamic>? previousRoute,
  ) => _protect(route, reverse: true);
}
