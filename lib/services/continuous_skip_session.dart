import 'package:flutter/foundation.dart';

/// Hold the lightweight playback path until all held gestures and loads end.
class ContinuousSkipSession extends ValueNotifier<bool> {
  ContinuousSkipSession() : super(false);
  final _holds = <Object>{};
  final _loads = <Object>{};
  bool _suspending = false, _disposed = false;

  VoidCallback hold() {
    if (_disposed) return () {};
    _suspending = true;
    return _retain(_holds);
  }

  VoidCallback trackLoad() => _disposed ? () {} : _retain(_loads);

  VoidCallback _retain(Set<Object> owners) {
    final token = Object();
    owners.add(token);
    _publish();
    return () {
      if (_disposed || !owners.remove(token)) return;
      _publish();
    };
  }

  void _publish() {
    if (_holds.isEmpty && _loads.isEmpty) _suspending = false;
    value = _suspending;
  }

  @override
  void dispose() {
    _disposed = true;
    _holds.clear();
    _loads.clear();
    super.dispose();
  }
}
