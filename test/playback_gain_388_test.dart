import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/services/audio/playback_entry_softening.dart';

void main() {
  test(
    'a late native failure after disposal cannot schedule a recovery write',
    () async {
      final reply = Completer<void>(), values = <double>[];
      final transition = PlaybackEntrySoftening((db) async {
        values.add(db);
        await reply.future;
      });
      final prepared = transition.prepare();
      transition.dispose();
      reply.completeError(StateError('late native rejection'));
      await prepared;
      expect(values, [-6]);
    },
  );
  test(
    'treble recovery is bounded and monotone, with no full-band gain ramp',
    () {
      expect(playbackEntryTrebleDb(0), -6);
      expect(playbackEntryTrebleDb(1), 0);
      var previous = -6.0;
      for (var i = 0; i <= 1000; i++) {
        final gain = playbackEntryTrebleDb(i / 1000);
        expect(gain, inInclusiveRange(previous, 0));
        previous = gain;
      }
      expect(playbackEntryTrebleDb(.5), -3);
    },
  );
  test(
    'cold decode waits for actual playing; rapid replacement restarts ramp',
    () async {
      final gains = <double>[];
      final fade = PlaybackEntrySoftening((gain) async => gains.add(gain));
      await fade.prepare();
      fade.begin(playing: false);
      await Future<void>.delayed(const Duration(milliseconds: 550));
      expect(gains, [-6]);
      fade.setPlaying(true);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(gains.last, inExclusiveRange(-6, 0));
      await fade.prepare();
      expect(gains.last, -6);
      fade.begin(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 550));
      expect(gains.last, 0);
      fade.dispose();
    },
  );
  test(
    'buffer pause freezes progress and cancel prevents late writes',
    () async {
      final gains = <double>[];
      final fade = PlaybackEntrySoftening((gain) async => gains.add(gain));
      await fade.prepare();
      fade.begin(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      fade.setPlaying(false);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final count = gains.length, pausedGain = gains.last;
      await Future<void>.delayed(const Duration(milliseconds: 520));
      expect(gains.length, count);
      fade.setPlaying(true);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(gains.last, greaterThan(pausedGain));
      expect(gains.last, lessThan(-1));
      await fade.cancel();
      expect(gains.last, 0);
      final stoppedCount = gains.length;
      await Future<void>.delayed(const Duration(milliseconds: 550));
      expect(gains.length, stoppedCount);
      fade.dispose();
    },
  );
  test(
    'slow native writes coalesce instead of replaying stale gain commands',
    () async {
      final gains = <double>[];
      final fade = PlaybackEntrySoftening((gain) async {
        gains.add(gain);
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await fade.prepare();
      fade.begin(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(gains.last, 0);
      expect(gains.length, lessThan(12));
      fade.dispose();
    },
  );
  test('unsupported gain falls back to unity and stops retrying', () async {
    final gains = <double>[];
    final fade = PlaybackEntrySoftening((gain) async {
      gains.add(gain);
      if (gain != 0) throw StateError('unsupported');
    });
    await fade.prepare();
    fade.begin(playing: true);
    await Future<void>.delayed(const Duration(milliseconds: 520));
    expect(gains, [-6, 0]);
    fade.dispose();
  });
}
