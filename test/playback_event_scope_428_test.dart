import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/services/audio/playback_event_scope.dart';

void main() {
  test(
    'event handlers run synchronously and report sync/async/stream failures',
    () async {
      final events = StreamController<int>.broadcast(sync: true);
      final failures = <Object>[];
      final seen = <int>[];
      final scope = PlaybackEventScope(onError: (e, _) => failures.add(e));
      final lateError = Completer<void>();
      scope.listen(events.stream, (value) {
        seen.add(value);
        if (value == 1) throw StateError('sync');
        if (value == 2) return lateError.future;
      });
      events.add(1);
      expect(seen, [1]);
      events.add(2);
      lateError.completeError(StateError('async'));
      events.addError(StateError('stream'));
      await Future<void>.delayed(Duration.zero);
      expect(
        failures.map((e) => e.toString()),
        containsAll([contains('sync'), contains('async'), contains('stream')]),
      );
      await scope.close();
      expect(events.hasListener, isFalse);
      await events.close();
    },
  );
  test(
    'close prevents queued events and ignores a pending handler error',
    () async {
      final events = StreamController<int>();
      final failures = <Object>[];
      final scope = PlaybackEventScope(onError: (e, _) => failures.add(e));
      final pending = Completer<void>();
      var calls = 0;
      scope.listen(events.stream, (_) {
        calls++;
        return pending.future;
      });
      events.add(1);
      await Future<void>.delayed(Duration.zero);
      events.add(2);
      final release = scope.close();
      pending.completeError(StateError('after close'));
      await release;
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      expect(failures, isEmpty);
      scope.listen(events.stream, (_) => calls++);
      expect(events.hasListener, isFalse);
      await events.close();
    },
  );
  test(
    'close callers share cancellation and cancellation errors are observed',
    () async {
      final cancel = Completer<void>();
      final events = StreamController<int>(onCancel: () => cancel.future);
      final failures = <Object>[];
      final scope = PlaybackEventScope(onError: (e, _) => failures.add(e));
      scope.listen(events.stream, (_) {});
      final first = scope.close(), second = scope.close();
      expect(first, same(second));
      var finished = false;
      unawaited(second.then((_) => finished = true));
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      cancel.completeError(StateError('cancel failed'));
      await first;
      expect(failures.single.toString(), contains('cancel failed'));
      await events.close();
    },
  );
  test(
    'duplicate completion pulses do not repeat a natural end action',
    () async {
      final events = StreamController<bool>.broadcast(sync: true);
      final scope = PlaybackEventScope(onError: (e, _) => fail('$e'));
      var advances = 0;
      scope.listen(events.stream.distinct(), (done) {
        if (done) advances++;
      });
      for (final done in [false, true, true, true, false, true, true]) {
        events.add(done);
      }
      expect(advances, 2);
      await scope.close();
      await events.close();
    },
  );
}
