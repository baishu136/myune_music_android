import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/lyric_viewport_blur.dart';

void main() {
  test(
    'edge blur increases symmetrically, remains bounded and honors opt-out',
    () {
      double sigma(double y, {bool enabled = true}) => lyricViewportBlurSigma(
        baseSigma: .9,
        centerY: y,
        viewportHeight: 600,
        edgeEnabled: enabled,
      );
      expect(sigma(300), .9);
      var previous = sigma(300);
      for (var y = 290; y >= 0; y -= 10) {
        final next = sigma(y.toDouble());
        expect(next, greaterThanOrEqualTo(previous));
        expect(next, sigma(600 - y.toDouble()));
        expect(next - previous, lessThanOrEqualTo(.400001));
        previous = next;
      }
      expect(sigma(0), 3.3);
      expect(sigma(-100), 3.3);
      expect(sigma(0, enabled: false), .9);
      expect(identical(cachedLyricBlur(.9), cachedLyricBlur(.9)), isTrue);
    },
  );
  testWidgets(
    'scroll changes filter layer without rebuilding or relaying out child',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final counts = _Counts();
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 600,
            child: ListView(
              controller: controller,
              children: [
                const SizedBox(height: 280),
                LyricViewportBlur(
                  key: const ValueKey('edge'),
                  sigma: .9,
                  contentCenter: 300,
                  viewportHeight: 600,
                  edgeEnabled: true,
                  scrollController: controller,
                  child: _Probe(counts),
                ),
                const SizedBox(height: 1000),
              ],
            ),
          ),
        ),
      );
      final render = tester.renderObject<RenderLyricViewportBlur>(
        find.byKey(const ValueKey('edge')),
      );
      final layouts = counts.layouts;
      final paints = counts.paints;
      expect(render.sigma, .9);
      for (var i = 1; i <= 120; i++) {
        controller.jumpTo(i * 1.8);
        await tester.pump(const Duration(microseconds: 8333));
      }
      expect(render.sigma, greaterThan(.9));
      expect(counts.layouts, layouts);
      expect(
        counts.paints,
        paints,
        reason: 'reuse the child raster while updating the filter layer',
      );
      await tester.pumpWidget(const SizedBox());
      expect(render.attached, isFalse);
    },
  );
}

class _Counts {
  int layouts = 0;
  int paints = 0;
}

class _Probe extends SingleChildRenderObjectWidget {
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
    size = constraints.constrain(const Size(200, 40));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    counts.paints++;
  }
}
