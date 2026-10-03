import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/services/foreground_lifecycle.dart';

void main() {
  test('temporary focus loss preserves visible UI work', () {
    expect(foregroundAfterLifecycle(AppLifecycleState.inactive, true), isTrue);
    expect(foregroundAfterLifecycle(AppLifecycleState.resumed, true), isTrue);
  });

  test('background return starts work only when resumed', () {
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      expect(foregroundAfterLifecycle(state, true), isFalse);
    }
    expect(
      foregroundAfterLifecycle(AppLifecycleState.inactive, false),
      isFalse,
    );
    expect(foregroundAfterLifecycle(AppLifecycleState.resumed, false), isTrue);
  });
}
