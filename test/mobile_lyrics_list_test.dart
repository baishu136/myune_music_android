import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/widgets/interlude_animation_widget.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';

void main() {
  test('active lyric scale reserves its full paint bounds', () {
    expect(mobileLyricScaleSafeExtent(40), closeTo(44, .001));
    expect(mobileLyricScaleSafeContentWidth(220), closeTo(200, .001));
  });

  test('large lyric jumps use a bounded elastic correction', () {
    expect(clampLyricElasticDisplacement(800, 300), closeTo(84, .001));
    expect(clampLyricElasticDisplacement(-800, 300), closeTo(-84, .001));
    expect(clampLyricElasticDisplacement(36, 300), 36);
    expect(clampLyricElasticDisplacement(800, 1000), 120);
    expect(lyricSeekVisibleTravel(220), closeTo(92.4, .001));
    expect(lyricSeekVisibleTravel(1000), 180);
  });

  test('stable lyric glow parameters reuse the cached raster layer', () {
    const style = TextStyle(fontSize: 20, height: 1.2);
    const painter = MobileLyricGlowPainter(
      text: '缓存外发光',
      style: style,
      color: Color(0x4DFFFFFF),
      blurRadius: 8,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      locale: Locale('zh', 'CN'),
    );
    const unchanged = MobileLyricGlowPainter(
      text: '缓存外发光',
      style: style,
      color: Color(0x4DFFFFFF),
      blurRadius: 8,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      locale: Locale('zh', 'CN'),
    );
    const changed = MobileLyricGlowPainter(
      text: '缓存外发光',
      style: style,
      color: Color(0x66FFFFFF),
      blurRadius: 8,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      locale: Locale('zh', 'CN'),
    );

    expect(unchanged.shouldRepaint(painter), isFalse);
    expect(changed.shouldRepaint(painter), isTrue);
  });

  testWidgets('regular mode moves the whole lyric list with a soft ease-out', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nextLine = find.byKey(const ValueKey('mobile_lyric_1'));
    final initialY = tester.getCenter(nextLine).dy;
    hostKey.currentState!.setActive(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final earlyY = tester.getCenter(nextLine).dy;
    expect(earlyY, lessThan(initialY));
    expect(earlyY, greaterThan(88));

    await tester.pump(mobileLyricsFocusTransitionDuration);
    expect(tester.getCenter(nextLine).dy, closeTo(88, 12));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'mobile_lyric_active_hop_',
            ),
      ),
      findsNothing,
    );
  });

  test('lyric blur grows gently with visual distance', () {
    expect(
      mobileLyricsFocusTransitionDuration,
      const Duration(milliseconds: 520),
    );
    expect(mobileLyricBlurSigmaForDistance(0), 0);
    expect(mobileLyricBlurSigmaForDistance(1), .9);
    expect(mobileLyricBlurSigmaForDistance(2), 1.65);
    expect(mobileLyricBlurSigmaForDistance(4), 3);
    expect(mobileLyricBlurSigmaForDistance(20), 3.4);
  });

  testWidgets('next-song lyrics clear an in-flight elastic displacement', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 220,
            child: _LyricsHost(key: hostKey, elasticScrollEnabled: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    hostKey.currentState!.setActive(5);
    await tester.pump();

    hostKey.currentState!.replaceLinesAt(0);
    await tester.pump();
    await tester.pump();

    final visibleTransforms = find.byWidgetPredicate(
      (widget) =>
          widget is Transform &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'mobile_lyric_elastic_transform_',
          ),
    );
    expect(visibleTransforms, findsWidgets);
    for (final transform in tester.widgetList<Transform>(visibleTransforms)) {
      expect(transform.transform.storage[13], 0);
    }
  });

  testWidgets('a played line returns to the queue with a soft style exit', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(1);
    await tester.pumpAndSettle();

    hostKey.currentState!.setActive(2);
    await tester.pump();

    final playedLine = find.byKey(const ValueKey('mobile_lyric_1'));
    final scale = tester.widget<AnimatedScale>(
      find.descendant(of: playedLine, matching: find.byType(AnimatedScale)),
    );
    final style = tester.widget<AnimatedDefaultTextStyle>(
      find.descendant(
        of: playedLine,
        matching: find.byType(AnimatedDefaultTextStyle),
      ),
    );
    expect(scale.duration, const Duration(milliseconds: 280));
    expect(scale.curve, const Cubic(.16, 1, .3, 1));
    expect(style.duration, const Duration(milliseconds: 280));
    expect(style.curve, const Cubic(.16, 1, .3, 1));

    final scaleSafeContent = tester.widget<FractionallySizedBox>(
      find.descendant(
        of: playedLine,
        matching: find.byKey(const ValueKey('mobile_lyric_scale_safe_content')),
      ),
    );
    expect(scaleSafeContent.widthFactor, 1 / mobileLyricsActiveScale);
    expect(scaleSafeContent.heightFactor, 1 / mobileLyricsActiveScale);
  });

  testWidgets('scaled lyric paint stays inside its retained sliver extent', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 220,
            child: _LyricsHost(key: hostKey),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Rect rowRect(int index) =>
        tester.getRect(find.byKey(ValueKey('mobile_lyric_$index')));
    Rect paintRect(int index) => tester.getRect(
      find.descendant(
        of: find.byKey(ValueKey('mobile_lyric_$index')),
        matching: find.byKey(const ValueKey('mobile_lyric_scaled_paint')),
      ),
    );
    void expectContained(int index) {
      final row = rowRect(index);
      final paint = paintRect(index);
      expect(paint.left, greaterThanOrEqualTo(row.left - .01));
      expect(paint.top, greaterThanOrEqualTo(row.top - .01));
      expect(paint.right, lessThanOrEqualTo(row.right + .01));
      expect(paint.bottom, lessThanOrEqualTo(row.bottom + .01));
    }

    expectContained(0);
    hostKey.currentState!.setActive(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expectContained(0);
    expectContained(1);
  });

  testWidgets('dense line changes retarget one bounded list animation', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final index in [1, 2, 3]) {
      hostKey.currentState!.setActive(index);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 55));
    }

    await tester.pumpAndSettle();
    final active = find.byKey(const ValueKey('mobile_lyric_3'));
    expect(active, findsOneWidget);
    expect(tester.getCenter(active).dy, closeTo(88, 12));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.contains('active_hop'),
      ),
      findsNothing,
    );
  });

  testWidgets('active lyric automatically scrolls into the visible area', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mobile_lyric_0')), findsOneWidget);

    hostKey.currentState!.setActive(35);
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('mobile_lyric_35'));
    expect(active, findsOneWidget);
    expect(tester.getCenter(active).dy, closeTo(88, 12));

    hostKey.currentState!.setActive(49);
    await tester.pumpAndSettle();

    final finalLine = find.byKey(const ValueKey('mobile_lyric_49'));
    expect(finalLine, findsOneWidget);
    expect(tester.getCenter(finalLine).dy, closeTo(88, 12));
  });

  testWidgets('first async lyric batch starts with the active line centered', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 220,
            child: _LyricsHost(key: hostKey, initiallyEmpty: true),
          ),
        ),
      ),
    );

    hostKey.currentState!.loadLinesAt(25);
    await tester.pump();

    final active = find.byKey(const ValueKey('mobile_lyric_25'));
    expect(active, findsOneWidget);
    expect(tester.getCenter(active).dy, closeTo(88, 12));
  });

  testWidgets(
    'left-aligned next-song lyrics use the new position on their first frame',
    (tester) async {
      final hostKey = GlobalKey<_LyricsHostState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 220,
              child: _LyricsHost(
                key: hostKey,
                elasticScrollEnabled: true,
                textAlign: TextAlign.left,
              ),
            ),
          ),
        ),
      );
      hostKey.currentState!.setActive(35);
      await tester.pumpAndSettle();

      hostKey.currentState!.switchSongAt(4);
      await tester.pump();

      final active = find.byKey(const ValueKey('mobile_lyric_4'));
      expect(active, findsOneWidget);
      expect(tester.getCenter(active).dy, closeTo(88, 12));
    },
  );

  testWidgets('uses the configured lyric font size', (tester) async {
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['当前歌词']),
      LyricLine(timestamp: const Duration(seconds: 1), texts: const ['下一行']),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileLyricsList(lines: lines, active: 0, fontSize: 26),
        ),
      ),
    );

    final activeStyle = tester.widget<AnimatedDefaultTextStyle>(
      find
          .ancestor(
            of: find.text('当前歌词'),
            matching: find.byType(AnimatedDefaultTextStyle),
          )
          .first,
    );
    final inactiveStyle = tester.widget<AnimatedDefaultTextStyle>(
      find
          .ancestor(
            of: find.text('下一行'),
            matching: find.byType(AnimatedDefaultTextStyle),
          )
          .first,
    );
    expect(activeStyle.style.fontSize, 26);
    expect(inactiveStyle.style.fontSize, 26);
  });

  testWidgets('keeps the active lyric centered while font size changes', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(25);
    await tester.pumpAndSettle();

    hostKey.currentState!.setFontSize(32);
    await tester.pumpAndSettle();
    final enlarged = find.byKey(const ValueKey('mobile_lyric_25'));
    expect(tester.getCenter(enlarged).dy, closeTo(88, 12));

    hostKey.currentState!.setFontSize(12);
    await tester.pumpAndSettle();
    final reduced = find.byKey(const ValueKey('mobile_lyric_25'));
    expect(tester.getCenter(reduced).dy, closeTo(88, 12));
  });

  testWidgets('multiline lyrics retain the 40 percent visual anchor', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            width: 260,
            child: _LyricsHost(key: hostKey),
          ),
        ),
      ),
    );
    hostKey.currentState!.setLineText(
      24,
      '这是一句会自动换行的很长歌词，用于验证真实文本高度不会造成累计定位漂移',
    );
    hostKey.currentState!.setActive(24);
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('mobile_lyric_24'));
    expect(active, findsOneWidget);
    expect(tester.getCenter(active).dy, closeTo(120, 12));
  });

  testWidgets('applies the selected font family to lyrics', (tester) async {
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['自定义字体歌词']),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileLyricsList(
            lines: lines,
            active: 0,
            fontFamily: 'TestLyricsFont',
          ),
        ),
      ),
    );

    final style = tester.widget<AnimatedDefaultTextStyle>(
      find
          .ancestor(
            of: find.text('自定义字体歌词'),
            matching: find.byType(AnimatedDefaultTextStyle),
          )
          .first,
    );
    expect(style.style.fontFamily, 'TestLyricsFont');
  });

  testWidgets('manual lyric browsing resumes follow after three idle seconds', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(20);
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('mobile_lyrics_scroll_view')),
      const Offset(0, -140),
    );
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    hostKey.currentState!.setActive(40);
    await tester.pump();

    final active = find.byKey(const ValueKey('mobile_lyric_40'));
    expect(active, findsNothing);

    await tester.pump(const Duration(seconds: 2));
    expect(active, findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(active, findsOneWidget);
    expect(tester.getCenter(active).dy, closeTo(88, 12));
  });

  testWidgets('a new lyric pointer hold cancels the pending follow timer', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    final scrollView = find.byKey(const ValueKey('mobile_lyrics_scroll_view'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(20);
    await tester.pumpAndSettle();
    await tester.drag(scrollView, const Offset(0, -140));
    await tester.pump(const Duration(milliseconds: 300));
    hostKey.currentState!.setActive(40);
    await tester.pump(const Duration(milliseconds: 2500));

    final heldGesture = await tester.startGesture(tester.getCenter(scrollView));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('mobile_lyric_40')), findsNothing);

    await heldGesture.up();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('mobile_lyric_40')), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile_lyric_40')), findsOneWidget);
  });

  testWidgets('controller recenters the active lyric immediately', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(25);
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('mobile_lyrics_scroll_view')),
      const Offset(0, -160),
    );
    await tester.pump(const Duration(milliseconds: 300));

    hostKey.currentState!.recenter();
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('mobile_lyric_25'));
    expect(active, findsOneWidget);
    expect(tester.getCenter(active).dy, closeTo(88, 12));
  });

  testWidgets('an immediate lyric drag owns a pending entry recenter', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(20);
    await tester.pumpAndSettle();

    hostKey.currentState!.recenter();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('mobile_lyrics_scroll_view'))),
    );
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump(const Duration(milliseconds: 16));

    final active = find.byKey(const ValueKey('mobile_lyric_20'));
    expect(active, findsOneWidget);
    expect((tester.getCenter(active).dy - 88).abs(), greaterThan(30));
    await gesture.up();
  });

  testWidgets('pointer down freezes an in-flight automatic scroll', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scrollView = find.byKey(const ValueKey('mobile_lyrics_scroll_view'));
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: scrollView, matching: find.byType(Scrollable)),
    );

    hostKey.currentState!.setActive(35);
    await tester.pump(const Duration(milliseconds: 80));
    final gesture = await tester.startGesture(tester.getCenter(scrollView));
    await tester.pump();
    final frozenOffset = scrollable.position.pixels;
    await tester.pump(const Duration(milliseconds: 300));
    expect(scrollable.position.pixels, closeTo(frozenOffset, .01));
    await gesture.up();
  });

  testWidgets('same-song lyric refresh does not end an active drag', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(20);
    await tester.pumpAndSettle();
    final scrollView = find.byKey(const ValueKey('mobile_lyrics_scroll_view'));
    final gesture = await tester.startGesture(tester.getCenter(scrollView));
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump(const Duration(milliseconds: 16));

    hostKey.currentState!.replaceLinesAt(40);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('mobile_lyric_40')), findsNothing);
    await gesture.up();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('mobile_lyric_40')), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile_lyric_40')), findsOneWidget);
  });

  testWidgets('controller settles smoothly on a selected lyric timestamp', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(8);
    await tester.pumpAndSettle();

    hostKey.currentState!.settleOn(const Duration(seconds: 35));
    await tester.pump();
    final prepositioned = find.byKey(const ValueKey('mobile_lyric_35'));
    expect(prepositioned, findsOneWidget);
    expect(tester.getCenter(prepositioned).dy, greaterThan(88));

    hostKey.currentState!.setActive(35);
    await tester.pumpAndSettle();
    final selected = find.byKey(const ValueKey('mobile_lyric_35'));
    expect(tester.getCenter(selected).dy, closeTo(88, 12));
  });

  testWidgets('a lyric refresh preserves an in-flight seek timestamp', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(10);
    await tester.pumpAndSettle();
    hostKey.currentState!.settleOn(const Duration(seconds: 20));
    await tester.pumpAndSettle();

    hostKey.currentState!.replaceLinesAt(19);
    await tester.pumpAndSettle();
    final target = find.byKey(const ValueKey('mobile_lyric_20'));
    expect(target, findsOneWidget);
    expect(tester.getCenter(target).dy, closeTo(88, 12));

    hostKey.currentState!.setActive(20);
    await tester.pumpAndSettle();
    expect(tester.getCenter(target).dy, closeTo(88, 12));
  });

  testWidgets('a transient previous-line seek event keeps the target locked', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(10);
    await tester.pumpAndSettle();
    hostKey.currentState!.settleOn(const Duration(seconds: 20));
    await tester.pumpAndSettle();

    hostKey.currentState!.setActive(20);
    await tester.pump(const Duration(milliseconds: 200));
    hostKey.currentState!.setActive(19);
    await tester.pump(const Duration(milliseconds: 400));
    final target = find.byKey(const ValueKey('mobile_lyric_20'));
    expect(target, findsOneWidget);
    expect(tester.getCenter(target).dy, closeTo(88, 12));

    hostKey.currentState!.setActive(20);
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.getCenter(target).dy, closeTo(88, 12));
  });

  testWidgets('seeking inside the active lyric keeps the list stable', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 220, child: _LyricsHost(key: hostKey)),
        ),
      ),
    );
    hostKey.currentState!.setActive(8);
    await tester.pumpAndSettle();

    hostKey.currentState!.settleOn(const Duration(seconds: 8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final active = find.byKey(const ValueKey('mobile_lyric_8'));
    expect(active, findsOneWidget);
    expect(tester.getCenter(active).dy, closeTo(88, 12));
  });

  testWidgets('far controller seek reaches a newly mounted elastic line', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 220,
            child: _LyricsHost(key: hostKey, elasticScrollEnabled: true),
          ),
        ),
      ),
    );
    hostKey.currentState!.setActive(2);
    await tester.pumpAndSettle();

    hostKey.currentState!.settleOn(const Duration(seconds: 40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final target = tester.widget<Transform>(
      find.byKey(const ValueKey('mobile_lyric_elastic_transform_40')),
    );
    expect(target.transform.storage[13].abs(), greaterThan(1));
  });

  testWidgets('manual browsing reports the lyric nearest the visual anchor', (
    tester,
  ) async {
    Duration? target;
    final lines = List.generate(
      30,
      (index) => LyricLine(
        timestamp: Duration(seconds: index * 5),
        texts: ['第 ${index + 1} 行'],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 220,
            child: MobileLyricsList(
              lines: lines,
              active: 0,
              onBrowseTargetChanged: (value) => target = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('mobile_lyrics_scroll_view')),
      const Offset(0, -150),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(target, isNotNull);
    expect(target, isNot(Duration.zero));

    await tester.pump(const Duration(seconds: 2));
    expect(target, isNotNull);

    await tester.pump(const Duration(seconds: 1));
    expect(target, isNull);
  });

  testWidgets('manual browsing highlights and selects the candidate row', (
    tester,
  ) async {
    const browseColor = Color(0xFF4A90E2);
    final controller = MobileLyricsListController();
    Duration? target;
    Duration? selected;
    var coverToggleCount = 0;
    final lines = List.generate(
      30,
      (index) => LyricLine(
        timestamp: Duration(seconds: index * 5),
        texts: ['第 ${index + 1} 行'],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => coverToggleCount++,
            child: SizedBox(
              height: 220,
              child: MobileLyricsList(
                controller: controller,
                lines: lines,
                active: 0,
                activeColor: browseColor,
                onBrowseTargetChanged: (value) => target = value,
                onBrowseTargetSelected: (value) {
                  selected = value;
                  controller.settleOn(value);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile_lyrics_progress_guide')),
      findsNothing,
    );
    await tester.drag(
      find.byKey(const ValueKey('mobile_lyrics_scroll_view')),
      const Offset(0, -150),
    );
    await tester.pump(const Duration(milliseconds: 180));

    expect(target, isNotNull);
    expect(
      find.byKey(const ValueKey('mobile_lyrics_progress_guide')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_lyrics_progress_time')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_lyrics_progress_line')),
      findsNothing,
    );
    expect(mobileLyricsBrowseGuideColor, const Color(0xB3FFFFFF));
    expect(formatMobileLyricsBrowseTime(const Duration(seconds: 65)), '1:05');
    expect(
      find.byKey(const ValueKey('mobile_lyrics_browse_highlight')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('mobile_lyrics_browse_highlight')),
          )
          .opacity,
      0,
    );
    expect(
      find.byKey(const ValueKey('mobile_lyrics_browse_tap_target')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('mobile_lyrics_browse_reset')),
      findsNothing,
    );
    expect(
      tester
          .widget<TweenAnimationBuilder<double>>(
            find.byKey(const ValueKey('mobile_lyrics_browse_highlight_scale')),
          )
          .tween
          .end,
      .86,
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('mobile_lyrics_browse_highlight')),
          )
          .opacity,
      1,
    );
    await tester.pump(mobileLyricsBrowseMaskRevealDuration);
    expect(mobileLyricsBrowseMaskColor, const Color(0x4DFFFFFF));
    expect(
      find.byKey(const ValueKey('mobile_lyrics_browse_tap_target')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TweenAnimationBuilder<double>>(
            find.byKey(const ValueKey('mobile_lyrics_browse_highlight_scale')),
          )
          .tween
          .end,
      1,
    );
    final selectedTarget = target;
    final targetIndex = selectedTarget!.inSeconds ~/ 5;
    final targetRow = tester.getRect(
      find.byKey(ValueKey('mobile_lyric_$targetIndex')),
    );
    final tapTarget = tester.getRect(
      find.byKey(const ValueKey('mobile_lyrics_browse_tap_target')),
    );
    final lyricsArea = tester.getRect(
      find.byKey(const ValueKey('mobile_lyrics_scroll_view')),
    );
    final browseStyle = tester
        .widget<AnimatedDefaultTextStyle>(
          find.descendant(
            of: find.byKey(ValueKey('mobile_lyric_$targetIndex')),
            matching: find.byType(AnimatedDefaultTextStyle),
          ),
        )
        .style;
    expect(browseStyle.color, browseColor);
    expect(tapTarget.height, greaterThan(targetRow.height));
    expect(tapTarget.center.dy, closeTo(targetRow.center.dy, .01));
    await tester.tapAt(Offset(tapTarget.left + 4, tapTarget.center.dy));
    await tester.pump();
    expect(selected, selectedTarget);
    expect(coverToggleCount, 0);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.contains('active_hop'),
      ),
      findsNothing,
    );

    selected = null;
    await tester.drag(
      find.byKey(const ValueKey('mobile_lyrics_scroll_view')),
      const Offset(0, -60),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(mobileLyricsBrowseMaskRevealDuration);
    final rightEdgeTarget = tester.getRect(
      find.byKey(const ValueKey('mobile_lyrics_browse_tap_target')),
    );
    final expectedRightTarget = target;
    await tester.tapAt(
      Offset(rightEdgeTarget.right - 4, rightEdgeTarget.center.dy),
    );
    await tester.pump();
    expect(selected, expectedRightTarget);
    expect(coverToggleCount, 0);

    selected = null;
    await tester.tapAt(Offset(tapTarget.center.dx, lyricsArea.top + 2));
    await tester.pump();
    expect(selected, isNull);
    expect(coverToggleCount, 1);
  });

  testWidgets('edge fade is opt-in', (tester) async {
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['第一行']),
      LyricLine(timestamp: const Duration(seconds: 1), texts: const ['第二行']),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MobileLyricsList(lines: lines, active: 0)),
      ),
    );
    expect(find.byKey(const ValueKey('mobile_lyrics_edge_fade')), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileLyricsList(
            lines: lines,
            active: 0,
            edgeFadeEnabled: true,
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('mobile_lyrics_edge_fade')),
      findsOneWidget,
    );
    final fade = tester.widget<ShaderMask>(
      find.byKey(const ValueKey('mobile_lyrics_edge_fade')),
    );
    expect(fade.blendMode, BlendMode.dstIn);
    expect(mobileLyricsTopEdgeAlpha, 0);
    expect(mobileLyricsTopFadeSoftAlpha, greaterThan(mobileLyricsTopEdgeAlpha));
    expect(mobileLyricsTopFadeMidAlpha, greaterThan(mobileLyricsTopEdgeAlpha));
    expect(
      mobileLyricsTopFadeNearAlpha,
      greaterThan(mobileLyricsTopFadeMidAlpha),
    );
    expect(mobileLyricsBottomFadeMidAlpha, greaterThan(0));
    final stops = mobileLyricsEdgeFadeStops(800);
    expect(stops.length, 10);
    expect(stops[4], closeTo(.14, .0001));
    expect(stops[5], closeTo(.84, .0001));
    for (var index = 1; index < stops.length; index++) {
      expect(stops[index], greaterThan(stops[index - 1]));
    }
  });

  testWidgets('karaoke lyric colors played and unplayed text separately', (
    tester,
  ) async {
    final line = LyricLine(
      timestamp: Duration.zero,
      texts: const ['Hello世界'],
      tokens: [
        [
          LyricToken(
            text: 'Hello',
            start: Duration.zero,
            end: const Duration(seconds: 1),
          ),
          LyricToken(
            text: '世界',
            start: const Duration(seconds: 1),
            end: const Duration(seconds: 2),
          ),
        ],
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: MobileLyricsList(
            lines: [line],
            active: 0,
            position: const Duration(milliseconds: 500),
          ),
        ),
      ),
    );

    final richText = tester.widget<Text>(
      find
          .descendant(
            of: find.byKey(const ValueKey('mobile_lyric_0')),
            matching: find.byType(Text),
          )
          .last,
    );
    final spans = (richText.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.map((span) => span.text).join(), 'Hello世界');
    expect(spans.first.style!.color, isNot(spans.last.style!.color));
    expect(spans.last.style!.color, Colors.white.withValues(alpha: .5));
  });

  testWidgets('active lyric highlight keeps the whole karaoke line white', (
    tester,
  ) async {
    final line = LyricLine(
      timestamp: Duration.zero,
      texts: const ['高亮歌词'],
      tokens: [
        [
          LyricToken(
            text: '高亮',
            start: Duration.zero,
            end: const Duration(seconds: 1),
          ),
          LyricToken(
            text: '歌词',
            start: const Duration(seconds: 1),
            end: const Duration(seconds: 2),
          ),
        ],
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileLyricsList(
            lines: [line],
            active: 0,
            position: const Duration(milliseconds: 500),
            highlightActiveLine: true,
          ),
        ),
      ),
    );

    final highlightedText = tester.widget<Text>(
      find
          .descendant(
            of: find.byKey(const ValueKey('mobile_lyric_0')),
            matching: find.byType(Text),
          )
          .last,
    );
    expect(highlightedText.data, '高亮歌词');
    expect(highlightedText.textSpan, isNull);
    final animatedStyle = tester.widget<AnimatedDefaultTextStyle>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_0')),
        matching: find.byType(AnimatedDefaultTextStyle),
      ),
    );
    expect(animatedStyle.style.color, Colors.white);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_0')),
        matching: find.byType(ValueListenableBuilder<Duration>),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_0')),
        matching: find.byType(RichText),
      ),
      findsOneWidget,
    );
  });

  testWidgets('karaoke progress can update without rebuilding the lyric list', (
    tester,
  ) async {
    final position = ValueNotifier(const Duration(milliseconds: 500));
    addTearDown(position.dispose);
    final line = LyricLine(
      timestamp: Duration.zero,
      texts: const ['Hello世界'],
      tokens: [
        [
          LyricToken(
            text: 'Hello',
            start: Duration.zero,
            end: const Duration(seconds: 1),
          ),
          LyricToken(
            text: '世界',
            start: const Duration(seconds: 1),
            end: const Duration(seconds: 2),
          ),
        ],
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: MobileLyricsList(
            lines: [line],
            active: 0,
            positionListenable: position,
          ),
        ),
      ),
    );

    Text richText() => tester.widget<Text>(
      find
          .descendant(
            of: find.byKey(const ValueKey('mobile_lyric_0')),
            matching: find.byType(Text),
          )
          .last,
    );

    var spans = (richText().textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.first.text, 'He');

    position.value = const Duration(milliseconds: 1500);
    await tester.pump();

    spans = (richText().textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.first.text, 'Hello');
  });

  testWidgets('light lyrics use stronger unplayed text and optional glow', (
    tester,
  ) async {
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['正在播放']),
      LyricLine(timestamp: const Duration(seconds: 1), texts: const ['尚未播放']),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Scaffold(
          body: MobileLyricsList(
            lines: lines,
            active: 0,
            glowEnabled: true,
            glowRadius: 14,
          ),
        ),
      ),
    );

    final inactiveStyle = tester
        .widget<AnimatedDefaultTextStyle>(
          find.descendant(
            of: find.byKey(const ValueKey('mobile_lyric_1')),
            matching: find.byType(AnimatedDefaultTextStyle),
          ),
        )
        .style;
    expect(inactiveStyle.color, const Color(0xFF757575).withValues(alpha: .72));
    expect(inactiveStyle.shadows, isNull);
    final inactiveGlow =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byKey(const ValueKey('mobile_lyric_1')),
                    matching: find.byKey(
                      const ValueKey('mobile_lyric_glow_layer'),
                    ),
                  ),
                )
                .painter!
            as MobileLyricGlowPainter;
    expect(inactiveGlow.color, inactiveStyle.color!.withValues(alpha: .30));
    expect(inactiveGlow.blurRadius, 14);
    final inactiveGlowOpacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_1')),
        matching: find.byKey(const ValueKey('mobile_lyric_glow_opacity')),
      ),
    );
    expect(inactiveGlowOpacity.opacity, inactiveStyle.color!.a);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Scaffold(body: MobileLyricsList(lines: lines, active: 0)),
      ),
    );
    final defaultStyle = tester
        .widget<AnimatedDefaultTextStyle>(
          find.descendant(
            of: find.byKey(const ValueKey('mobile_lyric_1')),
            matching: find.byType(AnimatedDefaultTextStyle),
          ),
        )
        .style;
    expect(defaultStyle.shadows, isNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_1')),
        matching: find.byKey(const ValueKey('mobile_lyric_glow_layer')),
      ),
      findsNothing,
    );
  });

  testWidgets('light playback backgrounds use dark-mode lyric treatment', (
    tester,
  ) async {
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['正在播放']),
      LyricLine(timestamp: const Duration(seconds: 1), texts: const ['尚未播放']),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Scaffold(
          body: MobileLyricsList(
            lines: lines,
            active: 0,
            brightForeground: true,
            glowEnabled: true,
          ),
        ),
      ),
    );

    final style = tester
        .widget<AnimatedDefaultTextStyle>(
          find.descendant(
            of: find.byKey(const ValueKey('mobile_lyric_1')),
            matching: find.byType(AnimatedDefaultTextStyle),
          ),
        )
        .style;
    expect(style.color, Colors.white.withValues(alpha: .72));
    expect(style.shadows, isNull);
    final glow =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byKey(const ValueKey('mobile_lyric_1')),
                    matching: find.byKey(
                      const ValueKey('mobile_lyric_glow_layer'),
                    ),
                  ),
                )
                .painter!
            as MobileLyricGlowPainter;
    expect(glow.color, style.color!.withValues(alpha: .30));
    final glowOpacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_1')),
        matching: find.byKey(const ValueKey('mobile_lyric_glow_opacity')),
      ),
    );
    expect(glowOpacity.opacity, style.color!.a);
  });

  testWidgets('lyric glow follows the rendered line color and opacity', (
    tester,
  ) async {
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['正在播放']),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: MobileLyricsList(lines: lines, active: 0, glowEnabled: true),
        ),
      ),
    );

    final style = tester
        .widget<AnimatedDefaultTextStyle>(
          find.descendant(
            of: find.byKey(const ValueKey('mobile_lyric_0')),
            matching: find.byType(AnimatedDefaultTextStyle),
          ),
        )
        .style;
    expect(style.shadows, isNull);
    final glow =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byKey(const ValueKey('mobile_lyric_0')),
                    matching: find.byKey(
                      const ValueKey('mobile_lyric_glow_layer'),
                    ),
                  ),
                )
                .painter!
            as MobileLyricGlowPainter;
    expect(glow.color, style.color!.withValues(alpha: .30));
    final glowOpacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_0')),
        matching: find.byKey(const ValueKey('mobile_lyric_glow_opacity')),
      ),
    );
    expect(glowOpacity.opacity, style.color!.a);
    final glowPaint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_0')),
        matching: find.byKey(const ValueKey('mobile_lyric_glow_layer')),
      ),
    );
    expect(glowPaint.isComplex, isTrue);
    expect(glowPaint.willChange, isFalse);
    expect(
      find.ancestor(
        of: find.descendant(
          of: find.byKey(const ValueKey('mobile_lyric_0')),
          matching: find.byKey(const ValueKey('mobile_lyric_glow_layer')),
        ),
        matching: find.byType(RepaintBoundary),
      ),
      findsWidgets,
    );
  });

  testWidgets('regular centered lyrics are the default presentation', (
    tester,
  ) async {
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['当前歌词']),
      LyricLine(timestamp: const Duration(seconds: 1), texts: const ['下一行']),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MobileLyricsList(lines: lines, active: 0)),
      ),
    );

    final list = tester.widget<MobileLyricsList>(find.byType(MobileLyricsList));
    final textStyle = tester.widget<AnimatedDefaultTextStyle>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_0')),
        matching: find.byType(AnimatedDefaultTextStyle),
      ),
    );
    expect(list.elasticScrollEnabled, isFalse);
    expect(list.lineBlurEnabled, isFalse);
    expect(textStyle.textAlign, TextAlign.center);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_1')),
        matching: find.byType(ImageFiltered),
      ),
      findsNothing,
    );
  });

  testWidgets('alignment and distance blur are applied per lyric line', (
    tester,
  ) async {
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['当前歌词']),
      LyricLine(timestamp: const Duration(seconds: 1), texts: const ['下一行']),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileLyricsList(
            lines: lines,
            active: 0,
            textAlign: TextAlign.left,
            lineBlurEnabled: true,
          ),
        ),
      ),
    );

    final textStyle = tester.widget<AnimatedDefaultTextStyle>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_1')),
        matching: find.byType(AnimatedDefaultTextStyle),
      ),
    );
    expect(textStyle.textAlign, TextAlign.left);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_0')),
        matching: find.byType(ImageFiltered),
      ),
      findsOneWidget,
    );
    final currentFilter = tester.widget<ImageFiltered>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_0')),
        matching: find.byType(ImageFiltered),
      ),
    );
    expect(currentFilter.enabled, isFalse);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_1')),
        matching: find.byType(ImageFiltered),
      ),
      findsOneWidget,
    );
    final safeArea = tester.widget<Padding>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_1')),
        matching: find.byKey(const ValueKey('mobile_lyric_filter_safe_area')),
      ),
    );
    expect(safeArea.padding, const EdgeInsets.symmetric(vertical: 5));
  });

  testWidgets('blur sharpness crossfades with the active lyric', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 220,
            child: _LyricsHost(key: hostKey, lineBlurEnabled: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    hostKey.currentState!.setActive(1);
    await tester.pump();
    final incomingAtStart = tester.widget<ImageFiltered>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_1')),
        matching: find.byType(ImageFiltered),
      ),
    );
    expect(incomingAtStart.enabled, isTrue);

    await tester.pump(const Duration(milliseconds: 100));
    final outgoingDuringTransition = tester.widget<ImageFiltered>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_0')),
        matching: find.byType(ImageFiltered),
      ),
    );
    expect(outgoingDuringTransition.enabled, isTrue);

    await tester.pump(mobileLyricsFocusTransitionDuration);
    final incomingSettled = tester.widget<ImageFiltered>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_1')),
        matching: find.byType(ImageFiltered),
      ),
    );
    expect(incomingSettled.enabled, isFalse);
  });

  testWidgets('configured lyric weight and interlude dots are rendered', (
    tester,
  ) async {
    final position = ValueNotifier(const Duration(seconds: 2));
    addTearDown(position.dispose);
    final lines = [
      LyricLine(
        timestamp: Duration.zero,
        texts: const [],
        isInterlude: true,
        interludeDuration: const Duration(seconds: 8),
      ),
      LyricLine(timestamp: const Duration(seconds: 8), texts: const ['歌词']),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileLyricsList(
            lines: lines,
            active: 0,
            fontWeight: FontWeight.w800,
            positionListenable: position,
            isPlaying: false,
          ),
        ),
      ),
    );

    final style = tester.widget<AnimatedDefaultTextStyle>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_lyric_0')),
        matching: find.byType(AnimatedDefaultTextStyle),
      ),
    );
    expect(style.style.fontWeight, FontWeight.w800);
    expect(find.byType(InterludeAnimationWidget), findsOneWidget);
  });

  testWidgets('speaker prefixes follow the selected global alignment', (
    tester,
  ) async {
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['世界上的另一个我']),
      LyricLine(timestamp: const Duration(seconds: 1), texts: const ['肆：第一句']),
      LyricLine(timestamp: const Duration(seconds: 2), texts: const ['肆的下一句']),
      LyricLine(timestamp: const Duration(seconds: 3), texts: const ['郭：第二句']),
      LyricLine(timestamp: const Duration(seconds: 4), texts: const ['郭的下一句']),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: MobileLyricsList(
              lines: lines,
              active: 2,
              textAlign: TextAlign.right,
            ),
          ),
        ),
      ),
    );

    TextAlign alignmentAt(int index) => tester
        .widget<AnimatedDefaultTextStyle>(
          find.descendant(
            of: find.byKey(ValueKey('mobile_lyric_$index')),
            matching: find.byType(AnimatedDefaultTextStyle),
          ),
        )
        .textAlign!;

    expect(alignmentAt(0), TextAlign.right);
    expect(alignmentAt(1), TextAlign.right);
    expect(alignmentAt(2), TextAlign.right);
    expect(alignmentAt(3), TextAlign.right);
    expect(alignmentAt(4), TextAlign.right);
  });

  testWidgets('side-aligned lyrics use the compact safe edge inset', (
    tester,
  ) async {
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['靠近屏幕边缘']),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileLyricsList(
            lines: lines,
            active: 0,
            textAlign: TextAlign.left,
          ),
        ),
      ),
    );

    expect(mobileLyricsHorizontalInset(TextAlign.left), 4);
    expect(mobileLyricsHorizontalInset(TextAlign.right), 4);
    expect(mobileLyricsHorizontalInset(TextAlign.center), 24);
  });

  testWidgets('elastic mode produces a visible per-line spring displacement', (
    tester,
  ) async {
    final hostKey = GlobalKey<_LyricsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: _LyricsHost(key: hostKey, elasticScrollEnabled: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    hostKey.currentState!.setActive(5);
    await tester.pump();
    final firstFrameCenter = tester.getCenter(
      find.byKey(const ValueKey('mobile_lyric_5')),
    );
    expect((firstFrameCenter.dy - 120).abs(), greaterThan(8));
    final transform = tester.widget<Transform>(
      find.byKey(const ValueKey('mobile_lyric_elastic_transform_5')),
    );
    expect(transform.transform.storage[13].abs(), greaterThan(1));

    await tester.pumpAndSettle();
    final settled = tester.widget<Transform>(
      find.byKey(const ValueKey('mobile_lyric_elastic_transform_5')),
    );
    expect(settled.transform.storage[13], closeTo(0, .5));
  });
}

