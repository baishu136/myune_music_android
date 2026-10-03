import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/lyric_frame_clock.dart';

void main() {
  testWidgets('completed elastic consumers stop vsync inside notification', (
    tester,
  ) async {
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(_Host(key: key));
    final clock = key.currentState!.clock;
    late VoidCallback listener;
    listener = () {
      clock.removeListener(listener);
      clock.endElasticRow();
    };
    clock.beginElasticRow();
    clock.addListener(listener);
    expect(clock.visualMoving.value, isTrue);
    expect(clock.moving.value, isFalse);
    await tester.pump();
    expect(clock.visualMoving.value, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    expect(key.currentState!.motion, isEmpty);
  });
  testWidgets(
    'one vsync feeds motion and karaoke, and idles after last consumer',
    (tester) async {
      final key = GlobalKey<_HostState>();
      await tester.pumpWidget(_Host(key: key));
      final clock = key.currentState!.clock;
      final playback = <Duration>[];
      void listener() => playback.add(clock.elapsed);
      clock.addListener(listener);
      clock.setMoving(true);
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(microseconds: 8333));
      }
      expect(playback, key.currentState!.motion);
      final lastMotion = key.currentState!.motion.length;
      clock.setMoving(false);
      await tester.pump(const Duration(milliseconds: 16));
      expect(key.currentState!.motion.length, lastMotion);
      expect(playback.length, greaterThan(lastMotion));
      clock.removeListener(listener);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump(const Duration(seconds: 1));
      final frozen = clock.elapsed;
      clock.addListener(listener);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(clock.elapsed, lessThan(frozen));
      expect(clock.elapsed, const Duration(milliseconds: 16));
      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
}

class _Host extends StatefulWidget {
  const _Host({super.key});
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with SingleTickerProviderStateMixin {
  final motion = <Duration>[];
  late final LyricFrameClock clock;
  @override
  void initState() {
    super.initState();
    clock = LyricFrameClock(this, motion.add);
  }

  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
