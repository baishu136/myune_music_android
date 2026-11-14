import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/widgets/compact_playback_lyrics.dart';
import 'package:myune_music/widgets/landscape_tools_panel.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';
import 'package:myune_music/widgets/playback_actions_menu.dart';

LyricLine timed() => LyricLine(
  timestamp: Duration.zero,
  texts: ['one two'],
  tokens: [
    [
      LyricToken(
        text: 'one ',
        start: Duration.zero,
        end: const Duration(seconds: 2),
      ),
      LyricToken(
        text: 'two',
        start: const Duration(seconds: 3),
        end: const Duration(seconds: 8),
      ),
    ],
  ],
);

void main() {
  test('ellipsis does not compress a long word into an earlier highlight', () {
    final token = LyricToken(
      text: 'ABCDEFGHIJKLMNO',
      start: Duration.zero,
      end: const Duration(seconds: 4),
    );
    CompactLyricInkLayout measure(double width) => CompactLyricInkLayout(
      text: token.text,
      style: const TextStyle(fontSize: 20),
      direction: TextDirection.ltr,
      scaler: TextScaler.noScaling,
      width: width,
      tokens: [token],
    );
    final narrow = measure(90), wide = measure(500);
    expect(narrow.spans.single.$3, wide.spans.single.$3);
    expect(narrow.spans.single.$2.last.right, lessThan(narrow.spans.single.$3));
    narrow.dispose();
    wide.dispose();
  });
  test('preview follows main karaoke opt-in, scope and synthetic timing', () {
    final line = timed();
    expect(
      compactKaraokeLine(line, enabled: false, mode: KaraokeLyricsMode.all),
      isNull,
    );
    expect(
      compactKaraokeLine(
        line,
        enabled: true,
        mode: KaraokeLyricsMode.timedOnly,
      ),
      same(line),
    );
    final plain = LyricLine(timestamp: Duration.zero, texts: ['Hello 世界']);
    expect(
      compactKaraokeLine(
        plain,
        enabled: true,
        mode: KaraokeLyricsMode.timedOnly,
      ),
      isNull,
    );
    final synthetic = compactKaraokeLine(
      plain,
      enabled: true,
      mode: KaraokeLyricsMode.all,
      next: const Duration(seconds: 4),
    )!;
    final main = synthesizeKaraokeTiming(
      plain,
      nextTimestamp: const Duration(seconds: 4),
    );
    expect(
      synthetic.tokens!.first.map((t) => (t.text, t.start, t.end)),
      main.tokens!.first.map((t) => (t.text, t.start, t.end)),
    );
  });

  testWidgets(
    'default preview never applies word ink even with live position',
    (tester) async {
      final position = ValueNotifier(const Duration(seconds: 1));
      await tester.pumpWidget(
        MaterialApp(
          home: CompactPlaybackLyrics(
            lines: [timed()],
            active: 0,
            position: position,
          ),
        ),
      );
      expect(find.byType(ShaderMask), findsNothing);
      expect(find.byKey(const ValueKey('compact-karaoke-ink')), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
      position.dispose();
    },
  );

  testWidgets(
    'production ink measures glyphs and shares pause, rate, seek and lifecycle clock',
    (tester) async {
      final position = ValueNotifier(const Duration(seconds: 1));
      final actual = ValueNotifier(true);
      final rate = ValueNotifier(2.0);
      final seek = ValueNotifier<Duration?>(null);
      final intent = ValueNotifier(0);
      final lines = [timed()];
      var visible = true;
      var enabled = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, set) {
              update = set;
              return TickerMode(
                enabled: visible,
                child: SizedBox(
                  width: 500,
                  child: CompactPlaybackLyrics(
                    lines: lines,
                    active: 0,
                    position: position,
                    isPlaying: true,
                    karaokeEnabled: enabled,
                    actualPlayback: actual,
                    rate: rate,
                    seek: seek,
                    seekIntent: intent,
                  ),
                ),
              );
            },
          ),
        ),
      );
      dynamic ink() => tester
          .widget<CustomPaint>(
            find.byKey(const ValueKey('compact-karaoke-ink')),
          )
          .foregroundPainter;
      final clock = ink().clock as KaraokeMediaClock;
      final layout = ink().layout as CompactLyricInkLayout;
      expect(layout.spans.first.$2.last.right, lessThan(150));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(clock.value.inMilliseconds, closeTo(1400, 5));
      expect(ink().layout, same(layout));
      actual.value = false;
      final paused = clock.value;
      await tester.pump(const Duration(seconds: 1));
      expect(clock.value, paused);
      intent.value++;
      seek.value = const Duration(seconds: 4);
      position.value = const Duration(seconds: 2);
      expect(clock.value, const Duration(seconds: 4));
      actual.value = true;
      rate.value = .5;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(clock.value.inMilliseconds, closeTo(4100, 5));
      update(() => visible = false);
      await tester.pump();
      final hidden = clock.value;
      await tester.pump(const Duration(seconds: 1));
      expect(clock.value, hidden);
      update(() => visible = true);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final background = clock.value;
      await tester.pump(const Duration(seconds: 1));
      expect(clock.value, background);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      update(() => enabled = false);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('compact-karaoke-ink')), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
      for (final notifier in [position, actual, rate, seek, intent]) {
        notifier.dispose();
      }
    },
  );

  testWidgets(
    'line shift retains row, moves continuously and snaps large seeks',
    (tester) async {
      final lines = List.generate(
        8,
        (i) => LyricLine(
          timestamp: Duration(seconds: i),
          texts: ['Line $i'],
        ),
      );
      var active = 1;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, set) {
                update = set;
                return CompactPlaybackLyrics(lines: lines, active: active);
              },
            ),
          ),
        ),
      );
      final row = tester.element(find.text('Line 2'));
      final before = tester.getTopLeft(find.text('Line 2')).dy;
      update(() => active = 2);
      await tester.pump();
      expect(tester.element(find.text('Line 2')), same(row));
      await tester.pump(const Duration(milliseconds: 100));
      final middle = tester.getTopLeft(find.text('Line 2')).dy;
      expect(middle, lessThan(before));
      expect(middle, greaterThan(before - 24));
      expect(find.text('Line 2'), findsOneWidget);
      expect(find.byType(AnimatedSwitcher), findsNothing);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Line 2')).dy,
        closeTo(before - 24, .01),
      );
      update(() => active = 7);
      await tester.pump();
      expect(find.text('Line 2'), findsNothing);
      expect(find.text('Line 7'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'category rail keeps edits, pauses hidden tickers, fits short landscape',
    (tester) async {
      tester.view.physicalSize = const Size(660, 260);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var created = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.8),
              padding: const EdgeInsets.only(left: 40),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: LandscapeToolsPanel(
              initial: PlaybackMenuAction.queue,
              builder: (_, page) => _KeepPage(
                key: ValueKey('page-$page'),
                created: () => created++,
              ),
            ),
          ),
        ),
      );
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('landscape-category-queue')))
            .dx,
        8,
      );
      await tester.enterText(find.byType(TextField), 'remember');
      final original = tester.element(find.byType(TextField));
      final originalFocus = tester
          .widget<EditableText>(find.byType(EditableText))
          .focusNode;
      expect(MediaQuery.paddingOf(original).left, 0);
      await tester.tap(
        find.byKey(const ValueKey('landscape-category-effects')),
      );
      await tester.pumpAndSettle();
      expect(created, 2);
      final offscreen = find
          .byType(TextField, skipOffstage: false)
          .evaluate()
          .where((e) => identical(e, original))
          .single;
      expect(TickerMode.valuesOf(offscreen).enabled, false);
      originalFocus.requestFocus();
      await tester.pump();
      expect(originalFocus.hasFocus, false);
      await tester.tap(find.byKey(const ValueKey('landscape-category-queue')));
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(TextField)), same(original));
      expect(find.text('remember'), findsOneWidget);
      expect(created, 2);
      expect(find.byTooltip('关闭菜单'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _KeepPage extends StatefulWidget {
  const _KeepPage({super.key, required this.created});
  final VoidCallback created;
  @override
  State<_KeepPage> createState() => _KeepPageState();
}

class _KeepPageState extends State<_KeepPage> {
  @override
  void initState() {
    super.initState();
    widget.created();
  }

  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsets.all(8), child: TextField());
}
