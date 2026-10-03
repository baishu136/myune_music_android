import 'package:flutter/foundation.dart';

/// Seek is an event, not merely a position value. Two replays/jumps to zero
/// must both reset visual clocks, even when the previous target was also zero.
class LyricSeekNotifier extends ValueNotifier<Duration?> {
  LyricSeekNotifier() : super(null);

  void publish(Duration target) {
    if (value == target) {
      notifyListeners();
    } else {
      value = target;
    }
  }
}
