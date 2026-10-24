import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/playback_progress_slider.dart';
import 'package:myune_music/services/lyric_sync_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Position extends ValueNotifier<Duration> {
  _Position() : super(Duration.zero);
  bool get listening => hasListeners;
}

void main() {
  testWidgets(
    'subpixel updates do not rebuild slider; preview and seek stay immediate',
    (tester) async {
      final p = _Position(), preview = ValueNotifier<double?>(null);
      var visible = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, set) {
                update = set;
                return MediaQuery(
                  data: const MediaQueryData(devicePixelRatio: 3),
                  child: TickerMode(
                    enabled: visible,
                    child: Center(
                      child: SizedBox(
                        width: 360,
                        child: PlaybackProgressSlider(
                          position: p,
                          preview: preview,
                          totalMs: 240000,
                          onStart: (_) {},
                          onChanged: (v) => preview.value = v,
                          onEnd: (_) {},
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      var old = tester.widget<Slider>(find.byType(Slider));
      var rebuilds = 0;
      for (var i = 1; i <= 100; i++) {
        p.value = Duration(milliseconds: i * 10);
        await tester.pump();
        final next = tester.widget<Slider>(find.byType(Slider));
        if (!identical(next, old)) rebuilds++;
        old = next;
      }
      expect(rebuilds, lessThan(22));
      expect((old.value - 1000).abs(), lessThan(65));
      preview.value = 12345;
      await tester.pump();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 12345);
      preview.value = null;
      p.value = const Duration(seconds: 100);
      await tester.pump();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 100000);
      update(() => visible = false);
      await tester.pump();
      expect(p.listening, isFalse);
      p.value = const Duration(seconds: 101);
      update(() => visible = true);
      await tester.pump();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 101000);
      await tester.pumpWidget(const SizedBox());
      expect(p.listening, isFalse);
      p.dispose();
      preview.dispose();
    },
  );
  test(
    'same-song sync lookups are stable and song offsets remain independent',
    () async {
      SharedPreferences.setMockInitialValues({});
      final sync = LyricSyncPreferences();
      await sync.initializationFuture;
      var changes = 0;
      sync.addListener(() => changes++);
      sync.useSong('C:\\Music\\A.mp3');
      await sync.setSong(123);
      final before = changes;
      for (var i = 0; i < 10000; i++) {
        sync.useSong('C:\\Music\\A.mp3');
      }
      expect(changes, before);
      expect(
        sync.visualPosition(const Duration(seconds: 1)),
        const Duration(milliseconds: 877),
      );
      sync.useSong('C:/Music/B.mp3');
      expect(sync.songDelayMs, 0);
      sync.useSong('c:/music/a.mp3');
      expect(sync.songDelayMs, 123);
      sync.dispose();
    },
  );
}
