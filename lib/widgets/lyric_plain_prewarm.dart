import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../page/playlist/playlist_models.dart';
import '../services/interaction_performance_controller.dart';
import 'lyric_raster_pool.dart';

final _colorGlyph = RegExp(
  r'[\u00a9\u00ae\u200d\u20e3\u2600-\u27ff\ufe0f\u{1f000}-\u{1faff}]',
  unicode: true,
);

bool plainLyricRasterSupported(String text, TextStyle style) =>
    !_colorGlyph.hasMatch(text) &&
    style.foreground == null &&
    style.background == null &&
    style.backgroundColor == null &&
    (style.shadows?.isEmpty ?? true) &&
    (style.decoration == null || style.decoration == TextDecoration.none);

bool sameLyricRgb(Color a, Color b) =>
    a.colorSpace == b.colorSpace &&
    (a.r - b.r).abs() <= 1e-12 &&
    (a.g - b.g).abs() <= 1e-12 &&
    (a.b - b.b).abs() <= 1e-12;

/// A list-local time window. Entries exist independently of mounted slivers,
/// so becoming the next row does not start the first expensive preparation.
class LyricPlainPrewarm {
  final _entries = <int, LyricPlainPrepared>{};
  Object? _configuration;
  bool enabled = true;

  LyricPlainPrepared? at(int index) => _entries[index];
  Iterable<int> get indices => _entries.keys;

  void update({
    required List<LyricLine> lines,
    required int active,
    required double rate,
    required bool visible,
    required bool Function(LyricLine) eligible,
    required double width,
    required double dpr,
    required TextStyle style,
    required TextAlign align,
    required TextDirection direction,
    required TextScaler scaler,
    required Locale? locale,
    required Color inactive,
    required Color activeColor,
  }) {
    final colors = [inactive.withValues(alpha: 1)];
    if (!sameLyricRgb(inactive, activeColor)) {
      colors.add(activeColor.withValues(alpha: 1));
    }
    final normalized = style.copyWith(
      inherit: false,
      color: colors.first,
      decorationColor: colors.first,
      shadows: null,
    );
    final configuration = (
      lines,
      width,
      dpr,
      normalized,
      align,
      direction,
      scaler,
      locale,
      colors.first,
      colors.last,
    );
    var changed = enabled != visible;
    if (_configuration != configuration) {
      clear();
      _configuration = configuration;
      changed = true;
    }
    enabled = visible;
    final wanted = <int, int>{};
    final current = active.clamp(0, lines.isEmpty ? 0 : lines.length - 1);
    if (lines.isNotEmpty) {
      wanted[current] = 0;
      // Cover the coming phrase's 2.4s, including a dense verse after a held
      // note. At least two future rows, at most six; the shared pixel budget
      // may admit fewer oversized rows. Playback speed scales the media window.
      final horizon =
          lines[current + 1 < lines.length ? current + 1 : current].timestamp +
          Duration(milliseconds: (2400 * rate.clamp(.25, 4.0)).round());
      for (var step = 1; step <= 6 && current + step < lines.length; step++) {
        final index = current + step;
        if (step > 2 && lines[index].timestamp > horizon) break;
        wanted[index] = step;
      }
      if (current > 0) wanted[current - 1] = 8;
    }
    for (final index in _entries.keys.toList()) {
      if (!wanted.containsKey(index) || !eligible(lines[index])) {
        _entries.remove(index)!.dispose();
        changed = true;
      }
    }
    for (final item in wanted.entries) {
      final line = lines[item.key];
      final text = line.texts.join('\n');
      if (!eligible(line) || !plainLyricRasterSupported(text, normalized)) {
        continue;
      }
      final entry = _entries.putIfAbsent(item.key, () {
        changed = true;
        return LyricPlainPrepared(
          owner: this,
          text: text,
          width: width,
          dpr: dpr,
          style: normalized,
          align: align,
          direction: direction,
          scaler: scaler,
          locale: locale,
          colors: colors,
        );
      });
      if (entry.rank != item.value) changed = true;
      entry.rank = item.value;
    }
    if (changed) LyricRasterPool.schedule();
  }

  void clear() {
    for (final entry in _entries.values) {
      entry.dispose();
    }
    _entries.clear();
    _configuration = null;
  }
}

class LyricPlainPrepared extends ChangeNotifier implements LyricRasterClient {
  LyricPlainPrepared({
    required this.owner,
    required this.text,
    required this.width,
    required this.dpr,
    required this.style,
    required this.align,
    required this.direction,
    required this.scaler,
    required this.locale,
    required this.colors,
  }) {
    _sequence = LyricRasterPool.register(this);
    // Use known layout width now; native text shaping itself waits for its
    // serialized work lease rather than running in the widget's build.
    LyricRasterPool.schedule();
  }
  final LyricPlainPrewarm owner;
  final String text;
  final double width, dpr;
  final TextStyle style;
  final TextAlign align;
  final TextDirection direction;
  final TextScaler scaler;
  final Locale? locale;
  final List<Color> colors;
  int rank = 0;
  late final int _sequence;
  int _pixels = 0;
  bool _disposed = false, _failed = false;
  _PreparedJob? _job;
  final _images = <ui.Image>[];
  ui.Image? get image => _images.firstOrNull;
  ui.Image? imageFor(Color color) {
    final index = colors.indexWhere((c) => sameLyricRgb(c, color));
    return index >= 0 && index < _images.length ? _images[index] : null;
  }

