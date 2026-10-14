part of 'mobile_lyrics_list.dart';

/// Image readback and bounds work only in the existing serial atlas job.
/// Pixel arrays are transient; the paint loop only reads cached sweep paths.
extension _KaraokeInkBounds on _KaraokePaintCache {
  Future<void> _calibrateInkPaths(ui.Image atlas, ui.Image coverage) async {
    final ink = await InteractionPerformanceController.instance
        .runIdleResource<ByteData?>(
          () => atlas.toByteData(format: ui.ImageByteFormat.rawRgba),
          priority: InteractionWorkPriority.currentVisual,
          allowDuringVisualAnimation: true,
          isStillNeeded: _rasterNeeded,
        );
    if (_disposed || ink == null) return;
    final alpha = await InteractionPerformanceController.instance
        .runIdleResource<ByteData?>(
          () => coverage.toByteData(format: ui.ImageByteFormat.rawRgba),
          priority: InteractionWorkPriority.currentVisual,
          allowDuringVisualAnimation: true,
          isStillNeeded: _rasterNeeded,
        );
    if (_disposed || alpha == null) return;
    final pixels = ink.buffer.asUint8List(ink.offsetInBytes, ink.lengthInBytes);
    final white = alpha.buffer.asUint8List(
      alpha.offsetInBytes,
      alpha.lengthInBytes,
    );
    final minima = Int32List(509)..fillRange(0, 509, atlas.width);
    final maxima = Int32List(509)..fillRange(0, 509, -1);
    var cursor = 0;
    while (cursor < pixels.length) {
      final lease = await InteractionPerformanceController.instance
          .acquireIdleWork(
            priority: InteractionWorkPriority.currentVisual,
            allowDuringVisualAnimation: true,
            isStillNeeded: _rasterNeeded,
          );
      try {
        if (!lease.isGranted || _disposed) return;
        final budget = Stopwatch()..start();
        final end = math.min(pixels.length, cursor + 32768);
        for (; cursor < end; cursor += 4) {
          if ((cursor & 1023) == 0 && budget.elapsedMicroseconds >= 1500) break;
          final a = pixels[cursor + 3];
          if (a < 8 || white[cursor + 3] < 8) continue;
          final r = ((pixels[cursor] * 255 / a - 28) / 28).round().clamp(0, 7);
          final g = ((pixels[cursor + 1] * 255 / a - 28) / 28).round().clamp(
            0,
            7,
          );
          final b = ((pixels[cursor + 2] * 255 / a - 28) / 28).round().clamp(
            0,
            7,
          );
          final id = r + g * 8 + b * 64;
          if (id >= 509) continue;
          final x = (cursor ~/ 4) % atlas.width;
          minima[id] = math.min(minima[id], x);
          maxima[id] = math.max(maxima[id], x);
        }
      } finally {
        lease.release();
      }
      if (cursor < pixels.length) await Future<void>.delayed(Duration.zero);
    }
    if (_disposed) return;
    for (final token in tokens) {
      if (token.nativeShaping) continue;
      for (final unit in token.units) {
        final id = unit.inkId;
        if (id >= 509 || maxima[id] < minima[id]) continue;
        // Exact coverage bounds include overhangs; the ink mask is unchanged.
        unit.sweep = KaraokeSweepPath([
          (
            start: fullBounds.left + minima[id] / _imageScale,
            end: fullBounds.left + (maxima[id] + 1) / _imageScale,
          ),
        ]);
      }
      for (final fragment in token.fragments) {
        fragment.sweep = KaraokeSweepPath(
          token.units
              .where((u) => identical(u.fragment, fragment))
              .expand((u) => u.sweep.spans),
        );
      }
    }
    assert(() {
      debugKaraokeInkBoundsScanCount++;
      return true;
    }());
  }
}

int debugKaraokeInkBoundsScanCount = 0;
