import 'package:flutter/widgets.dart';

/// Published by the list clock. Retained row tweens hand off before a segment
/// restarts; no independent ticker or rounding of subpixel positions.
class LyricSharedFocus extends Animation<double> with ChangeNotifier {
  double _value = 1;
  double previousValue = 1;
  int generation = 0;
  @override
  double get value => _value;
  @override
  AnimationStatus get status =>
      _value >= 1 ? AnimationStatus.completed : AnimationStatus.forward;
  @override
  void addStatusListener(AnimationStatusListener listener) {}
  @override
  void removeStatusListener(AnimationStatusListener listener) {}
  void begin() {
    previousValue = _value;
    generation++;
    _value = 0;
    notifyListeners();
  }

  void update(double progress) {
    final next = progress.clamp(0.0, 1.0);
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }
}

class LyricSharedFocusScope extends InheritedWidget {
  const LyricSharedFocusScope({
    super.key,
    required this.phase,
    required super.child,
  });
  final LyricSharedFocus? phase;
  static LyricSharedFocus? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<LyricSharedFocusScope>()
      ?.phase;
  @override
  bool updateShouldNotify(LyricSharedFocusScope oldWidget) =>
      oldWidget.phase != phase;
}
