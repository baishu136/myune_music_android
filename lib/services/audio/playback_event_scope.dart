import 'dart:async';

/// Owns player event subscriptions, including failures of async event handlers.
/// Closing gates queued deliveries immediately, before native cancellation ends.
class PlaybackEventScope {
  PlaybackEventScope({required this.onError});
  final void Function(Object, StackTrace) onError;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _closed = false;
  Future<void>? _closeFuture;

  void listen<T>(Stream<T> stream, FutureOr<void> Function(T) onData) {
    if (_closed) return;
    _subscriptions.add(
      stream.listen((event) {
        if (_closed) return;
        unawaited(Future<void>.sync(() => onData(event)).catchError(_report));
      }, onError: _report),
    );
  }

  void _report(Object error, StackTrace stack) {
    if (!_closed) onError(error, stack);
  }

  Future<void> close() => _closeFuture ??= _closeOnce();

  Future<void> _closeOnce() async {
    _closed = true;
    final subscriptions = List<StreamSubscription<dynamic>>.of(_subscriptions);
    _subscriptions.clear();
    await Future.wait(
      subscriptions.map((subscription) async {
        try {
          await subscription.cancel();
        } catch (error, stack) {
          onError(error, stack);
        }
      }),
    );
  }
}
