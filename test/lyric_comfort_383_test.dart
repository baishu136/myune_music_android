import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/widgets/lyric_elastic_motion.dart';
import 'package:myune_music/widgets/lyric_normalized_motion.dart';
import 'package:myune_music/widgets/lyric_scroll_motion.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';
import 'package:myune_music/widgets/lyric_raster_pool.dart';

void main() {
  testWidgets(
    'Chinese whole-line springs reuse the shared-budget glow raster',
    (tester) async {
      final key = GlobalKey<_HostState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: SizedBox(
              height: 500,
              width: 210,
              child: _Host(key: key, glow: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      MobileLyricGlowPainter pictureCache() => tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byKey(const ValueKey('mobile_lyric_0')),
              matching: find.byKey(const ValueKey('mobile_lyric_glow_layer')),
            ),
          )
          .map((w) => w.painter)
          .whereType<MobileLyricGlowPainter>()
          .first;
      for (var i = 0; i < 120 && pictureCache().preparedRaster == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      final raster = pictureCache().preparedRaster;
      expect(raster, isNotNull);
      expect(LyricRasterPool.pixels, lessThanOrEqualTo(LyricRasterPool.limit));
      key.currentState!.active(1);
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(pictureCache().preparedRaster, same(raster));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'delayed frames follow the analytic wall-time path without lost time',
    () {
      final delayed = LyricScrollMotion()
        ..sync(0)
        ..retarget(120);
      final regular = LyricScrollMotion()
        ..sync(0)
        ..retarget(120);
      delayed.advance(.16);
      for (var i = 0; i < 16; i++) {
        regular.advance(.01);
      }
      expect(delayed.offset, closeTo(regular.offset, 1e-8));
      expect(delayed.velocity, closeTo(regular.velocity, 1e-8));
      expect(delayed.offset, greaterThan(30));
    },
  );
  test('corrections start without a waiting period and end without a tail', () {
    for (final role in LyricElasticRole.values) {
      final motion = LyricElasticSegment(amplitude: 3, role: role);
      expect(motion.value(0), 0);
      expect(motion.velocity(0), 0);
      expect(motion.value(.68), 0);
      expect(motion.velocity(.68), 0);
      var peak = 0.0;
      for (var i = 1; i < 200; i++) {
        peak = peak > motion.value(i * .68 / 200).abs()
            ? peak
            : motion.value(i * .68 / 200).abs();
      }
      expect(peak, lessThanOrEqualTo(3));
      if (role != LyricElasticRole.arriving) {
        expect(motion.value(.03), greaterThan(0));
      }
    }
  });
  test(
    'finite corrections preserve position and velocity across retargets',
    () {
      final old = LyricElasticSegment(
        amplitude: 8,
        role: LyricElasticRole.surrounding,
      );
      final next = LyricElasticSegment(
        amplitude: 2,
        role: LyricElasticRole.departing,
        initialOffset: old.value(.18),
        initialVelocity: old.velocity(.18),
      );
      expect(next.value(0), old.value(.18));
      expect(next.velocity(0), closeTo(old.velocity(.18), 1e-9));
      expect(next.value(.68), 0);
      expect(next.velocity(.68), 0);
    },
  );
  test(
    'elastic focus retains default arrival then adds only a small rebound',
    () {
      const arrival = LyricElasticArrivalCurve(),
          retreat = LyricElasticRetreatCurve();
      for (final t in [.05, .1, .2, .4, .6, .7]) {
        expect(
          arrival.transform(t),
          closeTo(lyricTransitionCurve.transform(t), 1e-9),
        );
      }
      expect(arrival.transform(.85), greaterThan(1));
      expect(arrival.transform(.85), lessThan(1.05));
      expect(retreat.transform(.1), lessThan(retreat.transform(.2) / 3));
      expect(retreat.transform(.88), inExclusiveRange(1, 1.06));
      expect(arrival.transform(1), 1);
      expect(retreat.transform(1), 1);
    },
  );
  test('60/90/120 Hz corrections share the same wall-time pose', () {
    final motion = LyricElasticSegment(
      amplitude: -6,
      role: LyricElasticRole.surrounding,
    );
    for (final hz in [60, 90, 120]) {
      expect(motion.value((hz ~/ 3) / hz), closeTo(motion.value(1 / 3), 1e-12));
    }
  });
  testWidgets(
    'Chinese wrapped paragraphs move as one line and let the clock sleep',
    (tester) async {
      final key = GlobalKey<_HostState>();
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(height: 500, width: 210, child: _Host(key: key)),
        ),
      );
      await tester.pumpAndSettle();
      final physicalLayouts = debugElasticPhysicalLayoutCount;
      key.currentState!.active(1);
      await tester.pump();
      Transform transform() => tester.widget<Transform>(
        find.byKey(const ValueKey('mobile_lyric_elastic_transform_1')),
      );
      final initial = transform().transform.storage[13];
      expect(initial.abs(), greaterThan(10));
      await tester.pump(const Duration(milliseconds: 340));
      expect(transform().transform.storage[13], isNot(initial));
      expect(
        debugElasticPhysicalLayoutCount,
        physicalLayouts,
        reason: 'whole rows must not create split-band layouts',
      );
      await tester.pumpAndSettle();
      expect(transform().transform.storage[13], 0);
      expect(tester.binding.hasScheduledFrame, false);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'ordinary and elastic row entries both retain their first-frame position',
    (tester) async {
      for (final elastic in [false, true]) {
        final key = GlobalKey<_HostState>();
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              height: 500,
              child: _Host(key: key, elastic: elastic, chinese: false),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final before = tester.getCenter(
          find.byKey(const ValueKey('mobile_lyric_1')),
        );
        key.currentState!.active(1);
        await tester.pump();
        final after = tester.getCenter(
          find.byKey(const ValueKey('mobile_lyric_1')),
        );
        expect(after.dy, closeTo(before.dy, .01));
        await tester.pumpAndSettle();
      }
    },
  );
}

class _Host extends StatefulWidget {
  const _Host({
    super.key,
    this.elastic = true,
    this.chinese = true,
    this.glow = false,
  });
  final bool elastic, chinese, glow;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int _active = 0;
  late final lines = [
    for (var i = 0; i < 8; i++)
      LyricLine(
        timestamp: Duration(seconds: i * 2),
        texts: [
          widget.chinese ? '这是第$i行中文歌词需要按照实际屏幕折行保持舒缓自然的运动' : 'Line $i',
          if (widget.chinese) '这是翻译文本',
        ],
      ),
  ];
  void active(int i) => setState(() => _active = i);
  @override
  Widget build(BuildContext context) => MobileLyricsList(
    lines: lines,
    active: _active,
    scrollEffect: widget.elastic
        ? LyricScrollEffect.elastic
        : LyricScrollEffect.standard,
    karaokeLyricsEnabled: false,
    glowEnabled: widget.glow,
    glowRadius: 12,
    isPlaying: true,
    fontSize: 22,
    lineBlurEnabled: false,
    textAlign: TextAlign.left,
  );
}
