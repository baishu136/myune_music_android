import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/widgets/lyric_viewport_blur.dart';
import 'package:myune_music/widgets/mobile_lyrics_list.dart';

void main() {
  testWidgets('ordinary motion start/end retains all blur widgets', (
    tester,
  ) async {
    final lines = List.generate(
      40,
      (i) => LyricLine(
        timestamp: Duration(seconds: i * 3),
        texts: ['连续滚动歌词 $i', 'Translation $i'],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 360,
          height: 600,
          child: MobileLyricsList(
            lines: lines,
            active: 6,
            karaokeLyricsEnabled: false,
            lineBlurEnabled: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final widgets = {
      for (final e in tester.elementList(find.byType(LyricViewportBlur)))
        e: e.widget,
    };
    final dynamic config = tester.widget(
      find
          .byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_AnimatedLyricBlur',
          )
          .first,
    );
    final motion = config.motion as ValueNotifier<bool>;
    for (final moving in [true, false, true, false]) {
      motion.value = moving;
      await tester.pump();
      for (final e in tester.elementList(find.byType(LyricViewportBlur))) {
        expect(
          e.widget,
          same(widgets[e]),
          reason: 'a motion boundary must not rebuild every row',
        );
      }
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('sharpening keeps the outer layer and cached child paint', (
    tester,
  ) async {
    final sigma = AnimationController(
      vsync: tester,
      lowerBound: 0,
      upperBound: 3,
      value: .9,
    );
    final scroll = ScrollController();
    final counts = _Counts();
    await tester.pumpWidget(
      MaterialApp(
        home: LyricViewportBlur(
          key: const ValueKey('filter'),
          sigma: .9,
          sigmaAnimation: sigma,
          contentCenter: 100,
          viewportHeight: 600,
          edgeEnabled: false,
          scrollController: scroll,
          child: RepaintBoundary(child: _Probe(counts)),
        ),
      ),
    );
    final render = tester.renderObject<RenderLyricViewportBlur>(
      find.byKey(const ValueKey('filter')),
    );
    final layer = render.debugLayer;
    final filterLayer = layer!.firstChild! as ImageFilterLayer;
    final paints = counts.paints, layouts = counts.layouts;
    for (final value in [.45, .05, 0.0, 1.8, 0.0, .9]) {
      sigma.value = value;
      await tester.pump();
      expect(render.isRepaintBoundary, isTrue);
      expect(
        render.debugLayer,
        same(layer),
        reason: 'keep the cached row when a filter crosses zero',
      );
      expect(render.enabled, value > .01);
      if (value > .01) {
        expect(render.debugLayer!.firstChild, same(filterLayer));
      }
      expect(counts.paints, paints);
      expect(counts.layouts, layouts);
    }
    await tester.pumpWidget(const SizedBox());
    expect(layer.debugDisposed, isTrue);
    expect(filterLayer.debugDisposed, isTrue);
    sigma.dispose();
    scroll.dispose();
  });

  testWidgets('retained boundary matches native ImageFiltered pixels', (
    tester,
  ) async {
    final scroll = ScrollController();
    final key = GlobalKey();
    Widget content() => Transform.translate(
      offset: const Offset(13.5, 9.25),
      child: const Align(
        alignment: Alignment.topLeft,
        child: Text(
          'Lyrics ygp 中文\nTranslation',
          style: TextStyle(
            fontSize: 23,
            height: 1.2,
            color: Color(0x86FFFFFF),
            shadows: [Shadow(color: Color(0x70EEEEFF), blurRadius: 10)],
          ),
        ),
      ),
    );
    Future<List<int>> pixels(double sigma, bool custom) async {
      final child = RepaintBoundary(child: content());
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 240,
                height: 150,
                child: ColoredBox(
                  color: const Color(0xFF183447),
                  child: custom
                      ? LyricViewportBlur(
                          sigma: sigma,
                          contentCenter: 300,
                          viewportHeight: 600,
                          edgeEnabled: false,
                          scrollController: scroll,
                          child: child,
                        )
                      : ImageFiltered(
                          enabled: sigma > .01,
                          imageFilter: cachedLyricBlur(sigma),
                          child: child,
                        ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      late List<int> result;
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        result = data!.buffer.asUint8List().toList();
        image.dispose();
      });
      return result;
    }

    for (final sigma in [0.0, .05, .9, 2.8]) {
      final reference = await pixels(sigma, false),
          actual = await pixels(sigma, true);
      var error = 0, maxError = 0;
      for (var i = 0; i < reference.length; i++) {
        final delta = (reference[i] - actual[i]).abs();
        error += delta;
        if (delta > maxError) maxError = delta;
      }
      expect(error / reference.length, lessThanOrEqualTo(.05));
      expect(maxError, lessThanOrEqualTo(2));
    }
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });

  testWidgets(
    'live filter values reach compositing across repeated zero crossings',
    (tester) async {
      final sigma = AnimationController(
        vsync: tester,
        upperBound: 3,
        value: .9,
      );
      final scroll = ScrollController();
      final actualKey = GlobalKey(), referenceKey = GlobalKey();
      Widget content() => const RepaintBoundary(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Fading ygp 中文',
            style: TextStyle(
              fontSize: 24,
              color: Color(0x90FFFFFF),
              shadows: [Shadow(color: Color(0x7799CCFF), blurRadius: 9)],
            ),
          ),
        ),
      );
      Widget region(Key key, Widget child) => RepaintBoundary(
        key: key,
        child: SizedBox(
          width: 240,
          height: 150,
          child: ColoredBox(color: const Color(0xFF183447), child: child),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                region(
                  actualKey,
                  LyricViewportBlur(
                    sigma: .9,
                    sigmaAnimation: sigma,
                    contentCenter: 300,
                    viewportHeight: 600,
                    edgeEnabled: false,
                    scrollController: scroll,
                    child: content(),
                  ),
                ),
                region(
                  referenceKey,
                  AnimatedBuilder(
                    animation: sigma,
                    child: content(),
                    builder: (_, child) => ImageFiltered(
                      enabled: sigma.value > .01,
                      imageFilter: cachedLyricBlur(sigma.value),
                      child: child,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      for (final value in [.9, .4, .05, 0.0, .05, 1.8, 0.0]) {
        sigma.value = value;
        await tester.pump(const Duration(milliseconds: 16));
        await tester.runAsync(() async {
          Future<List<int>> pixels(GlobalKey key) async {
            final image =
                await (key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final data = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            final result = data!.buffer.asUint8List().toList();
            image.dispose();
            return result;
          }

          final actual = await pixels(actualKey),
              expected = await pixels(referenceKey);
          var sum = 0, maxError = 0;
          for (var i = 0; i < actual.length; i++) {
            final error = (actual[i] - expected[i]).abs();
            sum += error;
            if (error > maxError) maxError = error;
          }
          expect(sum / actual.length, lessThanOrEqualTo(.05));
          expect(maxError, lessThanOrEqualTo(2));
        });
      }
      await tester.pumpWidget(const SizedBox());
      sigma.dispose();
      scroll.dispose();
    },
  );
}

class _Counts {
  int layouts = 0, paints = 0;
}

class _Probe extends LeafRenderObjectWidget {
  const _Probe(this.counts);
  final _Counts counts;
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderProbe(counts);
}

class _RenderProbe extends RenderBox {
  _RenderProbe(this.counts);
  final _Counts counts;
  @override
  void performLayout() {
    counts.layouts++;
    size = constraints.constrain(const Size(200, 50));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    counts.paints++;
    context.canvas.drawRect(offset & size, Paint()..color = Colors.white);
  }
}
