import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';

/// Independently implemented staggered whole-line motion, informed by
/// ZeroBit Player's spring-list behaviour (reference revision in docs/408).
/// The owning lyric list supplies its existing clock; no row ticker or timer.
class LyricStaggeredSpring extends ChangeNotifier {
  SpringSimulation? _simulation;
  double _elapsed = 0, _delay = 0, _value = 0, _velocity = 0;
  bool _settled = true;
  bool get settled => _settled;
  double offset(int row) => _value;
  double get velocity => _velocity;
  void configureRows(List<double> centres, double height) {}

  void retarget({
    required double displacement,
    required int step,
    required double position,
  }) {
    final ratio = position.clamp(0.0, 1.0);
    final alreadyMoving = !_settled && _elapsed >= _delay;
    _delay = alreadyMoving ? 0 : step.clamp(0, 20) * .026;
    _elapsed = 0;
    _value += displacement;
    _simulation = SpringSimulation(
      SpringDescription.withDampingRatio(
        mass: 1,
        stiffness: 175 - 20 * ratio,
        ratio: .86 - .08 * ratio,
      ),
      _value,
      0,
      _velocity,
      tolerance: const Tolerance(distance: .005, velocity: .1),
    );
    _settled = false;
    notifyListeners();
  }

  void tick(double time) {
    _elapsed = time;
    final t = _elapsed - _delay;
    if (t >= 0 && _simulation != null && !_settled) {
      _value = _simulation!.x(t);
      _velocity = _simulation!.dx(t);
      if (_simulation!.isDone(t)) {
        _settled = true;
        _value = _velocity = 0;
      }
    }
    notifyListeners();
  }

  void clear() {
    _simulation = null;
    _settled = true;
    _value = _velocity = 0;
    notifyListeners();
  }
}
