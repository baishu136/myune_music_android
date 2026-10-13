import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/services/lyric_seek_notifier.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';
import 'karaoke_continuity_test.dart' as fixture;

void main() {
  testWidgets(
    'screen width change settles the new line geometry in its first frame',
    (tester) async {
      final lines = List.generate(
        8,
        (i) => LyricLine(
          timestamp: Duration(seconds: i * 10),
          texts: ['这是需要在窄屏上折成多行的歌词 some continuous words $i'],
        ),
      );
      final source = ValueNotifier(const Duration(seconds: 21));
      addTearDown(source.dispose);
      Widget host(double width) => MaterialApp(
        home: Center(
          child: SizedBox(
            width: width,
            height: 500,
            child: MobileLyricsList(
              lines: lines,
              active: 2,
              isPlaying: true,
              positionListenable: source,
              karaokeLyricsMode: KaraokeLyricsMode.all,
            ),
          ),
        ),
      );
      await tester.pumpWidget(host(260));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(host(500));
      final row = find.byKey(const ValueKey('mobile_lyric_2'));
      final firstY = tester.getCenter(row).dy;
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getCenter(row).dy, closeTo(firstY, .01));
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'screen suspension preserves pose and resumes without elapsed catch-up',
    (tester) async {
      final source = ValueNotifier(const Duration(milliseconds: 1000));
      addTearDown(source.dispose);
      await tester.pumpWidget(fixture.host(source, preparing: false));
      await tester.pump(const Duration(milliseconds: 200));
      final Duration before = fixture.painter(tester).positionListenable.value;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      source.value = const Duration(milliseconds: 4000);
      await tester.pump(const Duration(seconds: 3));
      expect(fixture.painter(tester).positionListenable.value, before);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      final Duration revealed = fixture
          .painter(tester)
          .positionListenable
          .value;
      expect(revealed, const Duration(milliseconds: 4000));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        (fixture.painter(tester).positionListenable.value - revealed)
            .inMilliseconds,
        inInclusiveRange(0, 18),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('page source replacement never rewinds the active glyph pose', (
    tester,
  ) async {
    final live = ValueNotifier(const Duration(milliseconds: 1000));
    final frozen = ValueNotifier(const Duration(milliseconds: 1000));
    addTearDown(live.dispose);
    addTearDown(frozen.dispose);
    await tester.pumpWidget(fixture.host(live, preparing: false));
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pump(const Duration(milliseconds: 160));
    final Duration before = fixture.painter(tester).positionListenable.value;
    await tester.pumpWidget(fixture.host(frozen, preparing: false));
    expect(fixture.painter(tester).positionListenable.value, before);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        fixture.painter(tester).positionListenable.value,
        greaterThanOrEqualTo(before),
      );
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'hidden lyrics sleep and reveal without a muted ticker catch-up',
    (tester) async {
      final source = ValueNotifier(const Duration(milliseconds: 1000));
      final seek = LyricSeekNotifier();
      addTearDown(source.dispose);
      addTearDown(seek.dispose);
      Widget host(bool visible) => MaterialApp(
        home: TickerMode(
          enabled: visible,
          child: SizedBox(
            width: 360,
            height: 640,
            child: MobileLyricsList(
              lines: fixture.lines,
              active: 0,
              isPlaying: true,
              positionListenable: source,
              seekPositionListenable: seek,
              entryPreparing: !visible,
              karaokeLyricsMode: KaraokeLyricsMode.all,
            ),
          ),
        ),
      );
      await tester.pumpWidget(host(true));
      await tester.pump(const Duration(milliseconds: 200));
      final Duration before = fixture.painter(tester).positionListenable.value;
      await tester.pumpWidget(host(false));
      expect(fixture.painter(tester).positionListenable.value, before);
      source.value = const Duration(milliseconds: 3000);
      await tester.pump(const Duration(seconds: 2));
      expect(fixture.painter(tester).positionListenable.value, before);
      await tester.pumpWidget(host(true));
      final Duration revealed = fixture
          .painter(tester)
          .positionListenable
          .value;
      expect(revealed, const Duration(milliseconds: 3000));
      await tester.pump(const Duration(milliseconds: 16));
      final Duration next = fixture.painter(tester).positionListenable.value;
      expect((next - revealed).inMilliseconds, inInclusiveRange(0, 18));
      seek.publish(const Duration(milliseconds: 500));
      await tester.pump();
      expect(
        fixture.painter(tester).positionListenable.value,
        const Duration(milliseconds: 500),
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
}
