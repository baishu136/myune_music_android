part of 'home_tab_viewport.dart';

class _HomePageParentData extends ContainerBoxParentData<RenderBox> {
  int index = 0;
}

class _HomePageSlot extends ParentDataWidget<_HomePageParentData> {
  const _HomePageSlot({super.key, required this.index, required super.child});
  final int index;
  @override
  Type get debugTypicalAncestorWidgetClass => _HomeTabScene;
  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _HomePageParentData;
    if (data.index != index) {
      data.index = index;
      renderObject.parent?.markNeedsLayout();
    }
  }
}

class _HomeTabScene extends MultiChildRenderObjectWidget {
  const _HomeTabScene({
    required this.motion,
    required this.source,
    required this.destination,
    required this.direction,
    this.warming,
    required super.children,
  });
  final Animation<double> motion;
  final int source;
  final int? destination;
  final double direction;
  final int? warming;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHomeTabScene(motion, source, destination, direction, warming);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHomeTabScene renderObject,
  ) => renderObject.configure(motion, source, destination, direction, warming);
  @override
  MultiChildRenderObjectElement createElement() => _HomeTabSceneElement(this);
}

class _HomeTabSceneElement extends MultiChildRenderObjectElement {
  _HomeTabSceneElement(_HomeTabScene super.widget);
  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    final scene = widget as _HomeTabScene;
    for (final child in children) {
      final index = (child.widget as _HomePageSlot).index;
      if (index == scene.source || index == scene.destination) visitor(child);
    }
  }
}

/// Unlike IndexedStack/Offstage, navigation layout does not visit all retained
/// pages. Animation ticks invalidate paint, not layout or the widget tree.
class _RenderHomeTabScene extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _HomePageParentData> {
  _RenderHomeTabScene(
    this._motion,
    this._source,
    this._destination,
    this._direction,
    this._warming,
  );
  Animation<double> _motion;
  int _source;
  int? _destination;
  double _direction;
  int? _warming;
  int? _lastSemanticIndex;
  int get _semanticIndex =>
      _destination != null && _motion.value >= .5 ? _destination! : _source;
  void configure(
    Animation<double> motion,
    int source,
    int? destination,
    double direction,
    int? warming,
  ) {
    if (_motion != motion) {
      if (attached) _motion.removeListener(_onTick);
      _motion = motion;
      if (attached) _motion.addListener(_onTick);
    }
    if (_source != source ||
        _destination != destination ||
        _direction != direction ||
        _warming != warming) {
      _source = source;
      _destination = destination;
      _direction = direction;
      _warming = warming;
      markNeedsLayout();
      markNeedsSemanticsUpdate();
    }
  }

  void _onTick() {
    markNeedsPaint();
    if (_lastSemanticIndex != _semanticIndex) {
      _lastSemanticIndex = _semanticIndex;
      markNeedsSemanticsUpdate();
    }
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HomePageParentData) {
      child.parentData = _HomePageParentData();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _motion.addListener(_onTick);
  }

  @override
  void detach() {
    _motion.removeListener(_onTick);
    super.detach();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;
  @override
  void performLayout() {
    size = constraints.biggest;
    assert(size.isFinite, 'HomeTabViewport requires a bounded viewport');
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _HomePageParentData;
      if (data.index == _source ||
          data.index == _destination ||
          data.index == _warming) {
        child.layout(BoxConstraints.tight(size), parentUsesSize: true);
      }
      child = data.nextSibling;
    }
  }

  Offset _offset(RenderBox child) {
    final index = (child.parentData! as _HomePageParentData).index;
    if (_destination == null) return Offset.zero;
    return Offset(
      (index == _source ? -_motion.value : 1 - _motion.value) *
          size.width *
          _direction,
      0,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _HomePageParentData;
      if (data.index == _source || data.index == _destination) {
        final translation = _offset(child);
        if (translation.dx.abs() < size.width) {
          context.paintChild(child, offset + translation);
        }
      } else if (data.index == _warming) {
        // Record the real subtree/display lists outside the ancestor clip.
        // This prepares layout/paint, not a promise of GPU texture residency.
        context.paintChild(child, offset + Offset(size.width * 2, 0));
      }
      child = data.nextSibling;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (_destination != null) return false;
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _HomePageParentData;
      if (data.index == _source) {
        return result.addWithPaintOffset(
          offset: Offset.zero,
          position: position,
          hitTest: (result, position) =>
              child!.hitTest(result, position: position),
        );
      }
      child = data.nextSibling;
    }
    return false;
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final offset = _offset(child);
    transform.translateByDouble(offset.dx, offset.dy, 0, 1);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _HomePageParentData;
      if (data.index == _semanticIndex) visitor(child);
      child = data.nextSibling;
    }
  }
}
