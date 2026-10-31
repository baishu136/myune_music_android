import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'interaction_motion.dart';

/// Owns click feedback separately from page navigation: tapping the selected
/// destination replays its icon without navigating or rebuilding the page.
class MyuneNavigationBar extends StatefulWidget {
  const MyuneNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  @override
  State<MyuneNavigationBar> createState() => _MyuneNavigationBarState();
}

class _MyuneNavigationBarState extends State<MyuneNavigationBar> {
  final _tapRevisions = List<int>.filled(5, 0);
  static const _destinations = [
    (IconMotion.library, '音乐库'),
    (IconMotion.playlist, '歌单'),
    (IconMotion.artist, '歌手'),
    (IconMotion.album, '专辑'),
    (IconMotion.settings, '设置'),
  ];
  @override
  Widget build(BuildContext context) => NavigationBar(
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    animationDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 300),
    selectedIndex: widget.selectedIndex,
    onDestinationSelected: (index) {
      setState(() => _tapRevisions[index]++);
      widget.onDestinationSelected(index);
    },
    destinations: [
      for (var i = 0; i < _destinations.length; i++)
        NavigationDestination(
          icon: NavigationMotionIcon(
            kind: _destinations[i].$1,
            selected: widget.selectedIndex == i,
            interactionRevision: _tapRevisions[i],
          ),
          label: _destinations[i].$2,
        ),
    ],
  );
}

/// Keeps NavigationBar's native indicator, colours, labels and semantics.
class NavigationMotionIcon extends StatefulWidget {
  const NavigationMotionIcon({
    super.key,
    required this.kind,
    required this.selected,
    this.interactionRevision = 0,
  });
  final IconMotion kind;
  final bool selected;
  final int interactionRevision;
  @override
  State<NavigationMotionIcon> createState() => _NavigationMotionIconState();
}

class _NavigationMotionIconState
    extends InteractionMotionState<NavigationMotionIcon>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    value: 1,
    animationBehavior: AnimationBehavior.preserve,
  );
  late double _fillFrom, _fillTarget;
  int _timelineMs = 440, _fillMs = 300;
  bool _accent = false;

  double get _fill {
    if (_fillFrom == _fillTarget) return _fillTarget;
    final t = (_controller.value * _timelineMs / _fillMs).clamp(0.0, 1.0);
    return _fillFrom +
        (_fillTarget - _fillFrom) * Curves.fastOutSlowIn.transform(t);
  }

  @override
  void initState() {
    super.initState();
    _fillFrom = _fillTarget = widget.selected ? 1 : 0;
  }

  @override
  void resetMotion() {
    _controller.stop();
    _fillFrom = _fillTarget = widget.selected ? 1 : 0;
    _accent = false;
    if (_controller.value != 1) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant NavigationMotionIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!motionAllowed) {
      resetMotion();
    } else if (oldWidget.selected != widget.selected) {
      // Capture visible coverage before changing the shared timeline. A rapid
      // reversal starts here, rather than flashing the outlined/filled endpoint.
      _fillFrom = _fill;
      _fillTarget = widget.selected ? 1 : 0;
      _fillMs = widget.selected ? 300 : 220;
      _timelineMs = widget.selected
          ? iconMotionDuration(widget.kind).inMilliseconds
          : _fillMs;
      _accent = widget.selected;
      _controller.duration = Duration(milliseconds: _timelineMs);
      _controller.forward(from: 0);
    } else if (widget.selected &&
        oldWidget.interactionRevision != widget.interactionRevision &&
        !_controller.isAnimating) {
      // A reselect plays the detail accent while keeping its settled solid ink.
      _fillFrom = _fillTarget = 1;
      _accent = true;
      _timelineMs = iconMotionDuration(widget.kind).inMilliseconds;
      _controller.duration = Duration(milliseconds: _timelineMs);
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final phase = _accent && widget.selected ? _controller.value : 1.0;
        return buildIconMotion(
          widget.kind,
          phase,
          NavigationGlyph(
            kind: widget.kind,
            phase: phase,
            selected: widget.selected,
            fillProgress: _fill,
          ),
          active: widget.selected,
        );
      },
    ),
  );
}

/// One rounded 24-unit family, drawn at the inherited size and colour. Detail
/// motion stays inside the silhouette rather than spinning an entire button.
class NavigationGlyph extends StatelessWidget {
  const NavigationGlyph({
    super.key,
    required this.kind,
    required this.phase,
    required this.selected,
    this.fillProgress,
  });
  final IconMotion kind;
  final double phase;
  final bool selected;
  final double? fillProgress;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final color = theme.color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox.square(
      dimension: theme.size ?? 24,
      child: CustomPaint(
        painter: _NavigationDetailPainter(
          kind,
          phase,
          selected,
          color.withValues(alpha: color.a * (theme.opacity ?? 1)),
          (fillProgress ?? (selected ? 1.0 : 0.0)).clamp(0.0, 1.0),
        ),
      ),
    );
  }
}

