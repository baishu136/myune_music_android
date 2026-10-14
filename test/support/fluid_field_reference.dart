import 'dart:math' as math;
import 'dart:typed_data';

// Independent scalar reference for the bounded paint fields, used only in tests.
List<double> fluidReferenceWeights(Float32List values, double x, double y) {
  final width = values[0], height = values[1], motion = values[2];
  final scaleX = width / math.min(width, height),
      scaleY = height / math.min(width, height);
  final px = x + motion * .055 * math.sin(y * 2.3 + values[5]);
  final py = y + motion * .045 * math.sin(x * 2 - values[4]);
  double smooth(double t) => t * t * (3 - 2 * t);
  return List.generate(4, (field) {
    final shape = 29 + field * 4;
    final cx = values[6 + field * 2], cy = values[7 + field * 2];
    double dx(double a, double b) =>
        values[shape] * (a - cx) * scaleX +
        values[shape + 1] * (b - cy) * scaleY;
    double dy(double a, double b) =>
        values[shape + 2] * (a - cx) * scaleX +
        values[shape + 3] * (b - cy) * scaleY;
    final bound = dx(x, y) * dx(x, y) + dy(x, y) * dy(x, y);
    final window = 1 - smooth(((bound - .04) / .96).clamp(0.0, 1.0));
    final ax = dx(px, py), ay = dy(px, py);
    final bend = motion / (1 + ax * ax + ay * ay);
    final bx = ax + bend * .20 * ay * ay, by = ay + bend * .16 * ax * ay;
    final falloff = 1 / (1 + bx * bx + by * by);
    return (.65 + .35 * falloff) * window;
  });
}

double fluidReferenceCoverage(List<double> weights) {
  final sum = weights.fold<double>(0, (a, b) => a + b);
  return .84 * sum / (sum + .60);
}
