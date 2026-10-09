import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';

void main() {
  for (final hz in [60, 90, 120]) {
    for (final elastic in [false, true]) {
      testWidgets(
        'karaoke ${elastic ? "elastic" : "rigid"} redirection and seek at ${hz}Hz',
        (tester) async {
          final position = ValueNotifier(Duration.zero);
          final output = ValueNotifier(true);
          final seek = ValueNotifier<Duration?>(null);
          addTearDown(position.dispose);
          addTearDown(output.dispose);
          addTearDown(seek.dispose);
          final lines = List.generate(
            18,
            (i) => LyricLine(
              timestamp: Duration(milliseconds: i * 200),
              texts: ['歌词 English 第$i行', '静态翻译'],
            ),
          );
          Widget host(int active) => _host(
            lines,
            active: active,
            position: position,
            output: output,
            seek: seek,
            elastic: elastic,
            height: 240,
          );
          await tester.pumpWidget(host(0));
          final item = find.byKey(const ValueKey('mobile_lyric_2'));
          final step = Duration(microseconds: (1e6 / hz).round());
          final frames = (hz * .2).round();
          for (var f = 0; f < frames; f++) {
            position.value += step;
            await tester.pump(step);
          }
          final before = tester.getCenter(item).dy;
          await tester.pumpWidget(host(1));
          expect(tester.getCenter(item).dy, closeTo(before, .05));
          for (var f = 0; f < frames; f++) {
            position.value += step;
            await tester.pump(step);
          }
          final redirect = tester.getCenter(item).dy;
          await tester.pumpWidget(host(2));
          expect(
            tester.getCenter(item).dy,
            closeTo(redirect, .05),
            reason: 'Redirect must inherit the residual displacement',
          );
          var previous = redirect;
          final layouts = debugKaraokeTextLayoutCount;
          final activeCache = _painter(tester, 2).cache;
          for (var f = 0; f < (hz * .12).round(); f++) {
            position.value += step;
            await tester.pump(step);
            final next = tester.getCenter(item).dy;
            expect(
              (next - previous).abs(),
              lessThan(tester.getSize(item).height * 12 / hz),
            );
            expect(_painter(tester, 2).cache, same(activeCache));
            previous = next;
          }
          // Scrolling may mount the next off-screen row once; the moving
          // active row never repeats a complete layout on an animation frame.
          expect(
            debugKaraokeTextLayoutCount,
            lessThanOrEqualTo(layouts + 10),
            reason:
                'at most two new bounded five-layout caches; no frame layout',
          );
          expect(
            find.byWidgetPredicate(
              (w) =>
                  w is AnimatedSlide &&
                  w.key == const ValueKey('mobile_lyric_karaoke_line_shift'),
            ),
            findsWidgets,
          );
          expect(
            find.byKey(const ValueKey('mobile_lyric_elastic_transform_2')),
            elastic ? findsOneWidget : findsNothing,
          );
          // Pause freezes singing while the wall-time line motion can settle.
          output.value = false;
          await tester.pump();
          final frozen = _painter(tester, 2).positionListenable.value;
          await tester.pump(const Duration(milliseconds: 70));
          expect(_painter(tester, 2).positionListenable.value, frozen);
          position.value = const Duration(milliseconds: 210);
          seek.value = position.value;
          await tester.pumpWidget(host(1));
          expect(_painter(tester, 1).positionListenable.value, position.value);
          for (final transform in tester.widgetList<Transform>(
            find.byWidgetPredicate(
              (w) =>
                  w is Transform &&
                  w.key.toString().contains('mobile_lyric_elastic_transform_'),
            ),
          )) {
            expect(transform.transform.storage[13], 0);
          }
          await tester.pump(const Duration(seconds: 2));
          expect(tester.binding.transientCallbackCount, 0);
        },
      );
    }
  }
  testWidgets(
    'export software-rendered multilingual review frames',
    (tester) async {
      await _loadFont(tester);
      const samples = [
        '快速中文混合 English 歌词在这里折行并连续推进',
        'supercalifragilisticexpialidocious softly follows',
        '日本語 한국어 𠀀 👨‍👩‍👧‍👦 é mixed words',
        'طريق الموسيقى शांत संगीत',
      ];
      final directory = Directory(
        const String.fromEnvironment(
          'KARAOKE_EXPORT_DIRECTORY',
          defaultValue: 'F:/AGENT/1/test-artifacts/synthetic-325',
        ),
      );
      await tester.runAsync(() => directory.create(recursive: true));
      for (var i = 0; i < samples.length; i++) {
        await tester.pumpWidget(
          _host(
            [
              LyricLine(
                timestamp: Duration.zero,
                texts: [samples[i], '静态翻译 / Translation'],
              ),
            ],
            width: 220,
            fontSize: 26,
          ),
        );
        final painter = _painter(tester, 0);
        await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder)
            ..drawColor(Colors.black, BlendMode.src);
          const times = [0, 900000, 1900000, 3700000];
          for (var f = 0; f < times.length; f++) {
            canvas.save();
            canvas.translate(f * 220.0, 6);
            painter.cache.paint(canvas, times[f], 1.0, painter.colors);
            canvas.restore();
          }
          final picture = recorder.endRecording();
          final image = await picture.toImage(
            880,
            painter.cache.height.ceil() + 12,
          );
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '${directory.path}/fixture_$i.png',
          ).writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
          picture.dispose();
        });
      }
    },
    skip: !const bool.fromEnvironment('KARAOKE_EXPORT_FRAMES'),
  );

  test('language chunks preserve text, graphemes and trailing spaces', () {
    const original = '𠀀中文 Hello  world 👨‍👩‍👧‍👦 é 日本語한국어が';
    final line = synthesizeKaraokeTiming(
      LyricLine(
        timestamp: const Duration(seconds: 2),
        texts: [original, '翻译', 'romaji'],
      ),
      nextTimestamp: const Duration(seconds: 6),
    );
    final tokens = line.tokens!.first;
    expect(tokens.map((t) => t.text).join(), original);
    expect(tokens.any((t) => t.text == '𠀀'), isTrue);
    expect(tokens.any((t) => t.text == 'が'), isTrue);
    expect(tokens.any((t) => t.text == 'Hello  '), isTrue);
    expect(tokens.any((t) => t.text == '👨‍👩‍👧‍👦 '), isTrue);
    expect(line.tokens![1], isEmpty);
    expect(line.tokens![2], isEmpty);
    expect(tokens.first.start, lessThan(line.timestamp));
    expect(tokens.last.end, lessThan(const Duration(seconds: 6)));
    for (var i = 1; i < tokens.length; i++) {
      expect(tokens[i].start, tokens[i - 1].end);
    }
    expect(karaokeSyntheticTokenWeight('é'), 1);
    expect(karaokeSyntheticTokenWeight('   '), 0);
    expect(karaokeSyntheticTokenWeight('longword'), lessThan(8));
  });

  test('CJK cadence stays even while Latin letters use a longer window', () {
    final chinese = synthesizeKaraokeTiming(
      LyricLine(
        timestamp: const Duration(seconds: 10),
        texts: const ['歌唱着一种没有深度的语言'],
      ),
      nextTimestamp: const Duration(seconds: 16),
    ).tokens!.first;
    expect(chinese.first.start, const Duration(milliseconds: 9920));
    expect(chinese.last.end, const Duration(milliseconds: 14560));
    expect(
      (chinese.last.end - chinese.last.start).inMicroseconds,
      closeTo((chinese.first.end - chinese.first.start).inMicroseconds, 1),
    );

    final english = synthesizeKaraokeTiming(
      LyricLine(
        timestamp: const Duration(seconds: 10),
        texts: const ["There's nothin' between us"],
      ),
      nextTimestamp: const Duration(seconds: 16),
    ).tokens!.first;
    expect(english.first.start, const Duration(seconds: 10));
    expect(english.last.end, const Duration(milliseconds: 15880));
    expect(
      english.first.end - english.first.start,
      greaterThan(const Duration(seconds: 1)),
    );

    final kana = synthesizeKaraokeTiming(
      LyricLine(timestamp: Duration.zero, texts: const ['やっと眼を覚ましたかい']),
      nextTimestamp: const Duration(seconds: 5),
    ).tokens!.first;
    expect(kana.map((token) => token.text).join(), 'やっと眼を覚ましたかい');
    expect(kana, hasLength(11));
  });

  test('synthetic Chinese blanks preserve text but consume no vocal time', () {
    final tokens = synthesizeKaraokeTiming(
      LyricLine(timestamp: const Duration(seconds: 10), texts: ['中  文']),
      nextTimestamp: const Duration(seconds: 14),
    ).tokens!.first;
    expect(tokens.map((token) => token.text).join(), '中  文');
    final blank = tokens.singleWhere((token) => token.text.trim().isEmpty);
    expect(blank.end, blank.start);
    expect(tokens.first.end, tokens.last.start);
    expect(
      synthesizeKaraokeTiming(
        LyricLine(timestamp: Duration.zero, texts: ['   ']),
      ).texts.first,
      '   ',
    );
  });

  test('bounds, real timestamp precedence and weak timing cache', () {
    final line = LyricLine(timestamp: Duration.zero, texts: ['Hi there']);
    final fast = synthesizeKaraokeTiming(
      line,
      nextTimestamp: const Duration(milliseconds: 200),
    );
    expect(fast.tokens!.first.last.end, const Duration(milliseconds: 650));
    expect(
      synthesizeKaraokeTiming(
        line,
        nextTimestamp: const Duration(milliseconds: 200),
      ),
      same(fast),
    );
    final slow = synthesizeKaraokeTiming(
      line,
      nextTimestamp: const Duration(seconds: 20),
    );
    expect(slow.tokens!.first.last.end, const Duration(seconds: 8));
    expect(slow, isNot(same(fast)));
    line.texts[0] = 'Changed';
    expect(
      synthesizeKaraokeTiming(
        line,
        nextTimestamp: const Duration(seconds: 20),
      ).tokens!.first.single.text,
      'Changed',
    );
    final real = LyricLine(
      timestamp: Duration.zero,
      texts: const ['真实'],
      tokens: [
        [
          LyricToken(
            text: '真实',
            start: const Duration(milliseconds: 320),
            end: const Duration(milliseconds: 700),
          ),
        ],
      ],
    );
    expect(synthesizeKaraokeTiming(real), same(real));
    expect(karaokeFeatherWidth(10), 12);
    expect(karaokeFeatherWidth(60), 18);
  });

  testWidgets('synthetic motion preloads the first glyph alongside scrolling', (
    tester,
  ) async {
    final position = ValueNotifier(const Duration(milliseconds: 999));
    addTearDown(position.dispose);
    final lines = [
      LyricLine(timestamp: Duration.zero, texts: const ['前行']),
      LyricLine(
        timestamp: const Duration(seconds: 1),
        texts: const ['中文 English'],
      ),
      LyricLine(timestamp: const Duration(seconds: 5), texts: const ['后行']),
    ];
    var active = 0;
    Widget build() =>
        _host(lines, active: active, position: position, height: 240);
    await tester.pumpWidget(build());
    final before = _painter(tester, 1).cache;
    expect(
      before.tokens.first.units.first.timing.liftStartUs,
      lessThan(1000000),
    );
    position.value = const Duration(seconds: 1);
    active = 1;
    await tester.pumpWidget(build());
    final centerAtStart = tester
        .getCenter(find.byKey(const ValueKey('mobile_lyric_1')))
        .dy;
    await tester.pump(const Duration(milliseconds: 80));
    final painter = _painter(tester, 1);
    expect(
      painter.positionListenable.value,
      greaterThan(const Duration(seconds: 1)),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('mobile_lyric_1'))).dy,
      lessThan(centerAtStart),
    );
    _draw(painter, 1080000);
    expect(painter.cache.lifts.first, lessThan(0));
  });

  testWidgets('English letters highlight and rise in sequence', (tester) async {
    await _loadFont(tester);
    await tester.pumpWidget(
      _host([
        LyricLine(timestamp: Duration.zero, texts: const ['Follow softly']),
        LyricLine(timestamp: const Duration(seconds: 6), texts: const ['Next']),
      ]),
    );
    final painter = _painter(tester, 0);
    final units = painter.cache.tokens.first.units;
    expect(units.length, greaterThan(3));
    for (var i = 1; i < units.length; i++) {
      expect(
        units[i].timing.highlightStartUs,
        greaterThan(units[i - 1].timing.highlightStartUs),
      );
    }
    _draw(painter, units[2].timing.highlightStartUs);
    expect(painter.cache.highlights[0], greaterThan(0));
    expect(painter.cache.highlights[1], greaterThan(0));
    expect(painter.cache.highlights[2], 0);
    expect(painter.cache.lifts[0], lessThan(painter.cache.lifts[1]));
    expect(painter.cache.lifts[1], lessThanOrEqualTo(0));
  });

  testWidgets('rigid synthetic mode retains the default list spring', (
    tester,
  ) async {
    final position = ValueNotifier(const Duration(milliseconds: 999));
    addTearDown(position.dispose);
    final lines = List.generate(
      8,
      (i) => LyricLine(
        timestamp: Duration(seconds: i),
        texts: ['第$i行歌词'],
      ),
    );
    await tester.pumpWidget(_host(lines, position: position, height: 240));
    final target = find.byKey(const ValueKey('mobile_lyric_1'));
    final before = tester.getCenter(target).dy;
    final anchor = tester
        .getCenter(find.byKey(const ValueKey('mobile_lyric_0')))
        .dy;
    position.value = const Duration(seconds: 1);
    await tester.pumpWidget(
      _host(lines, active: 1, position: position, height: 240),
    );
    expect(tester.getCenter(target).dy, closeTo(before, .01));
    await tester.pump(const Duration(milliseconds: 80));
    final during = tester.getCenter(target).dy;
    expect(during, lessThan(before));
    expect(during, greaterThan(anchor));
    expect(
      find.byWidgetPredicate(
        (widget) => widget.key.toString().contains('mobile_lyric_elastic_'),
      ),
      findsNothing,
    );
    expect(
      _painter(tester, 1).positionListenable.value,
      greaterThan(const Duration(seconds: 1)),
    );
    for (var frame = 0; frame < 34; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      (tester.getCenter(target).dy - anchor).abs(),
      lessThan((before - anchor) * .04),
    );
    // The common default spring settles its small tail at the same anchor.
    for (var frame = 0; frame < 26; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.getCenter(target).dy, closeTo(anchor, .4));
  });

  testWidgets(
    'paused decoder corrections and resume do not masquerade as a browse seek',
    (tester) async {
      final position = ValueNotifier(const Duration(seconds: 6));
      final output = ValueNotifier(false);
      addTearDown(position.dispose);
      addTearDown(output.dispose);
      final lines = List.generate(
        12,
        (i) => LyricLine(
          timestamp: Duration(seconds: i * 3),
          texts: ['第$i行歌词'],
        ),
      );
      await tester.pumpWidget(
        _host(lines, active: 2, position: position, output: output),
      );
      await tester.drag(
        find.byKey(const ValueKey('mobile_lyrics_scroll_view')),
        const Offset(0, -80),
      );
      await tester.pump(const Duration(seconds: 1));
      double guideOpacity() => tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('mobile_lyrics_browse_highlight')),
          )
          .opacity;
      expect(guideOpacity(), 1);
      position.value = const Duration(milliseconds: 6020);
      await tester.pump();
      expect(guideOpacity(), 1);
      expect(
        _painter(tester, 2).positionListenable.value,
        const Duration(seconds: 6),
      );
      await tester.pump(const Duration(seconds: 1));
      output.value = true;
      await tester.pump(const Duration(milliseconds: 100));
      position.value = const Duration(milliseconds: 6120);
      await tester.pump();
      expect(guideOpacity(), 1);
    },
  );

  testWidgets(
    'inactive karaoke blur shares one cached tier and its switch removes filters',
    (tester) async {
      final lines = List.generate(
        5,
        (i) => LyricLine(
          timestamp: Duration(seconds: i * 3),
          texts: ['第$i行歌词'],
        ),
      );
      await tester.pumpWidget(_host(lines, blur: true));
      ui.ImageFilter filter(int index) => tester
          .widget<ImageFiltered>(
            find.descendant(
              of: find.byKey(ValueKey('mobile_lyric_$index')),
              matching: find.byWidgetPredicate(
                (widget) => widget is ImageFiltered,
              ),
            ),
          )
          .imageFilter;
      final nearest = filter(1);
      for (final index in [1, 2, 3]) {
        final sigma = mobileLyricBlurSigmaForDistance(1);
        expect(
          filter(index).toString(),
          ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.decal,
          ).toString(),
        );
      }
      await tester.pumpWidget(
        _host(lines, blur: true, activeColor: Colors.blue),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(filter(1), same(nearest));
      await tester.pumpWidget(_host(lines));
      expect(
        find.byWidgetPredicate((widget) => widget is ImageFiltered),
        findsNothing,
      );
    },
  );

  testWidgets(
    'wrapped word relays physically and retains completed rows; translation stays static',
    (tester) async {
      await _loadFont(tester);
      final lines = [
        LyricLine(
          timestamp: Duration.zero,
          texts: const [
            'supercalifragilisticexpialidocious',
            'Translation / 翻译',
          ],
        ),
      ];
      await tester.pumpWidget(_host(lines, width: 150, fontSize: 30));
      final painter = _painter(tester, 0);
      final cache = painter.cache;
      final token = cache.tokens.first;
      expect(token.fragments.length, greaterThan(1));
      final first = token.fragments.first;
      final second = token.fragments[1];
      final mid =
          ((second.startRatio + second.endRatio) / 2 * token.spanUs).round()
              as int;
      final early = (await tester.runAsync(() => _pixels(painter, 0)))!;
      final middle = (await tester.runAsync(() => _pixels(painter, mid)))!;
      final complete = (await tester.runAsync(
        () => _pixels(painter, token.spanUs + 1000000),
      ))!;
      final firstRegion = Rect.fromLTRB(
        0,
        0,
        cache.width,
        first.bounds.bottom.toDouble(),
      );
      final reference = _whitePixels(complete, cache.width.ceil(), firstRegion);
      expect(reference, greaterThan(50));
      expect(_whitePixels(early, cache.width.ceil(), firstRegion), 0);
      expect(
        _whitePixels(middle, cache.width.ceil(), firstRegion),
        closeTo(reference, reference * .04),
      );
      final translationRegion = Rect.fromLTRB(
        0,
        cache.lineHeight * token.fragments.length,
        cache.width,
        cache.height,
      );
      expect(
        _sumPixels(early, cache.width.ceil(), translationRegion),
        _sumPixels(complete, cache.width.ceil(), translationRegion),
      );
      expect(debugKaraokeTextLayoutCount, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'frames and colour changes reuse shaped masks; geometry changes invalidate and dispose',
    (tester) async {
      final position = ValueNotifier(Duration.zero);
      addTearDown(position.dispose);
      final lines = [
        LyricLine(
          timestamp: Duration.zero,
          texts: const ['快速中文 longEnglishWord 👨‍👩‍👧‍👦 é', '静态翻译'],
        ),
      ];
      final initialPictures = debugKaraokeLivePictureCount;
      final initialLayouts = debugKaraokeTextLayoutCount;
      await tester.pumpWidget(_host(lines, position: position));
      final layoutCount = debugKaraokeTextLayoutCount;
      final dynamic initialCache = _painter(tester, 0).cache;
      final fragments = initialCache.tokens.fold<int>(
        0,
        (int count, dynamic token) => count + (token.fragments.length as int),
      );
      expect(
        layoutCount - initialLayouts,
        lessThanOrEqualTo(5 + fragments),
        reason:
            'geometry/ink plus one owned vector mask per token fragment; never per frame',
      );
      final livePictures = debugKaraokeLivePictureCount;
      final painter = _painter(tester, 0);
      for (final hz in [60, 90, 120]) {
        for (var f = 0; f < hz; f++) {
          _draw(painter, (f * 1000000 / hz).round());
        }
      }
      expect(debugKaraokeTextLayoutCount, layoutCount);
      expect(debugKaraokeLivePictureCount, livePictures);
      await tester.pumpWidget(
        _host(lines, position: position, activeColor: Colors.blue),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(debugKaraokeTextLayoutCount, layoutCount);
      await tester.pumpWidget(
        _host(lines, position: position, width: 180, fontSize: 32),
      );
      expect(debugKaraokeTextLayoutCount, greaterThan(layoutCount));
      final resizedCount = debugKaraokeTextLayoutCount;
      await tester.pumpWidget(
        _host(
          lines,
          position: position,
          width: 180,
          fontSize: 32,
          locale: const Locale('en', 'GB'),
        ),
      );
      expect(debugKaraokeTextLayoutCount, greaterThan(resizedCount));
      await tester.pumpWidget(const SizedBox());
      expect(debugKaraokeLivePictureCount, initialPictures);
    },
  );

  testWidgets(
    'unstarted rows and suffixes batch solid layers without frame layout',
    (tester) async {
      final lines = [
        LyricLine(
          timestamp: Duration.zero,
          texts: const ['快速中文词句混合长英文 following softly', '静态翻译'],
        ),
      ];
      await tester.pumpWidget(_host(lines));
      final painter = _painter(tester, 0);
      final layouts = debugKaraokeTextLayoutCount;
      painter.cache.prepareImage();
      for (var i = 0; i < 80 && !painter.cache.imageReady; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(painter.cache.imageReady, isTrue);
      var before = debugKaraokeSolidLayerCount;
      _draw(painter, -120000);
      expect(debugKaraokeSolidLayerCount - before, 0);
      before = debugKaraokeSolidLayerCount;
      _draw(painter, 100000);
      expect(debugKaraokeSolidLayerCount - before, 0);
      expect(debugKaraokeTextLayoutCount, layouts);
      expect(painter.cache.lifts.last, 0);
      expect(painter.cache.highlights.last, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'suffix batching respects out-of-order real timestamps and is bounded',
    (tester) async {
      final line = LyricLine(
        timestamp: Duration.zero,
        texts: const ['AB'],
        tokens: [
          [
            LyricToken(
              text: 'A',
              start: const Duration(seconds: 1),
              end: const Duration(seconds: 2),
            ),
            LyricToken(
              text: 'B',
              start: Duration.zero,
              end: const Duration(seconds: 1),
            ),
          ],
        ],
      );
      await tester.pumpWidget(_host([line]));
      final painter = _painter(tester, 0);
      _draw(painter, 300000);
      expect(painter.cache.highlights.first, 0);
      expect(painter.cache.highlights.last, greaterThan(0));
      await tester.pumpWidget(
        _host([
          LyricLine(
            timestamp: Duration.zero,
            texts: [List.filled(80, '字').join()],
          ),
        ]),
      );
      expect(_painter(tester, 0).cache.restSuffixMasks, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'ordinary 0.75/1/1.5/2x positions repaint without rebuilding the list',
    (tester) async {
      for (final rate in [.75, 1.0, 1.5, 2.0]) {
        final position = ValueNotifier(Duration.zero);
        await tester.pumpWidget(
          _host(
            [
              LyricLine(
                timestamp: Duration.zero,
                texts: const ['普通中文 English'],
              ),
            ],
            position: position,
            rate: rate,
          ),
        );
        final painter = _painter(tester, 0);
        for (var f = 1; f <= 5; f++) {
          await tester.pump(const Duration(milliseconds: 100));
          position.value = Duration(microseconds: (f * 100000 * rate).round());
          await tester.pump();
          expect(_painter(tester, 0), same(painter));
        }
        await tester.pumpWidget(const SizedBox());
        position.dispose();
      }
    },
  );

  testWidgets(
    'forward/backward seeks snap and preserve exact in-line progress, including future rows',
    (tester) async {
      final position = ValueNotifier(Duration.zero);
      final seek = ValueNotifier<Duration?>(null);
      addTearDown(position.dispose);
      addTearDown(seek.dispose);
      final lines = List.generate(
        30,
        (i) => LyricLine(
          timestamp: Duration(seconds: i),
          texts: ['逐字歌词 $i'],
        ),
      );
      await tester.pumpWidget(
        _host(lines, position: position, seek: seek, height: 240),
      );
      for (final target in [
        const Duration(milliseconds: 9500),
        const Duration(milliseconds: 3500),
      ]) {
        position.value = target;
        seek.value = target;
        await tester.pump();
        final index = target.inSeconds;
        expect(
          tester.getCenter(find.byKey(ValueKey('mobile_lyric_$index'))).dy,
          closeTo(96, .01),
        );
        expect(_painter(tester, index).positionListenable.value, target);
        final future = _painter(tester, index + 1);
        expect(
          future.positionListenable.value,
          lessThan(lines[index + 1].timestamp),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          tester.getCenter(find.byKey(ValueKey('mobile_lyric_$index'))).dy,
          closeTo(96, .01),
        );
      }
    },
  );
  testWidgets(
    'seeking near a fast line end does not delay the next highlight or spring',
    (tester) async {
      final position = ValueNotifier(const Duration(seconds: 8));
      final seek = ValueNotifier<Duration?>(null);
      addTearDown(position.dispose);
      addTearDown(seek.dispose);
      final lines = List.generate(
        15,
        (i) => LyricLine(
          timestamp: Duration(seconds: i),
          texts: ['快速中文 $i'],
        ),
      );
      await tester.pumpWidget(
        _host(lines, active: 8, position: position, seek: seek),
      );
      position.value = const Duration(milliseconds: 8990);
      seek.value = position.value;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      position.value = const Duration(milliseconds: 9020);
      await tester.pumpWidget(
        _host(lines, active: 9, position: position, seek: seek),
      );
      expect(_painter(tester, 8).isExiting, isTrue);
      expect(
        _painter(tester, 9).positionListenable.value,
        const Duration(milliseconds: 9020),
      );
    },
  );
}

Widget _host(
  List<LyricLine> lines, {
  int active = 0,
  ValueNotifier<Duration>? position,
  ValueNotifier<Duration?>? seek,
  ValueNotifier<bool>? output,
  double width = 320,
  double height = 360,
  double fontSize = 26,
  Color activeColor = Colors.white,
  double rate = 1,
  bool elastic = false,
  bool blur = false,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  theme: ThemeData(
    brightness: Brightness.dark,
    fontFamilyFallback: const [
      'SyntheticHangul',
      'SyntheticExtHan',
      'SyntheticEmoji',
      'SyntheticArabic',
      'SyntheticIndic',
    ],
  ),
  locale: locale,
  supportedLocales: const [Locale('en'), Locale('en', 'GB')],
  home: Scaffold(
    body: SizedBox(
      width: width,
      height: height,
      child: MobileLyricsList(
        lines: lines,
        active: active,
        positionListenable: position,
        seekPositionListenable: seek,
        actualPlaybackListenable: output,
        karaokeLyricsMode: KaraokeLyricsMode.all,
        fontSize: fontSize,
        fontFamily: 'SyntheticTest',
        activeColor: activeColor,
        playbackRate: rate,
        elasticScrollEnabled: elastic,
        lineBlurEnabled: blur,
      ),
    ),
  ),
);

dynamic _painter(WidgetTester tester, int index) => tester
    .widget<CustomPaint>(
      find.descendant(
        of: find.byKey(ValueKey('mobile_lyric_$index')),
        matching: find.byKey(
          const ValueKey('mobile_karaoke_single_pass_paint'),
        ),
      ),
    )
    .painter;

void _draw(dynamic painter, int mediaUs) {
  final recorder = ui.PictureRecorder();
  painter.cache.paint(Canvas(recorder), mediaUs, 1.0, painter.colors);
  recorder.endRecording().dispose();
}

Future<Uint8List> _pixels(dynamic painter, int mediaUs) async {
  final cache = painter.cache;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.black, BlendMode.src);
  cache.paint(canvas, mediaUs, 1.0, painter.colors);
  final picture = recorder.endRecording();
  final image = await picture.toImage(cache.width.ceil(), cache.height.ceil());
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final result = Uint8List.fromList(data!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return result;
}

int _whitePixels(Uint8List data, int width, Rect region) {
  var count = 0;
  for (
    var y = region.top.ceil().clamp(0, data.length ~/ (width * 4));
    y < region.bottom.floor().clamp(0, data.length ~/ (width * 4));
    y++
  ) {
    for (var x = 0; x < width; x++) {
      final at = (y * width + x) * 4;
      if (data[at] > 240 && data[at + 1] > 240 && data[at + 2] > 240) count++;
    }
  }
  return count;
}

int _sumPixels(Uint8List data, int width, Rect region) {
  var sum = 0;
  for (
    var y = region.top.ceil().clamp(0, data.length ~/ (width * 4));
    y < region.bottom.floor().clamp(0, data.length ~/ (width * 4));
    y++
  ) {
    for (var x = 0; x < width; x++) {
      sum += data[(y * width + x) * 4];
    }
  }
  return sum;
}

Future<void> _loadFont(WidgetTester tester) => tester.runAsync(() async {
  final bytes = await File('assets/fonts/MiSansVF.ttf').readAsBytes();
  await (FontLoader(
    'SyntheticTest',
  )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  // Flutter's host test runner has no Android system-font fallback. These
  // optional local fonts are only used for exported Windows review images;
  // they are never bundled with the app or needed by portable CI tests.
  if (const bool.fromEnvironment('KARAOKE_EXPORT_FRAMES')) {
    for (final entry in const {
      'SyntheticHangul': 'C:/Windows/Fonts/malgun.ttf',
      'SyntheticExtHan': 'C:/Windows/Fonts/mingliub.ttc',
      'SyntheticEmoji': 'C:/Windows/Fonts/seguiemj.ttf',
      'SyntheticArabic': 'C:/Windows/Fonts/arial.ttf',
      'SyntheticIndic': 'C:/Windows/Fonts/Nirmala.ttf',
    }.entries) {
      final file = File(entry.value);
      if (await file.exists()) {
        final data = await file.readAsBytes();
        await (FontLoader(
          entry.key,
        )..addFont(Future.value(ByteData.sublistView(data)))).load();
      }
    }
  }
});
