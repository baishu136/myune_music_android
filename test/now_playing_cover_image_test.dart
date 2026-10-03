import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/now_playing_cover_image.dart';

class _DeferredCover extends ImageProvider<_DeferredCover> {
  final Completer<ImageInfo> frame = Completer<ImageInfo>();
  @override
  Future<_DeferredCover> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
    _DeferredCover key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(frame.future);
}

Future<ui.Image> pixel(WidgetTester tester, Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = color);
  final picture = recorder.endRecording();
  final result = (await tester.runAsync(() => picture.toImage(8, 8)))!;
  picture.dispose();
  return result;
}

void main() {
  testWidgets(
    'rapid replacements retain the blend and only queue the latest decoded cover',
    (tester) async {
      final a = _DeferredCover(),
          b = _DeferredCover(),
          c = _DeferredCover(),
          d = _DeferredCover();
      final signal = ValueNotifier<ImageProvider<Object>?>(a);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: NowPlayingCoverImage(
              changes: signal,
              readImage: () => signal.value,
              size: 200,
            ),
          ),
        ),
      );
      Future<void> resolve(_DeferredCover cover, Color color) async {
        signal.value = cover;
        await tester.pump();
        cover.frame.complete(ImageInfo(image: await pixel(tester, color)));
        await tester.pump();
        await tester.pump();
      }

      ui.Image current() => tester
          .widget<RawImage>(
            find.byKey(const ValueKey('now-playing-cover-current')),
          )
          .image!;
      double opacity() => tester
          .widget<FadeTransition>(
            find.byKey(const ValueKey('now-playing-cover-fade')),
          )
          .opacity
          .value;
      await resolve(a, Colors.red);
      await resolve(b, Colors.blue);
      await tester.pump(const Duration(milliseconds: 100));
      final blend = opacity();
      final bFrame = current().clone();
      addTearDown(bFrame.dispose);
      await resolve(c, Colors.green);
      expect(current().isCloneOf(bFrame), isTrue);
      expect(opacity(), blend, reason: 'no dropped old layer at rapid switch');
      await resolve(d, Colors.yellow);
      expect(current().isCloneOf(bFrame), isTrue);
      expect(opacity(), blend);
      expect(find.byType(RawImage), findsNWidgets(2));
      final retiredHandle = tester
          .widget<RawImage>(
            find.byKey(const ValueKey('now-playing-cover-previous')),
          )
          .image!;
      await tester.pump(const Duration(milliseconds: 221));
      final dFrame = current().clone();
      addTearDown(dFrame.dispose);
      expect(dFrame.isCloneOf(bFrame), isFalse);
      expect(
        opacity(),
        0,
        reason: 'latest replacement starts over fully visible B',
      );
      await tester.pumpAndSettle();
      expect(retiredHandle.debugDisposed, isTrue);
      expect(opacity(), 1);
      expect(current().isCloneOf(dFrame), isTrue);
      expect(find.byType(RawImage), findsOneWidget);
      final currentHandle = current();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(currentHandle.debugDisposed, isTrue);
      expect(tester.binding.transientCallbackCount, 0);
      signal.dispose();
      PaintingBinding.instance.imageCache.clear();
    },
  );

  testWidgets(
    'hidden cover and reduced-motion surfaces cancel replacement immediately',
    (tester) async {
      final a = _DeferredCover(), b = _DeferredCover(), c = _DeferredCover();
      final signal = ValueNotifier<ImageProvider<Object>?>(a);
      var enabled = true;
      var reduceMotion = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return MediaQuery(
                data: MediaQueryData(disableAnimations: reduceMotion),
                child: Center(
                  child: NowPlayingCoverImage(
                    changes: signal,
                    readImage: () => signal.value,
                    size: 200,
                    transitionsEnabled: enabled,
                  ),
                ),
              );
            },
          ),
        ),
      );
      Future<void> resolve(_DeferredCover cover, Color color) async {
        signal.value = cover;
        await tester.pump();
        cover.frame.complete(ImageInfo(image: await pixel(tester, color)));
        await tester.pump();
        await tester.pump();
      }

      await resolve(a, Colors.red);
      await resolve(b, Colors.blue);
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byType(RawImage), findsNWidgets(2));
      update(() => enabled = false);
      await tester.pump();
      expect(find.byType(RawImage), findsOneWidget);
      update(() {
        enabled = true;
        reduceMotion = true;
      });
      await tester.pump();
      await resolve(c, Colors.green);
      expect(find.byType(RawImage), findsOneWidget);
      expect(
        tester
            .widget<FadeTransition>(
              find.byKey(const ValueKey('now-playing-cover-fade')),
            )
            .opacity
            .value,
        1,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
      signal.dispose();
      PaintingBinding.instance.imageCache.clear();
    },
  );
  testWidgets(
    'replacement crossfades only after decoding with fixed geometry',
    (tester) async {
      final a = _DeferredCover(), b = _DeferredCover();
      final signal = ValueNotifier<ImageProvider<Object>?>(a);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: NowPlayingCoverImage(
              changes: signal,
              readImage: () => signal.value,
              size: 200,
            ),
          ),
        ),
      );
      a.frame.complete(ImageInfo(image: await pixel(tester, Colors.red)));
      await tester.pump();
      await tester.pump();
      final bounds = tester.getRect(
        find.byKey(const ValueKey('now-playing-cover-image')),
      );
      signal.value = b;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const ValueKey('now-playing-cover-previous')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('now-playing-cover-placeholder')),
        findsNothing,
      );
      b.frame.complete(ImageInfo(image: await pixel(tester, Colors.blue)));
      await tester.pump();
      await tester.pump();
      final incoming = find.byKey(const ValueKey('now-playing-cover-fade'));
      expect(
        find.byKey(const ValueKey('now-playing-cover-previous')),
        findsOneWidget,
      );
      double opacity() => tester.widget<FadeTransition>(incoming).opacity.value;
      expect(opacity(), 0);
      var previous = opacity();
      for (var f = 0; f < 20; f++) {
        await tester.pump(const Duration(microseconds: 16667));
        expect(opacity(), greaterThanOrEqualTo(previous));
        expect(
          tester.getRect(find.byKey(const ValueKey('now-playing-cover-image'))),
          bounds,
        );
        expect(
          find.byKey(const ValueKey('now-playing-cover-placeholder')),
          findsNothing,
        );
        previous = opacity();
      }
      expect(opacity(), 1);
      expect(
        find.byKey(const ValueKey('now-playing-cover-previous')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      signal.dispose();
      PaintingBinding.instance.imageCache.clear();
    },
  );
  testWidgets(
    'asynchronous cover arrives without touching or rebuilding parent',
    (tester) async {
      final signal = ValueNotifier<ImageProvider<Object>?>(null);
      final cover = _DeferredCover();
      var parentBuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (_) {
              parentBuilds++;
              return NowPlayingCoverImage(
                changes: signal,
                readImage: () => signal.value,
                size: 200,
              );
            },
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('now-playing-cover-placeholder')),
        findsOneWidget,
      );
      signal.value = cover;
      await tester.pump();
      cover.frame.complete(ImageInfo(image: await pixel(tester, Colors.red)));
      await tester.pump();
      await tester.pump();
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      expect(parentBuilds, 1);
      expect(
        find.byKey(const ValueKey('now-playing-cover-placeholder')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      signal.dispose();
      PaintingBinding.instance.imageCache.clear();
    },
  );

  testWidgets(
    'same Image retains a decoded frame through slow/rapid track changes',
    (tester) async {
      final a = _DeferredCover(), b = _DeferredCover(), c = _DeferredCover();
      final signal = ValueNotifier<ImageProvider<Object>?>(a);
      await tester.pumpWidget(
        MaterialApp(
          home: NowPlayingCoverImage(
            changes: signal,
            readImage: () => signal.value,
            size: 200,
          ),
        ),
      );
      a.frame.complete(ImageInfo(image: await pixel(tester, Colors.red)));
      await tester.pump();
      await tester.pump();
      final oldFrame = tester
          .widget<RawImage>(find.byType(RawImage))
          .image!
          .clone();
      addTearDown(oldFrame.dispose);
      final imageElement = tester.element(
        find.byKey(const ValueKey('now-playing-cover-image')),
      );
      signal.value = b;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        tester
            .widget<RawImage>(find.byType(RawImage))
            .image!
            .isCloneOf(oldFrame),
        isTrue,
      );
      expect(
        tester.element(find.byKey(const ValueKey('now-playing-cover-image'))),
        same(imageElement),
      );
      signal.value = c;
      await tester.pump();
      c.frame.complete(ImageInfo(image: await pixel(tester, Colors.blue)));
      await tester.pump();
      await tester.pump();
      final current = tester
          .widget<RawImage>(
            find.byKey(const ValueKey('now-playing-cover-current')),
          )
          .image!
          .clone();
      addTearDown(current.dispose);
      expect(current.isCloneOf(oldFrame), isFalse);
      b.frame.complete(ImageInfo(image: await pixel(tester, Colors.green)));
      await tester.pump();
      expect(
        tester
            .widget<RawImage>(
              find.byKey(const ValueKey('now-playing-cover-current')),
            )
            .image!
            .isCloneOf(current),
        isTrue,
      );
      signal.value =
          null; // Definitively coverless: no indefinite previous song.
      await tester.pump();
      expect(find.byType(RawImage), findsNothing);
      expect(
        find.byKey(const ValueKey('now-playing-cover-placeholder')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      signal.dispose();
      PaintingBinding.instance.imageCache.clear();
    },
  );
}