class _NavigationDetailPainter extends CustomPainter {
  const _NavigationDetailPainter(
    this.kind,
    this.phase,
    this.selected,
    this.color,
    this.fillProgress,
  );
  final IconMotion kind;
  final double phase;
  final bool selected;
  final Color color;
  final double fillProgress;
  static final _back = Path()
    ..moveTo(3, 6.5)
    ..lineTo(3, 19)
    ..quadraticBezierTo(3, 21, 5, 21)
    ..lineTo(17, 21);
  static final _shoulders = Path()
    ..moveTo(4.2, 20)
    ..lineTo(4.2, 18)
    ..cubicTo(4.2, 12.4, 19.8, 12.4, 19.8, 18)
    ..lineTo(19.8, 20)
    ..close();
  static final _gear = _gearPath();
  static final _noteStem = Path()
    ..moveTo(0, 0)
    ..lineTo(0, -7)
    ..lineTo(3, -7.8)
    ..lineTo(3, -4.9);
  static final _front = RRect.fromRectAndRadius(
    const Rect.fromLTRB(7, 3, 21, 17.8),
    const Radius.circular(2),
  );
  static final _librarySolid = Path.combine(
    PathOperation.difference,
    Path()..addRRect(_front),
    _noteHole().shift(const Offset(15.4, 13.1)),
  );
  static Path _noteHole() => Path.combine(
    PathOperation.union,
    Path()..addOval(const Rect.fromLTRB(-4.05, -1.45, .65, 2.05)),
    Path()..addPolygon(const [
      Offset(-.82, .3),
      Offset(-.82, -7.6),
      Offset(3.82, -8.8),
      Offset(3.82, -4.9),
      Offset(2.18, -4.9),
      Offset(2.18, -6.7),
      Offset(.82, -6.35),
      Offset(.82, .3),
    ], true),
  );
  static final _gearSolid = Path.combine(
    PathOperation.difference,
    _gear,
    Path()..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 3.1)),
  );
  static final _recordSolid = _recordPath();
  static Path _recordPath() {
    final holes = Path()
      ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 1.65));
    for (final start in [-.85, 2.3]) {
      const sweep = 1.05, outer = 6.875, inner = 5.325;
      final groove = Path()
        ..arcTo(
          Rect.fromCircle(center: const Offset(12, 12), radius: outer),
          start,
          sweep,
          true,
        )
        ..lineTo(
          12 + inner * math.cos(start + sweep),
          12 + inner * math.sin(start + sweep),
        )
        ..arcTo(
          Rect.fromCircle(center: const Offset(12, 12), radius: inner),
          start + sweep,
          -sweep,
          false,
        )
        ..close();
      final caps = Path();
      for (final angle in [start, start + sweep]) {
        caps.addOval(
          Rect.fromCircle(
            center: Offset(
              12 + 6.1 * math.cos(angle),
              12 + 6.1 * math.sin(angle),
            ),
            radius: .775,
          ),
        );
      }
      holes.addPath(
        Path.combine(PathOperation.union, groove, caps),
        Offset.zero,
      );
    }
    return Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 9)),
      holes,
    );
  }

  static Path _gearPath() {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      for (var j = 0; j < 4; j++) {
        final angle = (i + (j - 1.5) * .21) * math.pi / 4;
        final radius = j == 1 || j == 2 ? 9.1 : 7.4;
        final x = 12 + radius * math.cos(angle);
        final y = 12 + radius * math.sin(angle);
        if (i == 0 && j == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
    }
    return path..close();
  }

  double _accent([double delay = 0]) =>
      selected ? iconMotionAccent(phase, delay: delay) : 0;

  // Anticipate briefly, turn, then ease into a rotationally identical endpoint.
  double _turn(double angle) {
    if (!selected || phase <= 0 || phase >= 1) return 0;
    double smooth(double t) => t * t * (3 - 2 * t);
    if (phase < .1) return -.06 * smooth(phase / .1);
    if (phase < .86) {
      return -.06 + (angle + .085) * smooth((phase - .1) / .76);
    }
    return angle + .025 * (1 - smooth((phase - .86) / .14));
  }

  void _around(Canvas canvas, Offset pivot, double angle) {
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(angle);
    canvas.translate(-pivot.dx, -pivot.dy);
  }

  void _note(Canvas canvas, Paint pen, Paint fill, double x, double y) {
    canvas.save();
    canvas.translate(x, y);
    canvas.drawPath(_noteStem, pen);
    canvas.drawOval(const Rect.fromLTRB(-4.05, -1.45, .65, 2.05), fill);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..strokeWidth = 1.8 + .25 * fillProgress
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final fill = Paint()..color = color;
    if (kind == IconMotion.library) {
      canvas.drawPath(_back, pen);
      canvas.save();
      canvas.translate(0, -.65 * _accent(.08));
      _around(canvas, const Offset(14, 11), -.04 * _accent(.04));
      canvas.drawRRect(_front, pen);
      final edge = 17.8 - 16 * fillProgress;
      if (fillProgress > 0) {
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(6, edge, 22, 19));
        canvas.drawPath(_librarySolid, fill);
        canvas.restore();
      }
      if (fillProgress < 1) {
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(5, 0, 23, edge));
        _note(canvas, pen, fill, 15.4, 13.1);
        canvas.restore();
      }
      canvas.restore();
    } else if (kind == IconMotion.playlist) {
      for (var i = 0; i < 3; i++) {
        final shift = 1.45 * _accent(i * .09);
        final y = 6.0 + i * 5.0;
        pen.strokeWidth = 1.8 + 1.2 * fillProgress;
        canvas.drawLine(
          Offset(3 + shift, y),
          Offset((i == 2 ? 9 : 11.5) + shift, y),
          pen,
        );
      }
      pen.strokeWidth = 1.8 + .25 * fillProgress;
      canvas.save();
      canvas.translate(0, -.8 * _accent(.16));
      _note(canvas, pen, fill, 17.7, 17);
      canvas.restore();
    } else if (kind == IconMotion.artist) {
      canvas.save();
      canvas.translate(0, -.25 * _accent(.12));
      canvas.drawPath(_shoulders, pen);
      if (fillProgress > 0) {
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(3, 20 - 7 * fillProgress, 21, 21));
        canvas.drawPath(_shoulders, fill);
        canvas.restore();
      }
      canvas.restore();
      canvas.save();
      _around(canvas, const Offset(12, 11), .11 * _accent());
      canvas.translate(0, -.5 * _accent());
      canvas.drawCircle(const Offset(12, 6.8), 3.3, pen);
      if (fillProgress > 0) {
        canvas.drawCircle(const Offset(12, 6.8), 3.3 * fillProgress, fill);
      }
      canvas.restore();
    } else if (kind == IconMotion.album) {
      canvas.drawCircle(const Offset(12, 12), 9, pen);
      canvas.save();
      _around(canvas, const Offset(12, 12), _turn(2 * math.pi));
      final opening = 9 * (1 - fillProgress);
      if (fillProgress > 0) {
        canvas.save();
        final mask = Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(const Rect.fromLTRB(0, 0, 24, 24));
        if (opening > 0) {
          mask.addOval(
            Rect.fromCircle(center: const Offset(12, 12), radius: opening),
          );
        }
        canvas.clipPath(mask);
        canvas.drawPath(_recordSolid, fill);
        canvas.restore();
      }
      if (fillProgress < 1) {
        canvas.save();
        canvas.clipPath(
          Path()..addOval(
            Rect.fromCircle(center: const Offset(12, 12), radius: opening),
          ),
        );
        canvas.drawCircle(const Offset(12, 12), 1.65, fill);
        pen.strokeWidth = 1.55;
        canvas.drawArc(
          Rect.fromCircle(center: const Offset(12, 12), radius: 6.1),
          -.85,
          1.05,
          false,
          pen,
        );
        canvas.drawArc(
          Rect.fromCircle(center: const Offset(12, 12), radius: 6.1),
          2.3,
          1.05,
          false,
          pen,
        );
        canvas.restore();
      }
      canvas.restore();
    } else if (kind == IconMotion.settings) {
      canvas.save();
      _around(canvas, const Offset(12, 12), _turn(math.pi / 4));
      canvas.drawPath(_gear, pen);
      if (fillProgress > 0) {
        canvas.save();
        canvas.clipPath(
          Path()..addOval(
            Rect.fromCircle(
              center: const Offset(12, 12),
              radius: 3.1 + 6.1 * fillProgress,
            ),
          ),
        );
        canvas.drawPath(_gearSolid, fill);
        canvas.restore();
      }
      canvas.restore();
      canvas.drawCircle(const Offset(12, 12), 3.1, pen);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NavigationDetailPainter oldDelegate) =>
      kind != oldDelegate.kind ||
      phase != oldDelegate.phase ||
      selected != oldDelegate.selected ||
      fillProgress != oldDelegate.fillProgress ||
      color != oldDelegate.color;
}
