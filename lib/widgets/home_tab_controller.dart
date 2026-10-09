part of 'home_tab_viewport.dart';

/// Navigation intent, not a physical multi-page offset. `page` reports the
/// settled endpoint; no intermediate index is exposed during a far jump.
class HomeTabController extends ChangeNotifier {
  HomeTabController({int initialPage = 0})
    : _index = initialPage,
      _target = initialPage;
  int _index, _target;
  bool _moving = false, _disposed = false;
  _HomeTabViewportState? _client;
  int get index => _index;
  int get targetIndex => _target;
  double? get page => hasClients ? _index.toDouble() : null;
  bool get hasClients => _client != null && !_disposed;
  bool get isTransitioning => _moving;
  Set<int> get preparedPages =>
      Set.unmodifiable(_client?._prepared ?? const <int>{});
  Future<void> animateToPage(
    int index, {
    Duration duration = homeTabTransitionDuration,
    Curve curve = homeTabTransitionCurve,
  }) {
    if (_disposed) return Future.value();
    if (_client == null || duration <= Duration.zero) {
      jumpToPage(index);
      return Future.value();
    }
    return _client!._navigate(index, duration, curve);
  }

  void jumpToPage(int index) {
    if (_disposed) return;
    if (hasClients) {
      _client!._snap(index);
    } else {
      _report(index, index, false);
    }
  }

  void _attach(_HomeTabViewportState client, int index) {
    assert(
      _client == null,
      'A home controller can attach to only one viewport',
    );
    _client = client;
    _index = _target = index;
    _moving = false;
  }

  void _detach(_HomeTabViewportState client) {
    if (_client == client) {
      _client = null;
      _moving = false;
    }
  }

  void _report(int index, int target, bool moving) {
    if (_disposed) return;
    final changed = _index != index || _target != target || _moving != moving;
    _index = index;
    _target = target;
    _moving = moving;
    // Intent and settlement only, no global listeners/timers per paint frame.
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _client?._cancelRequests();
    _client = null;
    _disposed = true;
    super.dispose();
  }
}

class _HomeTabRequest {
  _HomeTabRequest(this.index, this.duration, this.curve);
  final int index;
  final Duration duration;
  final Curve curve;
  final done = Completer<void>();
  void complete() {
    if (!done.isCompleted) done.complete();
  }
}
