import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/artwork_image.dart';
import 'package:myune_music/widgets/now_playing_cover_image.dart';
import 'package:myune_music/widgets/landscape_playback_surface.dart';
import 'now_playing_cover_image_test.dart' as fixture;

class _Deferred extends ImageProvider<_Deferred> {
  final frame = Completer<ImageInfo>();
  @override
  Future<_Deferred> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(_Deferred key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(frame.future);
}

void main() {
  testWidgets(
    'latest pending request cancels an obsolete decoded queue entry',
    (tester) async {
      final a = _Deferred(), b = _Deferred(), c = _Deferred(), d = _Deferred();
      final signal = ValueNotifier<ImageProvider<Object>>(a);
      addTearDown(signal.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: NowPlayingCoverImage(
            size: 200,
            changes: signal,
            readImage: () => signal.value,
          ),
        ),
      );
      Future<void> resolve(_Deferred provider, Color color) async {
        signal.value = provider;
        await tester.pump();
        provider.frame.complete(
          ImageInfo(image: await fixture.pixel(tester, color)),
        );
        await tester.pump();
        await tester.pump();
      }

      await resolve(a, Colors.red);
      await resolve(b, Colors.blue);
      await tester.pump(const Duration(milliseconds: 100));
      await resolve(c, Colors.green);
      signal.value = d;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 230));
      final opacity = tester
          .widget<FadeTransition>(
            find.byKey(const ValueKey('now-playing-cover-fade')),
          )
          .opacity
          .value;
      expect(
        opacity,
        1,
        reason: 'obsolete C must not start while latest D is pending',
      );
      expect(
        find.byKey(const ValueKey('now-playing-cover-previous')),
        findsNothing,
      );
      await resolve(d, Colors.orange);
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        tester
            .widget<FadeTransition>(
              find.byKey(const ValueKey('now-playing-cover-fade')),
            )
            .opacity
            .value,
        inExclusiveRange(0, 1),
      );
      await tester.pumpWidget(const SizedBox());
      PaintingBinding.instance.imageCache.clear();
    },
  );
  testWidgets('stale landscape props cannot paint both layers in portrait', (
    tester,
  ) async {
    for (final mode in [LandscapeCoverMode.duet, LandscapeCoverMode.info]) {
      for (final lyrics in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: LandscapePlaybackSurface(
              landscape: false,
              mode: mode,
              showLyrics: lyrics,
              title: '',
              artist: '',
              cover: const Text('cover'),
              lyrics: const Text('lyrics'),
              onModeChanged: (_) {},
            ),
          ),
        );
        expect(find.text('cover'), lyrics ? findsNothing : findsOneWidget);
        expect(find.text('lyrics'), lyrics ? findsOneWidget : findsNothing);
      }
    }
  });
  testWidgets(
    'same artwork re-decode during a replacement does not queue a second fade',
    (tester) async {
      Future<Uint8List> png(Color color) async {
        final image = await fixture.pixel(tester, color);
        final data = (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.png),
        ))!;
        image.dispose();
        return data.buffer.asUint8List();
      }

      final red = await png(Colors.red), blue = await png(Colors.blue);
      final signal = ValueNotifier<ImageProvider<Object>>(MemoryImage(red));
      addTearDown(signal.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: NowPlayingCoverImage(
            size: 200,
            changes: signal,
            readImage: () => signal.value,
          ),
        ),
      );
      Future<void> decoded() async {
        await tester.runAsync(() async {
          final ready = Completer<void>();
          final stream = signal.value.resolve(const ImageConfiguration());
          final listener = ImageStreamListener(
            (info, synchronous) {
              info.dispose();
              if (!ready.isCompleted) ready.complete();
            },
            onError: (Object error, StackTrace? stack) {
              if (!ready.isCompleted) ready.completeError(error, stack);
            },
          );
          stream.addListener(listener);
          try {
            await ready.future.timeout(const Duration(seconds: 10));
          } finally {
            stream.removeListener(listener);
          }
        });
        await tester.pump();
        await tester.pump();
      }

      double opacity() => tester
          .widget<FadeTransition>(
            find.byKey(const ValueKey('now-playing-cover-fade')),
          )
          .opacity
          .value;
      await decoded();
      signal.value = MemoryImage(blue);
      await tester.pump();
      await decoded();
      await tester.pump(const Duration(milliseconds: 80));
      expect(opacity(), inExclusiveRange(0, 1));
      final before = opacity();
      signal.value = CoverMemoryImage(
        Uint8List.fromList(blue),
        targetPixels: 512,
      );
      await tester.pump();
      await decoded();
      expect(opacity(), before);
      await tester.pump(const Duration(milliseconds: 250));
      expect(opacity(), 1);
      expect(
        find.byKey(const ValueKey('now-playing-cover-previous')),
        findsNothing,
      );
      await tester.pump(const Duration(milliseconds: 80));
      expect(opacity(), 1);
      await tester.pumpWidget(const SizedBox());
      PaintingBinding.instance.imageCache.clear();
    },
  );
}