class _LyricsHost extends StatefulWidget {
  const _LyricsHost({
    super.key,
    this.initiallyEmpty = false,
    this.elasticScrollEnabled = false,
    this.lineBlurEnabled = false,
    this.textAlign = TextAlign.center,
  });

  final bool initiallyEmpty;
  final bool elasticScrollEnabled;
  final bool lineBlurEnabled;
  final TextAlign textAlign;

  @override
  State<_LyricsHost> createState() => _LyricsHostState();
}

class _LyricsHostState extends State<_LyricsHost> {
  int active = 0;
  String contentIdentity = 'song-a';
  double fontSize = 20;
  final controller = MobileLyricsListController();
  late List<LyricLine> lines;

  List<LyricLine> _makeLines() => List.generate(
    50,
    (index) => LyricLine(
      timestamp: Duration(seconds: index),
      texts: ['第 ${index + 1} 行'],
    ),
  );

  @override
  void initState() {
    super.initState();
    lines = widget.initiallyEmpty ? [] : _makeLines();
  }

  void setActive(int value) => setState(() => active = value);

  void setFontSize(double value) => setState(() => fontSize = value);

  void setLineText(int index, String text) => setState(() {
    lines = List<LyricLine>.of(lines);
    lines[index] = LyricLine(timestamp: lines[index].timestamp, texts: [text]);
  });

  void loadLinesAt(int value) => setState(() {
    active = value;
    lines = _makeLines();
  });

  void replaceLinesAt(int value) => setState(() {
    active = value;
    lines = _makeLines();
  });

  void beginNextSong() => setState(() {
    contentIdentity = 'song-b';
    active = -1;
    lines = [];
  });

  void loadNextSongLyrics() => setState(() {
    active = 0;
    lines = _makeLines();
  });

  void switchSongAt(int value) => setState(() {
    contentIdentity = 'song-b';
    active = value;
    lines = List.generate(
      50,
      (index) => LyricLine(
        timestamp: Duration(seconds: index),
        texts: ['下一曲第 ${index + 1} 行'],
      ),
    );
  });

  void recenter() => controller.recenter();

  void settleOn(Duration target) => controller.settleOn(target);

  @override
  Widget build(BuildContext context) => MobileLyricsList(
    controller: controller,
    lines: lines,
    active: active,
    contentIdentity: contentIdentity,
    fontSize: fontSize,
    elasticScrollEnabled: widget.elasticScrollEnabled,
    lineBlurEnabled: widget.lineBlurEnabled,
    textAlign: widget.textAlign,
  );
}
