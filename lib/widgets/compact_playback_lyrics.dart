import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../page/playlist/playlist_models.dart';
import '../page/setting/settings_provider.dart';
import 'lyric_frame_clock.dart';
import 'mobile_lyrics_list.dart';

/// Three stable rows. Timing follows the full lyric view; words never lift.
class CompactPlaybackLyrics extends StatefulWidget {
  const CompactPlaybackLyrics({
    super.key,
    required this.lines,
    required this.active,
    this.position,
    this.karaokeEnabled = false,
    this.karaokeMode = KaraokeLyricsMode.timedOnly,
    this.smoothMotion = false,
    this.isPlaying = false,
    this.playbackRate = 1,
    this.actualPlayback,
    this.rate,
    this.seek,
    this.seekIntent,
    this.enabled = true,
  });
  final List<LyricLine> lines;
  final int active;
  final ValueListenable<Duration>? position;
  final bool karaokeEnabled, smoothMotion, isPlaying, enabled;
  final KaraokeLyricsMode karaokeMode;
  final double playbackRate;
  final ValueListenable<bool>? actualPlayback;
  final ValueListenable<double>? rate;
  final ValueListenable<Duration?>? seek;
  final ValueListenable<int>? seekIntent;
  @override
  State<CompactPlaybackLyrics> createState() => _CompactPlaybackLyricsState();
}

