import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/now_playing_cover_glow.dart';
import 'package:myune_music/widgets/now_playing_cover_image.dart';
import 'now_playing_cover_image_test.dart' as fixture;

class _DeferredImage extends ImageProvider<_DeferredImage> {
  final frame = Completer<ImageInfo>();
  @override
  Future<_DeferredImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
    _DeferredImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(frame.future);
}

double alpha(WidgetTester tester) {
  return (tester
              .widget<DecoratedBox>(
                find
                    .descendant(
                      of: find.byType(NowPlayingCoverGlow),
                      matching: find.byType(DecoratedBox),
                    )
                    .first,
              )
              .decoration
          as BoxDecoration)
      .boxShadow!
      .single
      .color
      .a;
}

void main() {
  testWidgets(
    'wait for route AND decoded pixels, then fade without rebuilding cover',
    (tester) async {
      var entered = false;
      late StateSetter update;
      final image = _DeferredImage();
      final changes = ValueNotifier(0);
      var parentBuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              parentBuilds++;
              return Center(
                child: NowPlayingCoverGlow(
                  enabled: true,
                  entranceComplete: entered,
                  waitForImage: true,
                  child: NowPlayingCoverImage(
                    changes: changes,
                    readImage: () => image,
                    size: 240,
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(alpha(tester), 0);
      update(() => entered = true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(alpha(tester), 0);
      image.frame.complete(
        ImageInfo(image: await fixture.pixel(tester, Colors.blue)),
      );
      await tester.pump();
      await tester.pump();
      expect(alpha(tester), 0);
      final element = tester.element(
        find.byKey(const ValueKey('now-playing-cover-image')),
      );
      final builds = parentBuilds;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(alpha(tester), inExclusiveRange(0, .05));
      await tester.pump(const Duration(milliseconds: 180));
      expect(alpha(tester), closeTo(.05, .003));
      await tester.pump(const Duration(milliseconds: 361));
      expect(alpha(tester), closeTo(.1, .003));
      expect(parentBuilds, builds);
      expect(
        tester.element(find.byKey(const ValueKey('now-playing-cover-image'))),
        same(element),
      );
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
      changes.dispose();
      PaintingBinding.instance.imageCache.clear();
    },
  );
  testWidgets(
    'cover return waits for actual transform completion and restarts halo',
    (tester) async {
      final transition = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 300),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: NowPlayingCoverGlow(
              enabled: true,
              coverTransition: transition,
              child: const SizedBox.square(dimension: 240),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(alpha(tester), closeTo(.1, .003));
      transition.value = 1;
      await tester.pump();
      expect(alpha(tester), 0);
      transition.reverse();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 299));
      expect(alpha(tester), 0);
      await tester.pump(const Duration(milliseconds: 2));
      expect(alpha(tester), 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(alpha(tester), inExclusiveRange(0, .05));
      await tester.pumpAndSettle();
      expect(alpha(tester), closeTo(.1, .003));
      await tester.pumpWidget(const SizedBox());
      transition.dispose();
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
  testWidgets(
    'queued replacements never light before the latest cover finishes',
    (tester) async {
      final a = _DeferredImage(), b = _DeferredImage(), c = _DeferredImage();
      final changes = ValueNotifier<ImageProvider<Object>>(a);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: NowPlayingCoverGlow(
              enabled: true,
              waitForImage: true,
              child: NowPlayingCoverImage(
                changes: changes,
                readImage: () => changes.value,
                size: 240,
              ),
            ),
          ),
        ),
      );
      Future<void> resolve(_DeferredImage provider, Color color) async {
        changes.value = provider;
        await tester.pump();
        provider.frame.complete(
          ImageInfo(image: await fixture.pixel(tester, color)),
        );
        await tester.pump();
        await tester.pump();
      }

      await resolve(a, Colors.red);
      await tester.pumpAndSettle();
      await resolve(b, Colors.blue);
      expect(alpha(tester), 0);
      await tester.pump(const Duration(milliseconds: 100));
      await resolve(c, Colors.green);
      expect(alpha(tester), 0);
      await tester.pump(const Duration(milliseconds: 221));
      expect(alpha(tester), 0);
      await tester.pump(const Duration(milliseconds: 319));
      expect(alpha(tester), 0);
      await tester.pump(const Duration(milliseconds: 2));
      expect(alpha(tester), 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(alpha(tester), inExclusiveRange(0, .05));
      await tester.pumpAndSettle();
      expect(alpha(tester), closeTo(.1, .003));
      await tester.pumpWidget(const SizedBox());
      changes.dispose();
      PaintingBinding.instance.imageCache.clear();
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
}