  Size? contentSize;
  static const padding = 32.0;
  int get _rank => rank + (owner.enabled ? 0 : 10000);
  @override
  int get rasterRank => _rank * 2;
  @override
  int get rasterSequence => _sequence;
  @override
  bool get rasterReserved => _job != null;
  @override
  int get rasterDemand => _disposed || _failed
      ? 0
      : !owner.enabled && image == null
      ? 0
      : _pixels;

  /// Supply the already measured height; no additional layout in this call.
  void measureHeight(double height) {
    final w = ((width + padding * 2) * dpr).ceil();
    final h = ((height + padding * 2) * dpr).ceil() + 1;
    final eligible =
        dpr >= 1 &&
        dpr <= 4 &&
        width > 0 &&
        height > 0 &&
        w <= 4096 &&
        h <= 4096 &&
        w * h <= 2097152;
    _pixels = eligible ? w * h * colors.length : 0;
  }

  InteractionWorkPriority _priority() => _rank <= 1
      ? InteractionWorkPriority.currentVisual
      : _rank < 8
      ? InteractionWorkPriority.userVisible
      : InteractionWorkPriority.background;

  @override
  void reserveRaster() {
    if (_job != null || rasterDemand == 0) return;
    final job = _PreparedJob(LyricRasterReservation(rasterDemand));
    _job = job;
    bool needed() => !_disposed && _job == job && owner.enabled;
    job.needed = needed;
    unawaited(() async {
      final lease = await InteractionPerformanceController.instance
          .acquireIdleWork(
            priority: _priority(),
            priorityForWork: _priority,
            isStillNeeded: needed,
            // Automatic lyric motion permits bounded work, just like karaoke.
            // Real touch/fling/route protections still reject these requests.
            allowDuringVisualAnimation: true,
          );
      ui.Picture? picture;
      TextPainter? painter;
      final pending = <ui.Image>[];
      try {
        if (!lease.isGranted || !needed()) return;
        painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textAlign: align,
          textDirection: direction,
          textScaler: scaler,
          locale: locale,
        )..layout(minWidth: width, maxWidth: width);
        final size = Size(width, painter.height);
        final w = ((width + padding * 2) * dpr).ceil();
        final h = ((size.height + padding * 2) * dpr).ceil();
        if (w * h * colors.length > job.reservation.pixels) {
          _failed = true;
          return;
        }
        for (var i = 0; i < colors.length; i++) {
          if (!needed()) return;
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder)..scale(dpr);
          painter.text = TextSpan(
            text: text,
            style: style.copyWith(color: colors[i], decorationColor: colors[i]),
          );
          painter.layout(minWidth: width, maxWidth: width);
          painter.paint(canvas, const Offset(padding, padding));
          picture = recorder.endRecording();
          job.started = true;
          pending.add(await picture.toImage(w, h));
          picture.dispose();
          picture = null;
        }
        if (!needed()) {
          return;
        }
        _images.addAll(pending);
        pending.clear();
        contentSize = size;
        notifyListeners();
      } catch (_) {
        if (!_disposed && _job == job) _failed = true;
      } finally {
        painter?.dispose();
        picture?.dispose();
        for (final image in pending) {
          image.dispose();
        }
        job.finished = true;
        if (_job != job || image == null) {
          job.reservation.release();
          if (_job == job) _job = null;
        }
        lease.release();
      }
    }());
  }

  Rect? sourceFor(Color color, Size actualSize) {
    final size = contentSize, atlas = imageFor(color);
    if (size == null ||
        atlas == null ||
        (actualSize.width - size.width).abs() > .01 ||
        actualSize.height + .01 < size.height) {
      return null;
    }
    return Rect.fromLTWH(0, 0, atlas.width.toDouble(), atlas.height.toDouble());
  }

  @override
  void evictRaster() {
    final job = _job;
    _job = null;
    if (job != null) {
      InteractionPerformanceController.instance.cancelIdleWork(job.needed);
      if (!job.started || job.finished) job.reservation.release();
    }
    for (final image in _images) {
      image.dispose();
    }
    _images.clear();
    contentSize = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    LyricRasterPool.unregister(this);
    evictRaster();
    super.dispose();
  }
}

class _PreparedJob {
  _PreparedJob(this.reservation);
  final LyricRasterReservation reservation;
  late final bool Function() needed;
  bool started = false, finished = false;
}

class LyricPlainPrewarmScope extends InheritedWidget {
  const LyricPlainPrewarmScope({
    super.key,
    required this.entry,
    required super.child,
  });
  final LyricPlainPrepared? entry;
  static LyricPlainPrewarmScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LyricPlainPrewarmScope>();
  @override
  bool updateShouldNotify(LyricPlainPrewarmScope oldWidget) =>
      oldWidget.entry != entry;
}
