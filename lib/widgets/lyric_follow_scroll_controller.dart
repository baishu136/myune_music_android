import 'package:flutter/widgets.dart';

/// The shared lyric clock owns motion; keep one activity for its entire run.
class LyricFollowScrollController extends ScrollController {
  LyricFollowScrollController({super.initialScrollOffset});

  void followTo(double value) {
    if (!hasClients) return;
    (position as _FollowPosition).followTo(value);
  }

  void stopFollowing() {
    for (final position in positions) {
      (position as _FollowPosition).stopFollowing();
    }
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _FollowPosition(
    physics: physics,
    context: context,
    initialPixels: initialScrollOffset,
    keepScrollOffset: keepScrollOffset,
    oldPosition: oldPosition,
    debugLabel: debugLabel,
  );
}

class _FollowPosition extends ScrollPositionWithSingleContext {
  _FollowPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  void followTo(double value) {
    if (activity is! _FollowActivity) beginActivity(_FollowActivity(this));
    setPixels(value.clamp(minScrollExtent, maxScrollExtent));
  }

  void stopFollowing() {
    // A real drag, hold or ballistic gesture may already have taken ownership.
    if (activity is _FollowActivity) goIdle();
  }
}

class _FollowActivity extends ScrollActivity {
  _FollowActivity(super.delegate);
  @override
  bool get shouldIgnorePointer => false;
  @override
  bool get isScrolling => true;
  @override
  double get velocity => 0;
}