class _CompactPlaybackLyricsState extends State<CompactPlaybackLyrics>
    with TickerProviderStateMixin {
  late final _clock = KaraokeMediaClock(
    widget.position?.value ?? Duration.zero,
    rate: widget.rate?.value ?? widget.playbackRate,
    smoothMotion: widget.smoothMotion,
  );
  late final _frames = LyricFrameClock(this, (_) {});
  late final _shift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );
  double _from = 0, _to = 0;
  bool _running = false, _subscribed = false, _seeking = false, _visible = true;
  LyricLine? _line;
  Duration? _end;
  double get _start =>
      _from + (_to - _from) * Curves.easeOutCubic.transform(_shift.value);
  int get _target =>
      (widget.active - 1).clamp(0, math.max(0, widget.lines.length - 3));
  @override
  void initState() {
    super.initState();
    _from = _to = _target.toDouble();
    _attach();
    _prepareLine();
    _frames.available.addListener(_availability);
  }

  void _attach() {
    widget.position?.addListener(_position);
    widget.actualPlayback?.addListener(_sync);
    widget.rate?.addListener(_rate);
    widget.seek?.addListener(_seek);
    widget.seekIntent?.addListener(_seekIntent);
  }

  void _detach(CompactPlaybackLyrics old) {
    old.position?.removeListener(_position);
    old.actualPlayback?.removeListener(_sync);
    old.rate?.removeListener(_rate);
    old.seek?.removeListener(_seek);
    old.seekIntent?.removeListener(_seekIntent);
  }

  void _prepareLine() {
    final i = widget.active;
    final line = i >= 0 && i < widget.lines.length ? widget.lines[i] : null;
    _line = line == null
        ? null
        : compactKaraokeLine(
            line,
            enabled: widget.karaokeEnabled,
            mode: widget.karaokeMode,
            next: i + 1 < widget.lines.length
                ? widget.lines[i + 1].timestamp
                : null,
          );
    final tokens = _line?.tokens?.firstOrNull;
    _end = tokens == null || tokens.isEmpty
        ? null
        : tokens.map((t) => t.end).reduce((a, b) => a > b ? a : b);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled && widget.enabled;
    _frames.setEnabled(_visible);
    _sync();
  }

  @override
  void didUpdateWidget(CompactPlaybackLyrics old) {
    super.didUpdateWidget(old);
    if (old.position != widget.position ||
        old.actualPlayback != widget.actualPlayback ||
        old.rate != widget.rate ||
        old.seek != widget.seek ||
        old.seekIntent != widget.seekIntent) {
      _detach(old);
      _attach();
      _clock.handoffSource(widget.position?.value ?? _clock.value);
    }
    if (!identical(old.lines, widget.lines)) {
      _seeking = false;
      _clock.seek(widget.position?.value ?? Duration.zero);
    }
    _clock.smoothMotion = widget.smoothMotion;
    _rate();
    _prepareLine();
    final target = _target.toDouble();
    if (_to != target || !identical(old.lines, widget.lines)) {
      final current = _start;
      _from = current;
      _to = target;
      if (!identical(old.lines, widget.lines) ||
          (target - current).abs() > 1.01 ||
          MediaQuery.disableAnimationsOf(context)) {
        _from = target;
        _shift.value = 1;
      } else {
        _shift.forward(from: 0);
      }
    }
    _visible = TickerMode.valuesOf(context).enabled && widget.enabled;
    _frames.setEnabled(_visible);
    _sync();
  }

  void _position() {
    if (!_seeking) _clock.readSource(widget.position!.value);
    _sync();
  }

  void _rate() => _clock.changeRate(
    widget.rate?.value ?? widget.playbackRate,
    widget.position?.value ?? _clock.value,
  );
  void _seekIntent() {
    _seeking = true;
    _sync();
  }

  void _seek() {
    final target = widget.seek?.value;
    if (target == null) return;
    _clock.seek(target, protectFromStaleSource: true);
    _seeking = false;
    _sync();
  }

  void _availability() {
    if (_frames.available.value) {
      _clock.handoffSource(widget.position?.value ?? _clock.value);
    }
    _sync();
  }

  void _tick() {
    _clock.tick(_frames.elapsed);
    _syncFrames();
  }

  void _sync() {
    final running =
        widget.isPlaying &&
        (widget.actualPlayback?.value ?? true) &&
        !_seeking &&
        _visible &&
        _frames.available.value;
    if (_running != running) {
      _running = running;
      _clock.setRunning(running, widget.position?.value ?? _clock.value);
      _clock.rebaseElapsed(_frames.elapsed);
    }
    _syncFrames();
  }

  void _syncFrames() {
    if (!_subscribed && _running && _end != null) {
      _clock.handoffSource(widget.position?.value ?? _clock.value);
    }
    final needs = _running && _end != null && _clock.value < _end!;
    if (needs == _subscribed) return;
    _subscribed = needs;
    if (needs) {
      _clock.rebaseElapsed(_frames.elapsed);
      _frames.addListener(_tick);
    } else {
      _frames.removeListener(_tick);
    }
  }

  @override
  void dispose() {
    _detach(widget);
    _frames.available.removeListener(_availability);
    _frames.dispose();
    _clock.dispose();
    _shift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 72,
    child: ClipRect(
      child: AnimatedBuilder(
        animation: _shift,
        builder: (context, _) {
          final start = _start;
          return Stack(
            children: [
              for (var i = start.floor(); i < start.ceil() + 3; i++)
                Positioned(
                  key: ValueKey(i),
                  left: 0,
                  right: 0,
                  top: (i - start) * 24,
                  height: 24,
                  child: AnimatedOpacity(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    opacity: i == widget.active ? 1 : .5,
                    child: _CompactRow(
                      line: i < widget.lines.length ? widget.lines[i] : null,
                      fallback: widget.lines.isEmpty && i == 0 ? '暂无歌词' : '',
                      karaoke: i == widget.active ? _line : null,
                      clock: _clock,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

/// Same opt-in and synthetic timing policy as the full lyric renderer.
LyricLine? compactKaraokeLine(
  LyricLine line, {
  required bool enabled,
  required KaraokeLyricsMode mode,
  Duration? next,
}) {
  if (!canAnimateLyricLine(line, enabled, mode)) return null;
  final effective = hasUsableKaraokeTiming(line)
      ? line
      : mode == KaraokeLyricsMode.all
      ? synthesizeKaraokeTiming(line, nextTimestamp: next)
      : null;
  return effective != null && hasUsableKaraokeTiming(effective)
      ? effective
      : null;
}

class _CompactRow extends StatefulWidget {
  const _CompactRow({
    required this.line,
    required this.karaoke,
    required this.clock,
    required this.fallback,
  });
  final LyricLine? line, karaoke;
  final KaraokeMediaClock clock;
  final String fallback;
  @override
  State<_CompactRow> createState() => _CompactRowState();
}

class _CompactRowState extends State<_CompactRow> {
  Object? _layoutKey;
  CompactLyricInkLayout? _layout;
  @override
  void dispose() {
    _layout?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final text = line == null
        ? widget.fallback
        : line.isInterlude ||
              line.texts.isEmpty ||
              line.texts.first.trim().isEmpty
        ? '…'
        : line.texts.first;
    final style =
        (Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 12))
            .copyWith(
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurface,
            );
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final child = Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
    if (widget.karaoke == null) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final key = (
          text,
          style,
          direction,
          scaler,
          constraints.maxWidth,
          widget.karaoke,
        );
        if (_layoutKey != key) {
          _layout?.dispose();
          _layoutKey = key;
          _layout = CompactLyricInkLayout(
            text: text,
            style: style,
            direction: direction,
            scaler: scaler,
            width: constraints.maxWidth,
            tokens: widget.karaoke!.tokens!.first,
          );
        }
        return CustomPaint(
          key: const ValueKey('compact-karaoke-ink'),
          foregroundPainter: _CompactInk(_layout!, widget.clock),
          child: Opacity(opacity: .45, child: child),
        );
      },
    );
  }
}

/// Measured once per paragraph/constraint change, never in the frame callback.
class CompactLyricInkLayout {
  CompactLyricInkLayout({
    required String text,
    required TextStyle style,
    required TextDirection direction,
    required TextScaler scaler,
    required double width,
    required List<LyricToken> tokens,
  }) : painter = TextPainter(
         text: TextSpan(text: text, style: style),
         textDirection: direction,
         textScaler: scaler,
         maxLines: 1,
         ellipsis: '…',
       ) {
    painter.layout(minWidth: width, maxWidth: width);
    final full = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    var cursor = 0;
    for (final token in tokens) {
      final start = text.indexOf(token.text, cursor);
      if (start < 0 || token.text.isEmpty) continue;
      cursor = start + token.text.length;
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: cursor),
      );
      final fullBoxes = full.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: cursor),
      );
      if (boxes.isNotEmpty) {
        spans.add((
          token,
          boxes,
          fullBoxes.fold<double>(0, (sum, box) => sum + box.right - box.left),
        ));
      }
    }
    full.dispose();
  }
  final TextPainter painter;
  final spans = <(LyricToken, List<TextBox>, double)>[];
  void dispose() => painter.dispose();
}

class _CompactInk extends CustomPainter {
  _CompactInk(this.layout, this.clock) : super(repaint: clock);
  final CompactLyricInkLayout layout;
  final KaraokeMediaClock clock;
  @override
  void paint(Canvas canvas, Size size) {
    final dy = (size.height - layout.painter.height) / 2;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final (token, boxes, width) in layout.spans) {
      final progress = karaokeVisualTokenProgress(token, clock.value);
      if (progress <= 0) continue;
      var remaining = width * progress;
      for (final box in boxes) {
        final take = math.min(remaining, box.right - box.left);
        remaining -= take;
        if (take <= 0) continue;
        final left = box.direction == TextDirection.rtl
            ? box.right - take
            : box.left;
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(left, 0, left + take, size.height));
        layout.painter.paint(canvas, Offset(0, dy));
        canvas.restore();
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CompactInk old) =>
      old.layout != layout || old.clock != clock;
}

/// Token timing is used when supplied; ordinary LRC remains estimated.
double compactLyricProgress(LyricLine line, Duration position, Duration? next) {
  final tokens = line.tokens;
  if (tokens != null && tokens.isNotEmpty && tokens.first.isNotEmpty) {
    var done = 0.0, total = 0;
    for (final token in tokens.first) {
      final length = token.text.runes.length;
      total += length;
      final span = token.end.inMicroseconds - token.start.inMicroseconds;
      done +=
          length *
          (span <= 0
              ? (position >= token.end ? 1 : 0)
              : ((position.inMicroseconds - token.start.inMicroseconds) / span)
                    .clamp(0.0, 1.0));
    }
    return total == 0 ? 0 : (done / total).clamp(0.0, 1.0);
  }
  final end = next ?? line.timestamp + const Duration(seconds: 4);
  final span = end.inMicroseconds - line.timestamp.inMicroseconds;
  return span <= 0
      ? 0
      : ((position.inMicroseconds - line.timestamp.inMicroseconds) / span)
            .clamp(0.0, 1.0);
}
