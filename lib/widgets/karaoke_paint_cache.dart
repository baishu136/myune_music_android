part of 'mobile_lyrics_list.dart';

// Debug counters do not run in release. Tests check layout and native-picture
// ownership, including colour-only focus transitions and repeated remounts.
int debugKaraokeLayoutBuildCount = 0;
int debugKaraokeTextLayoutCount = 0;
int debugKaraokeLivePictureCount = 0;
int debugKaraokeSolidLayerCount = 0;
int debugKaraokeGradientLayerCount = 0;

ui.FragmentProgram? _karaokeInkProgram;
Future<ui.FragmentProgram>? _karaokeInkProgramFuture;
Future<void>? _karaokeRasterTail;
// Joining/combining and colour-font glyphs retain exact native coverage.
final _karaokeJoinedRun = RegExp(r'[\u0300-\u036F\u0590-\u0FFF\u200D]');
final _karaokeColorGlyph = RegExp(
  r'[\u200D\uFE0F\u2600-\u27FF\u{1F000}-\u{1FAFF}]',
  unicode: true,
);
Future<ui.FragmentProgram> _loadKaraokeInkProgram() {
  if (_karaokeInkProgram case final program?) return Future.value(program);
  return _karaokeInkProgramFuture ??= () async {
    try {
      return _karaokeInkProgram ??= await ui.FragmentProgram.fromAsset(
        'shaders/karaoke_ink.frag',
      );
    } finally {
      _karaokeInkProgramFuture = null;
    }
  }();
}

double karaokeFeatherWidth(double lineHeight) =>
    (lineHeight * karaokeDefaultMotion.highlightFeatherFraction).clamp(
      12.0,
      18.0,
    );

class _KaraokePaintStyle {
  _KaraokePaintStyle(this.active, this.inactive)
    : activeLayer = Paint()
        ..colorFilter = ui.ColorFilter.mode(active, BlendMode.srcIn),
      inactiveLayer = Paint()
        ..colorFilter = ui.ColorFilter.mode(inactive, BlendMode.srcIn),
      translationLayer = Paint()
        ..colorFilter = ui.ColorFilter.mode(
          inactive.withValues(alpha: inactive.a * .6),
          BlendMode.srcIn,
        ),
      gradient = Paint()
        ..blendMode = BlendMode.srcIn
        ..shader = ui.Gradient.linear(Offset.zero, const Offset(1, 0), [
          active,
          inactive,
        ]) {
    translation = inactive.withValues(alpha: inactive.a * .6);
    _focusGradients = List.generate(
      65,
      (index) => index == 64
          ? gradient
          : (Paint()
              ..blendMode = BlendMode.srcIn
              ..shader = ui.Gradient.linear(Offset.zero, const Offset(1, 0), [
                Color.lerp(inactive, active, index / 64)!,
                inactive,
              ])),
    );
  }
  final Color active;
  final Color inactive;
  late final Color translation;
  late final List<Paint> _focusGradients;
  Paint gradientForStrength(double strength) =>
      _focusGradients[(strength.clamp(0.0, 1.0) * 64).round()];
  _KaraokePaintStyle withColors(Color active, Color inactive) =>
      _KaraokePaintStyle(active, inactive);
  final Paint activeLayer;
  final Paint inactiveLayer;
  final Paint translationLayer;
  final Paint gradient;
  final Paint coverageLayer = Paint();
}

class _KaraokeFragment {
  _KaraokeFragment(this.bounds, this.direction, this.row);
  Rect bounds;
  late final Rect layerBounds;
  final TextDirection direction;
  final int row;
  double startRatio = 0;
  double endRatio = 1;
  int index = 0;
  ui.Picture? mask;
  _KaraokeNativeInk? nativeInk;
  late final KaraokeSweepPath sweep;
  late double feather;
  _KaraokeSweepRelay? relay;
}

class _KaraokeSweepRelay {
  _KaraokeSweepRelay(this.path, this.timeline, this.rtl, this.feather);
  final KaraokeSweepPath path;
  final KaraokeSweepTimeline timeline;
  final bool rtl;
  final double feather;
  double phase = 0;
  double front = 0;
}

class _KaraokeNativeInk {
  _KaraokeNativeInk(this.image, this.shader);
  final ui.Image image;
  final ui.FragmentShader shader;
  void dispose() {
    shader.dispose();
    image.dispose();
  }
}

class _KaraokeUnit {
  _KaraokeUnit(this.range, this.bounds, this.fragment);
  final _KaraokePaintRange range;
  final Rect bounds;
  final _KaraokeFragment fragment;
  late final Rect layerBounds;
  int inkId = 0;
  ui.FragmentShader? shader;
  late final KaraokeGlyphTiming timing;
  late final KaraokeSweepPath sweep;
}

class _KaraokePaintToken {
  _KaraokePaintToken(this.range, this.units, this.fragments, this.bounds);
  final _KaraokeTokenRange range;
  final List<_KaraokeUnit> units;
  final List<_KaraokeFragment> fragments;
  final Rect bounds;
  int firstUnit = 0;
  bool nativeShaping = false;
  late final int visualStartUs;
  late final int spanUs;
}

/// Owned by a lyric State (or the single list-local prewarm spare), never by
/// individual frame painters. Preparing a
/// layout records shaped masks once. Pictures contain complete shaped runs,
/// preserving joining scripts; unsupported/super-long tokens use whole runs.
/// No global glyph cache: culling a row releases all its native pictures.
class _KaraokePaintCache extends ChangeNotifier {
  _KaraokePaintCache({
    required this.text,
    required this.ranges,
    required this.synthetic,
    required this.width,
    required this.style,
    required this.textAlign,
    required this.textDirection,
    required this.textScaler,
    required this.locale,
    this.pixelRatio = 1,
  }) {
    assert(() {
      debugKaraokeLayoutBuildCount++;
      return true;
    }());
    final layout = _layout(TextSpan(text: text, style: _maskStyle));
    final baseRecorder = ui.PictureRecorder();
    layout.paint(Canvas(baseRecorder), Offset.zero);
    _baseMask = baseRecorder.endRecording();
    assert(() {
      debugKaraokeLivePictureCount++;
      return true;
    }());
    height = layout.height;
    lineHeight = layout.preferredLineHeight;
    feather = karaokeFeatherWidth(lineHeight);
    liftHeight = -karaokeLiftPixels(1, lineHeight, karaokeDefaultMotion);
    final overflow = (lineHeight * .2).clamp(3.0, 16.0);
    final rasterRatio = pixelRatio.clamp(1.0, 4.0);
    fullBounds = Rect.fromLTRB(
      (-overflow * rasterRatio).floor() / rasterRatio,
      (-overflow * rasterRatio).floor() / rasterRatio,
      ((width + overflow) * rasterRatio).ceil() / rasterRatio,
      ((height + overflow) * rasterRatio).ceil() / rasterRatio,
    );
    // Two bounded atlases (<=4 MiB combined), never a texture per character.
    var imageScale = math.min(
      pixelRatio.clamp(1.0, 4.0),
      math.min(
        4096 / fullBounds.longestSide,
        math.sqrt(524288 / (fullBounds.width * fullBounds.height)),
      ),
    );
    while ((fullBounds.width * imageScale).ceil() *
            (fullBounds.height * imageScale).ceil() >
        524288) {
      imageScale *= .999;
    }
    _imageScale = imageScale;
    _lines = layout.computeLineMetrics();
    _textLines = List.generate(
      _lines.length,
      (row) => layout.getLineBoundary(
        layout.getPositionForOffset(
          Offset(
            _lines[row].left + _lines[row].width / 2,
            _lines[row].baseline,
          ),
        ),
      ),
    );
    var originalEnd = text.indexOf('\n');
    if (originalEnd < 0) originalEnd = text.length;
    final drawable = <_KaraokeTokenRange>[];
    var unitCount = 0;
    var fragmentCount = 0;
    for (final range in ranges) {
      if (range.start < 0 ||
          range.end > originalEnd ||
          range.end <= range.start) {
        continue;
      }
      final wholeBoxes = _boxes(layout, range);
      if (wholeBoxes.isEmpty) continue;
      var offsets = karaokeGraphemeRanges(
        text.substring(range.start, range.end),
        startOffset: range.start,
      );
      // Avoid separating ligatures, joining/combining scripts or unbounded
      // paragraph copies for pathological long lyrics. They still sweep and
      // lift as shaped runs, with a separate fragment at every physical wrap.
      final tokenText = text.substring(range.start, range.end);
      final complex = _karaokeJoinedRun.hasMatch(tokenText);
      final nativeColor = _karaokeColorGlyph.hasMatch(tokenText);
      var wholeRun =
          complex ||
          nativeColor ||
          style.fontStyle == FontStyle.italic ||
          offsets.length + unitCount > 256;
      final selections = <List<ui.TextBox>>[];
      final visibleBoxes = <ui.TextBox>[];
      Rect? previous;
      if (offsets.length <= 256) {
        for (final offset in offsets) {
          final boxes = _boxes(
            layout,
            _KaraokePaintRange(start: offset.start, end: offset.end),
          );
          visibleBoxes.addAll(boxes);
          selections.add(boxes);
          if (wholeRun) continue;
          final glyph = boxes.length == 1
              ? layout.getClosestGlyphForOffset(boxes.first.toRect().center)
              : null;
          if (boxes.length != 1 ||
              (glyph != null &&
                  (glyph.graphemeClusterCodeUnitRange.start < offset.start ||
                      glyph.graphemeClusterCodeUnitRange.end > offset.end)) ||
              (previous != null && previous.overlaps(boxes.first.toRect()))) {
            wholeRun = true;
            continue;
          }
          previous = boxes.first.toRect();
        }
      } else {
        // Bound pathological paragraph work. Whole non-whitespace runs still
        // exclude word gaps without measuring every letter of a huge token.
        for (final match in RegExp(r'\S+').allMatches(tokenText).take(256)) {
          visibleBoxes.addAll(
            _boxes(
              layout,
              _KaraokePaintRange(
                start: range.start + match.start,
                end: range.start + match.end,
              ),
            ),
          );
        }
        if (RegExp(r'\S+').allMatches(tokenText).length > 256) {
          visibleBoxes.clear();
          visibleBoxes.addAll(wholeBoxes);
        }
      }
      if (wholeRun) {
        offsets = [(start: range.start, end: range.end)];
        selections.clear();
        selections.add(wholeBoxes);
      }
      if (offsets.isEmpty) continue;
      final units = <_KaraokeUnit>[];
      final fragments = <_KaraokeFragment>[];
      for (var i = 0; i < offsets.length; i++) {
        for (final box in selections[i]) {
          final bounds = box.toRect();
          final row = _physicalRow(bounds);
          // Only adjacent shaped runs can join. A/font-fallback/B must not
          // become two overlapping bounding rectangles with double width.
          final previous = fragments.isEmpty ? null : fragments.last;
          final fragment =
              previous != null &&
                  previous.row == row &&
                  (wholeRun || previous.direction == box.direction)
              ? previous
              : (_KaraokeFragment(bounds, box.direction, row)
                  ..index = fragmentCount++);
          if (!identical(previous, fragment)) fragments.add(fragment);
          fragment.bounds = fragment.bounds.expandToInclude(bounds);
          if (wholeRun &&
              units.isNotEmpty &&
              identical(units.last.fragment, fragment)) {
            // Keep the complete shaped run, including its different fallback
            // fonts, as one moving unit. Its highlight still sweeps normally.
            final old = units.removeLast();
            units.add(
              _KaraokeUnit(
                old.range,
                old.bounds.expandToInclude(bounds),
                fragment,
              ),
            );
            continue;
          }
          units.add(
            _KaraokeUnit(
              _KaraokePaintRange(start: offsets[i].start, end: offsets[i].end),
              bounds,
              fragment,
            ),
          );
        }
      }
      // The immutable path skips whitespace/positive tracking, but keeps the
      // original shaped masks intact (also for RTL/ligature/native fallbacks).
      final tracking = math.max(0.0, style.letterSpacing ?? 0);
      for (final fragment in fragments) {
        final spans = <({double start, double end})>[];
        for (final box in visibleBoxes) {
          final rect = box.toRect();
          if (_physicalRow(rect) != fragment.row ||
              (!wholeRun && box.direction != fragment.direction) ||
              rect.right <= fragment.bounds.left ||
              rect.left >= fragment.bounds.right) {
            continue;
          }
          final trim = math.min(tracking / 2, rect.width * .45);
          spans.add((start: rect.left + trim, end: rect.right - trim));
        }
        fragment.sweep = KaraokeSweepPath(
          spans.isEmpty
              ? [(start: fragment.bounds.left, end: fragment.bounds.right)]
              : spans,
        );
      }
      final totalWidth = fragments.fold<double>(
        0,
        (sum, f) => sum + f.sweep.length,
      );
      if (totalWidth <= 0) continue; // non-rendering control-only token
      var preceding = 0.0;
      for (final fragment in fragments) {
        // Native shaping needs one intact run, not a texture spanning the
        // original PLUS every translation row. Cache conservative ink padding
        // once; never crop at a glyph advance box or allocate a Rect in paint.
        fragment.layerBounds = fragment.bounds.inflate(overflow);
        fragment.startRatio = preceding / totalWidth;
        preceding += fragment.sweep.length;
        fragment.endRatio = preceding / totalWidth;
      }
      final span = math.max(
        1,
        range.token.end.inMicroseconds - range.token.start.inMicroseconds,
      );
      for (final fragment in fragments) {
        fragment.feather = karaokeSweepFeather(
          width: fragment.sweep.length,
          durationUs: (span * (fragment.endRatio - fragment.startRatio))
              .round(),
          baseline: feather,
        );
      }
      // 9-bit atlas IDs reserve three groups. Pathological long lines must
      // fall back rather than wrapping IDs and losing/borrowing another glyph.
      final nativeRun =
          nativeColor || complex || unitCount + units.length > 509;
      for (var i = 0; i < units.length; i++) {
        final unit = units[i];
        unit.layerBounds = unit.bounds.inflate(overflow);
        unit.inkId = nativeRun ? 511 : unitCount + i;
        final trim = math.min(tracking / 2, unit.bounds.width * .45);
        unit.sweep = KaraokeSweepPath([
          (start: unit.bounds.left + trim, end: unit.bounds.right - trim),
        ]);
        if (synthetic) {
          final f = unit.fragment;
          final before = f.sweep.distanceBefore(unit.bounds.left + trim);
          final after = f.sweep.distanceBefore(unit.bounds.right - trim);
          final within = f.direction == TextDirection.rtl
              ? f.sweep.length - after
              : before;
          final startRatio =
              f.startRatio +
              (f.endRatio - f.startRatio) * within / f.sweep.length;
          final endRatio = startRatio + (after - before) / totalWidth;
          final start =
              range.token.start.inMicroseconds + (span * startRatio).round();
          unit.timing = KaraokeGlyphTiming(
            sourceTokenStartUs: range.token.start.inMicroseconds,
            sourceTokenEndUs: range.token.end.inMicroseconds,
            visualTokenStartUs: range.token.start.inMicroseconds,
            highlightStartUs: start,
            highlightEndUs:
                range.token.start.inMicroseconds + (span * endRatio).round(),
            liftStartUs: start,
            estimatedCadenceUs: math.max(
              1,
              (span * (endRatio - startRatio)).round(),
            ),
          );
        } else {
          unit.timing = KaraokeGlyphTiming.fromToken(
            sourceTokenStartUs: range.token.start.inMicroseconds,
            sourceTokenEndUs: range.token.end.inMicroseconds,
            visualTokenStartUs: karaokeVisualTokenStart(
              range.token,
            ).inMicroseconds,
            highlightStartProgress: karaokeGlyphHighlightStart(i, units.length),
            highlightWindowProgress: units.length <= 1
                ? 1
                : math.min(.48, 1.8 / (units.length + .8)),
            estimatedCadenceUs: span / units.length,
          );
        }
      }
      var bounds = wholeBoxes.first.toRect();
      for (final box in wholeBoxes.skip(1)) {
        bounds = bounds.expandToInclude(box.toRect());
      }
      final token =
          _KaraokePaintToken(range, units, fragments, bounds.inflate(overflow))
            ..firstUnit = unitCount
            ..nativeShaping = nativeRun
            ..visualStartUs = synthetic
                ? range.token.start.inMicroseconds
                : karaokeVisualTokenStart(range.token).inMicroseconds;
      token.spanUs = math.max(
        1,
        range.token.end.inMicroseconds - token.visualStartUs,
      );
      unitCount += units.length;
      tokens.add(token);
      // Own a shaped vector fallback before this cache can become visible.
      // Cold rows must sweep too; no token mask is constructed during paint.
      _prepareNativeToken(token);
      drawable.add(range);
    }
    if (synthetic) _buildSyntheticRelays();
    _buildFollowerTimeline();
    final untouched = <_KaraokePaintRange>[];
    var cursor = 0;
    for (final range in drawable) {
      if (range.start > cursor) {
        untouched.add(_KaraokePaintRange(start: cursor, end: range.start));
      }
      cursor = math.max(cursor, range.end);
    }
    if (cursor < originalEnd) {
      untouched.add(_KaraokePaintRange(start: cursor, end: originalEnd));
    }
    originalMask = _recordOwnedMask(untouched);
    primaryMask = _recordOwnedMask([
      _KaraokePaintRange(start: 0, end: originalEnd),
    ]);
    final firstStarts = List<int>.filled(tokens.length, 0);
    for (var i = 0; i < tokens.length; i++) {
      var first = tokens[i].visualStartUs;
      for (final unit in tokens[i].units) {
        first = math.min(
          first,
          math.min(unit.timing.liftStartUs, unit.timing.highlightStartUs),
        );
      }
      firstStarts[i] = first;
    }
    firstMotionUs = firstStarts.isEmpty
        ? 0x7fffffffffffffff
        : firstStarts.reduce(math.min);
    // Linear scalar metadata only; no quadratic set of suffix Pictures.
    restSuffixStartUs = Int64List(tokens.length);
    var earliest = 0x7fffffffffffffff;
    for (var i = tokens.length - 1; i >= 0; i--) {
      earliest = math.min(earliest, firstStarts[i]);
      restSuffixStartUs[i] = earliest;
    }
    drawOriginal = untouched.any(
      (r) => text.substring(r.start, r.end).trim().isNotEmpty,
    );
    drawTranslation =
        originalEnd < text.length &&
        text.substring(originalEnd + 1).trim().isNotEmpty;
    _primaryNative = _needsNativeCoverage(text.substring(0, originalEnd));
    _originalNative = untouched.any(
      (r) => _needsNativeCoverage(text.substring(r.start, r.end)),
    );
    _translationNative =
        drawTranslation &&
        _needsNativeCoverage(text.substring(originalEnd + 1));
    translationMask = _recordOwnedMask(
      originalEnd < text.length
          ? [_KaraokePaintRange(start: originalEnd + 1, end: text.length)]
          : const [],
    );
    _originalInkId = 509;
    _translationInkId = 510;
    final inkRanges = <({_KaraokePaintRange range, int id})>[];
    for (final token in tokens) {
      for (final unit in token.units) {
        final row = _textLines[unit.fragment.row];
        inkRanges.add((
          range: _KaraokePaintRange(
            start: math.max(unit.range.start, row.start),
            end: math.min(unit.range.end, row.end),
          ),
          id: unit.inkId,
        ));
      }
    }
    for (final range in untouched) {
      inkRanges.add((range: range, id: _originalInkId));
    }
    if (drawTranslation) {
      inkRanges.add((
        range: _KaraokePaintRange(start: originalEnd + 1, end: text.length),
        id: _translationInkId,
      ));
    }
    inkRanges.sort((a, b) => a.range.start.compareTo(b.range.start));
    final taggedSpans = <InlineSpan>[];
    var taggedCursor = 0;
    for (final entry in inkRanges) {
      if (entry.range.end <= entry.range.start) continue;
      if (entry.range.start > taggedCursor) {
        taggedSpans.add(
          TextSpan(text: text.substring(taggedCursor, entry.range.start)),
        );
      }
      final id = entry.id;
      taggedSpans.add(
        TextSpan(
          text: text.substring(entry.range.start, entry.range.end),
          style: TextStyle(
            color: Color.fromARGB(
              255,
              28 + (id & 7) * 28,
              28 + ((id >> 3) & 7) * 28,
              28 + ((id >> 6) & 7) * 28,
            ),
          ),
        ),
      );
      taggedCursor = entry.range.end;
    }
    if (taggedCursor < text.length) {
      taggedSpans.add(TextSpan(text: text.substring(taggedCursor)));
    }
    final tagged = _layout(
      TextSpan(
        style: _maskStyle.copyWith(color: Colors.transparent),
        children: taggedSpans,
      ),
    );
    // Colour runs must keep the same shaped geometry. Joining scripts and
    // ligatures already remain whole runs above; colours never set font metrics.
    assert((tagged.height - height).abs() < .01);
    final inkRecorder = ui.PictureRecorder();
    tagged.paint(Canvas(inkRecorder), Offset.zero);
    _inkMask = inkRecorder.endRecording();
    tagged.dispose();
    assert(() {
      debugKaraokeLivePictureCount++;
      return true;
    }());
    layout.dispose();
    lifts = Float64List(unitCount);
    highlights = Float64List(unitCount);
    fragmentPhases = Float64List(fragmentCount);
    fragmentFronts = Float64List(fragmentCount);
  }

  final String text;
  final List<_KaraokeTokenRange> ranges;
  final bool synthetic;
  final List<_KaraokeSweepRelay> sweepRelays = [];
  final double width;
  final TextStyle style;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final Locale? locale;
  final double pixelRatio;
  late final double _imageScale;
  late final List<ui.LineMetrics> _lines;
  late final List<TextRange> _textLines;
  late final int _originalInkId;
  late final int _translationInkId;
  late final ui.Picture _inkMask;
  ui.FragmentShader? _primaryShader;
  ui.FragmentShader? _originalShader;
  ui.FragmentShader? _translationShader;
  late final bool _primaryNative, _originalNative, _translationNative;
  _KaraokeNativeInk? _originalNativeInk, _translationNativeInk;
  int _nativePixels = 0, _nativeImageCount = 0;
  bool _ready = false;
  final Paint _inkPaint = Paint();
  ui.Image? _image;
  ui.Image? _coverageImage;
  bool _disposed = false;
  bool _rasterNeeded() => !_disposed;
  Future<void>? _imageFuture;
  final List<_KaraokePaintToken> tokens = [];
  late final double height;
  late final double lineHeight;
  late final double feather;
  late final double liftHeight;
  late final Rect fullBounds;
  late final ui.Picture originalMask;
  late final ui.Picture primaryMask;
  late final int firstMotionUs;
  Int64List restSuffixStartUs = Int64List(0);
  final restSuffixMasks = <ui.Picture>[];
  late final ui.Picture translationMask;
  late final bool drawOriginal;
  late final bool drawTranslation;
  late final ui.Picture _baseMask;
  late final Float64List lifts;
  late final Float64List highlights;
  late final KaraokeFollowerTimeline followerTimeline;

  void _buildFollowerTimeline() {
    final glyphs = <KaraokeFollowerGlyph>[];
    _KaraokeUnit? previous;
    var previousDrawable = false;
    var previousCompact = false;
    var previousWord = false;
    var chain = 0;
    for (final token in tokens) {
      for (final unit in token.units) {
        final unitText = text.substring(unit.range.start, unit.range.end);
        final drawable = unitText.trim().isNotEmpty;
        final compact = karaokeHasCompactFollowerScript(unitText);
        final word = karaokeHasWordFollowerScript(unitText);
        final before = previous;
        // One ordinary Latin word separator carries movement, not blank ink
        // or highlight time. Layout-only string checks; no new frame work.
        final wordBoundary =
            before != null &&
            previousWord &&
            word &&
            unit.range.start == before.range.end + 1 &&
            const [' ', '\u00a0', '\u202f'].contains(text[before.range.end]) &&
            karaokeDefaultMotion.maxWordFollowerGap > Duration.zero;
        final connected =
            before != null &&
            drawable &&
            previousDrawable &&
            (before.range.end == unit.range.start || wordBoundary) &&
            before.fragment.row == unit.fragment.row &&
            before.fragment.direction == unit.fragment.direction &&
            karaokeFollowerTimingConnected(
              before.timing,
              unit.timing,
              karaokeDefaultMotion,
              compactScript: previousCompact && compact,
              wordBoundary: wordBoundary,
            );
        if (!connected) chain++;
        glyphs.add(KaraokeFollowerGlyph(timing: unit.timing, chain: chain));
        previous = unit;
        previousDrawable = drawable;
        previousCompact = compact;
        previousWord = word;
      }
    }
    followerTimeline = KaraokeFollowerTimeline(glyphs, karaokeDefaultMotion);
  }

  void _buildSyntheticRelays() {
    final group = <_KaraokeFragment>[];
    final segments = <({int startUs, int endUs, double advance})>[];
    void flush() {
      if (group.isEmpty) return;
      final relay = _KaraokeSweepRelay(
        KaraokeSweepPath(group.expand((fragment) => fragment.sweep.spans)),
        KaraokeSweepTimeline(segments),
        group.first.direction == TextDirection.rtl,
        karaokeSweepFeather(
          width: segments.fold<double>(0, (sum, s) => sum + s.advance),
          durationUs: segments.last.endUs - segments.first.startUs,
          baseline: feather,
        ),
      );
      sweepRelays.add(relay);
      for (final fragment in group) {
        fragment.relay = relay;
        fragment.feather = relay.feather;
      }
      group.clear();
      segments.clear();
    }

    for (final token in tokens) {
      final start = token.range.token.start.inMicroseconds;
      final span = token.range.token.end.inMicroseconds - start;
      for (final fragment in token.fragments) {
        final startUs = start + (span * fragment.startRatio).round();
        final endUs = start + (span * fragment.endRatio).round();
        if (endUs <= startUs) {
          flush();
          continue;
        }
        if (group.isNotEmpty &&
            (fragment.row != group.last.row ||
                fragment.direction != group.last.direction ||
                startUs != segments.last.endUs)) {
          flush(); // Wraps/direction changes/actual gaps never share a front.
        }
        group.add(fragment);
        segments.add((
          startUs: startUs,
          endUs: endUs,
          advance: fragment.sweep.length,
        ));
      }
    }
    flush();
  }

  late final Float64List fragmentPhases;
  late final Float64List fragmentFronts;

  TextStyle get _maskStyle => style.copyWith(
    color: Colors.white,
    shadows: null,
    decoration: TextDecoration.none,
  );

  bool matches(
    double newWidth,
    TextStyle newStyle,
    TextAlign alignment,
    TextDirection direction,
    TextScaler scaler,
    Locale? newLocale, [
    double newPixelRatio = 1,
  ]) =>
      // Division used by pre-layout and multiplication used by fractional
      // render constraints can differ by a few floating-point ULPs.
      (width - newWidth).abs() < 1e-6 &&
      style.compareTo(newStyle) != RenderComparison.layout &&
      textAlign == alignment &&
      textDirection == direction &&
      textScaler == scaler &&
      locale == newLocale &&
      pixelRatio == newPixelRatio;

  int _physicalRow(Rect bounds) {
    var nearest = 0;
    var distance = double.infinity;
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      final center = line.baseline + (line.descent - line.ascent) / 2;
      final delta = (bounds.center.dy - center).abs();
      if (delta < distance) {
        nearest = i;
        distance = delta;
      }
    }
    return nearest;
  }

  /// Requested only by active/near-next rows, outside paint. An async raster
  /// never blocks layout. Pending stale results are disposed, not adopted.
  Future<void> prepareImage() => _imageFuture ??= _enqueueRaster();
  Future<void> _enqueueRaster() async {
    final previous = _karaokeRasterTail;
    final done = Completer<void>();
    _karaokeRasterTail = done.future;
    if (previous != null) await previous;
    try {
      if (!_disposed) await _rasterize();
    } finally {
      if (identical(_karaokeRasterTail, done.future)) _karaokeRasterTail = null;
      done.complete();
    }
  }

  Future<ui.Image?> _idleRasterImage(ui.Picture picture, int w, int h) =>
      InteractionPerformanceController.instance.runIdleResource<ui.Image>(
        () => picture.toImage(w, h),
        priority: InteractionWorkPriority.currentVisual,
        isStillNeeded: _rasterNeeded,
      );
  bool get imageReady => _ready;
  int get imageBytes =>
      (_image?.width ?? 0) * (_image?.height ?? 0) * 8 + _nativePixels * 4;
  bool _needsNativeCoverage(String value) =>
      _karaokeJoinedRun.hasMatch(value) || _karaokeColorGlyph.hasMatch(value);

  // At most 16 additional images / 2MiB, alongside the existing <=4MiB atlas.
  // Native runs never use RGB ownership decoding. Raster once outside paint,
  // preserving the full shaped run and original white coverage. If budgeting
  // would undersample too far, retain the exact vector-Picture fallback.
  Future<_KaraokeNativeInk?> _prepareNativeInk(
    ui.Picture mask,
    Rect bounds,
    ui.FragmentProgram program,
  ) async {
    final budget = 524288 - _nativePixels;
    if (_disposed || _nativeImageCount >= 16 || budget < 1024) return null;
    final requested = pixelRatio.clamp(1.0, 4.0);
    final scale = math.min(
      requested,
      math.min(
        4096 / bounds.longestSide,
        math.sqrt(budget / (bounds.width * bounds.height)),
      ),
    );
    if (scale < requested * .66) return null;
    final rasterBounds = Rect.fromLTRB(
      (bounds.left * scale).floor() / scale,
      (bounds.top * scale).floor() / scale,
      (bounds.right * scale).ceil() / scale,
      (bounds.bottom * scale).ceil() / scale,
    );
    final w = (rasterBounds.width * scale).round(),
        h = (rasterBounds.height * scale).round();
    if (w * h > budget) return null;
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..scale(scale)
      ..translate(-rasterBounds.left, -rasterBounds.top)
      ..drawPicture(mask);
    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await _idleRasterImage(picture, w, h);
      if (image == null) return null;
      if (_disposed) {
        image.dispose();
        return null;
      }
      final shader = program.fragmentShader()
        ..setFloat(0, rasterBounds.left)
        ..setFloat(1, rasterBounds.top)
        ..setFloat(2, image.width.toDouble())
        ..setFloat(3, image.height.toDouble())
        ..setFloat(4, scale)
        ..setFloat(5, -2)
        ..setFloat(6, -1)
        ..setImageSampler(0, image)
        ..setImageSampler(1, image);
      _nativePixels += w * h;
      _nativeImageCount++;
      return _KaraokeNativeInk(image, shader);
    } catch (_) {
      image?.dispose();
      return null;
    } finally {
      picture.dispose();
    }
  }

  Future<void> _rasterize() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..scale(_imageScale)
      ..translate(-fullBounds.left, -fullBounds.top)
      ..drawPicture(_inkMask);
    final picture = recorder.endRecording();
    final coverageRecorder = ui.PictureRecorder();
    Canvas(coverageRecorder)
      ..scale(_imageScale)
      ..translate(-fullBounds.left, -fullBounds.top)
      ..drawPicture(_baseMask);
    final coveragePicture = coverageRecorder.endRecording();
    ui.Image? image;
    ui.Image? coverage;
    try {
      image = await _idleRasterImage(
        picture,
        (fullBounds.width * _imageScale).ceil(),
        (fullBounds.height * _imageScale).ceil(),
      );
      if (image == null) return;
      coverage = await _idleRasterImage(
        coveragePicture,
        image.width,
        image.height,
      );
      if (coverage == null) {
        image.dispose();
        return;
      }
      if (_disposed) {
        image.dispose();
        coverage.dispose();
        return;
      }
      final program = await InteractionPerformanceController.instance
          .runIdleResource<ui.FragmentProgram>(
            _loadKaraokeInkProgram,
            priority: InteractionWorkPriority.currentVisual,
            isStillNeeded: _rasterNeeded,
          );
      if (_disposed || program == null) {
        image.dispose();
        coverage.dispose();
        return;
      }
      _image = image;
      _coverageImage = coverage;
      if (!await _prepareShaders(program, image)) return;
      if (_originalNative && drawOriginal) {
        _originalNativeInk = await _prepareNativeInk(
          originalMask,
          fullBounds,
          program,
        );
      }
      if (_translationNative) {
        _translationNativeInk = await _prepareNativeInk(
          translationMask,
          fullBounds,
          program,
        );
      }
      for (final token in tokens) {
        if (!token.nativeShaping) continue;
        for (final fragment in token.fragments) {
          if (_disposed) return;
          fragment.nativeInk = await _prepareNativeInk(
            fragment.mask!,
            fragment.layerBounds,
            program,
          );
        }
      }
      if (_disposed) return;
      for (final token in tokens) {
        if (token.nativeShaping) continue;
        for (final fragment in token.fragments) {
          fragment.mask?.dispose();
          fragment.mask = null;
          assert(() {
            debugKaraokeLivePictureCount--;
            return true;
          }());
        }
      }
      _ready = true;
      notifyListeners();
    } catch (error) {
      if (_image == null) {
        image?.dispose();
        coverage?.dispose();
      }
      // A bounded Picture fallback remains usable on raster/OOM failures.
      if (kDebugMode) debugPrint('Karaoke image fallback: $error');
      if (!_disposed) {
        // The shaped vector masks remain usable without waiting for a retry.
        notifyListeners();
      }
    } finally {
      picture.dispose();
      coveragePicture.dispose();
    }
  }

  Future<bool> _prepareShaders(
    ui.FragmentProgram program,
    ui.Image image,
  ) async {
    final controller = InteractionPerformanceController.instance;
    var lease = await controller.acquireIdleWork(
      priority: InteractionWorkPriority.currentVisual,
      isStillNeeded: _rasterNeeded,
    );
    final budget = Stopwatch()..start();
    try {
      if (!lease.isGranted || _disposed) return false;
      _primaryShader = _makeShader(program, image, -1);
      _originalShader = _makeShader(program, image, _originalInkId.toDouble());
      _translationShader = _makeShader(
        program,
        image,
        _translationInkId.toDouble(),
      );
      var count = 0;
      for (final token in tokens) {
        if (token.nativeShaping) continue;
        for (final unit in token.units) {
          if (count >= 32 || budget.elapsedMicroseconds >= 2000) {
            lease.release();
            lease = await controller.acquireIdleWork(
              priority: InteractionWorkPriority.currentVisual,
              isStillNeeded: _rasterNeeded,
            );
            if (!lease.isGranted || _disposed) return false;
            count = 0;
            budget.reset();
          }
          unit.shader = _makeShader(program, image, unit.inkId.toDouble());
          count++;
        }
      }
      return true;
    } finally {
      lease.release();
    }
  }

  ui.FragmentShader _makeShader(
    ui.FragmentProgram program,
    ui.Image image,
    double id,
  ) {
    final shader = program.fragmentShader()
      ..setFloat(0, fullBounds.left)
      ..setFloat(1, fullBounds.top)
      ..setFloat(2, image.width.toDouble())
      ..setFloat(3, image.height.toDouble())
      ..setFloat(4, _imageScale)
      ..setFloat(5, id)
      ..setFloat(6, _translationInkId.toDouble())
      ..setImageSampler(0, image)
      ..setImageSampler(1, _coverageImage!);
    return shader;
  }

  ui.Picture _recordOwnedMask(List<_KaraokePaintRange> ranges) {
    if (ranges.length == 1 &&
        ranges.first.start == 0 &&
        ranges.first.end == text.length) {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawPicture(_baseMask);
      assert(() {
        debugKaraokeLivePictureCount++;
        return true;
      }());
      return recorder.endRecording();
    }
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final range in ranges) {
      if (range.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, range.start)));
      }
      if (range.end > range.start) {
        spans.add(
          TextSpan(
            text: text.substring(range.start, range.end),
            style: const TextStyle(color: Colors.white),
          ),
        );
      }
      cursor = range.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    final selected = _layout(
      TextSpan(
        style: _maskStyle.copyWith(color: Colors.transparent),
        children: spans,
      ),
    );
    final recorder = ui.PictureRecorder();
    selected.paint(Canvas(recorder), Offset.zero);
    selected.dispose();
    assert(() {
      debugKaraokeLivePictureCount++;
      return true;
    }());
    return recorder.endRecording();
  }

  void _prepareNativeToken(_KaraokePaintToken token) {
    for (final fragment in token.fragments) {
      if (fragment.mask != null) continue;
      final line = _textLines[fragment.row];
      fragment.mask = _recordOwnedMask([
        _KaraokePaintRange(
          start: math.max(token.range.start, line.start),
          end: math.min(token.range.end, line.end),
        ),
      ]);
    }
  }

  TextPainter _layout(InlineSpan span) {
    assert(() {
      debugKaraokeTextLayoutCount++;
      return true;
    }());
    return TextPainter(
      text: span,
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
    )..layout(maxWidth: width);
  }

  List<ui.TextBox> _boxes(TextPainter layout, _KaraokePaintRange range) =>
      layout
          .getBoxesForSelection(
            TextSelection(baseOffset: range.start, extentOffset: range.end),
          )
          .where((b) => b.right > b.left && b.bottom > b.top)
          .toList();

  @override
  void dispose() {
    _disposed = true;
    InteractionPerformanceController.instance.cancelIdleWork(_rasterNeeded);
    _ready = false;
    _primaryShader?.dispose();
    _originalShader?.dispose();
    _translationShader?.dispose();
    _image?.dispose();
    _coverageImage?.dispose();
    _originalNativeInk?.dispose();
    _translationNativeInk?.dispose();
    _nativePixels = 0;
    _image = null;
    var count = 5;
    originalMask.dispose();
    primaryMask.dispose();
    translationMask.dispose();
    for (final mask in restSuffixMasks) {
      mask.dispose();
      count++;
    }
    for (final token in tokens) {
      for (final fragment in token.fragments) {
        fragment.nativeInk?.dispose();
        if (fragment.mask case final mask?) {
          mask.dispose();
          count++;
        }
      }
      for (final unit in token.units) {
        unit.shader?.dispose();
      }
    }
    _inkMask.dispose();
    _baseMask.dispose();
    assert(() {
      debugKaraokeLivePictureCount -= count;
      return true;
    }());
    super.dispose();
  }

  void _solid(
    Canvas canvas,
    ui.Picture mask,
    Rect bounds,
    double lift,
    Paint layer,
  ) {
    assert(() {
      debugKaraokeSolidLayerCount++;
      return true;
    }());
    canvas.save();
    canvas.translate(0, lift);
    canvas.saveLayer(bounds, layer);
    canvas.drawPicture(mask);
    canvas.restore();
    canvas.restore();
  }

  void _ink(
    Canvas canvas,
    ui.FragmentShader shader,
    Rect bounds,
    double lift,
    Color active,
    Color inactive,
    double front,
    double direction,
    double strength, {
    double? featherWidth,
  }) {
    shader
      ..setFloat(7, front)
      ..setFloat(8, featherWidth ?? feather)
      ..setFloat(9, direction)
      ..setFloat(10, strength)
      ..setFloat(11, active.r * active.a)
      ..setFloat(12, active.g * active.a)
      ..setFloat(13, active.b * active.a)
      ..setFloat(14, active.a)
      ..setFloat(15, inactive.r * inactive.a)
      ..setFloat(16, inactive.g * inactive.a)
      ..setFloat(17, inactive.b * inactive.a)
      ..setFloat(18, inactive.a);
    _inkPaint.shader = shader;
    canvas.save();
    canvas.translate(0, lift);
    canvas.drawRect(bounds, _inkPaint);
    canvas.restore();
  }

  // Test-only pixel oracle: the same shader and owned ink used by animation.
  void debugPaintOwnedGlyph(Canvas canvas, int index) {
    assert(kDebugMode);
    for (final token in tokens) {
      for (final unit in token.units) {
        if (unit.inkId == index) {
          _ink(
            canvas,
            unit.shader!,
            unit.layerBounds,
            0,
            Colors.white,
            Colors.white,
            0,
            1,
            0,
          );
          return;
        }
      }
    }
  }

  /// Cached unit geometry + scalar arithmetic only. There is no layout,
  /// selection query, lazy mask creation, list/map/record, Paint/Rect/Offset or
  /// gradient construction here. Native canvas recording still has its own
  /// costs; this is not a claim of zero engine/GPU allocation.
  void paint(
    Canvas canvas,
    int mediaUs,
    double retention,
    _KaraokePaintStyle colors, [
    double highlightStrength = 1,
  ]) {
    if (mediaUs <= firstMotionUs) {
      for (var i = 0; i < lifts.length; i++) {
        lifts[i] = 0;
        highlights[i] = 0;
      }
      if (!_primaryNative && _primaryShader != null) {
        _ink(
          canvas,
          _primaryShader!,
          fullBounds,
          0,
          colors.inactive,
          colors.inactive,
          0,
          1,
          0,
        );
      } else {
        _solid(canvas, primaryMask, fullBounds, 0, colors.inactiveLayer);
      }
      if (drawTranslation) {
        _paintTranslation(canvas, colors);
      }
      return;
    }
    followerTimeline.writeOffsets(
      mediaUs,
      lineHeight,
      lifts,
      retention: retention,
    );
    if (drawOriginal) {
      if (_originalNativeInk case final ink?) {
        _ink(
          canvas,
          ink.shader,
          fullBounds,
          0,
          colors.inactive,
          colors.inactive,
          0,
          1,
          0,
        );
      } else if (!_originalNative && _originalShader != null) {
        _ink(
          canvas,
          _originalShader!,
          fullBounds,
          0,
          colors.inactive,
          colors.inactive,
          0,
          1,
          0,
        );
      } else {
        _solid(canvas, originalMask, fullBounds, 0, colors.inactiveLayer);
      }
    }
    if (drawTranslation) {
      _paintTranslation(canvas, colors);
    }
    for (var r = 0; r < sweepRelays.length; r++) {
      final relay = sweepRelays[r];
      relay.phase = relay.timeline.phaseAt(mediaUs);
      relay.front = relay.path.frontAt(
        relay.phase,
        relay.feather,
        rtl: relay.rtl,
      );
    }
    for (var t = 0; t < tokens.length; t++) {
      final token = tokens[t];
      final progress = ((mediaUs - token.visualStartUs) / token.spanUs).clamp(
        0.0,
        1.0,
      );
      for (var u = 0; u < token.units.length; u++) {
        final index = token.firstUnit + u;
        final timing = token.units[u].timing;
        highlights[index] = karaokeGlyphHighlightAt(mediaUs, timing);
      }
      if (synthetic || !_ready || token.nativeShaping) {
        for (var f = 0; f < token.fragments.length; f++) {
          final fragment = token.fragments[f];
          final phase =
              ((progress - fragment.startRatio) /
                      (fragment.endRatio - fragment.startRatio))
                  .clamp(0.0, 1.0);
          fragmentPhases[fragment.index] = fragment.relay?.phase ?? phase;
          fragmentFronts[fragment.index] =
              fragment.relay?.front ??
              fragment.sweep.frontAt(
                phase,
                fragment.feather,
                rtl: fragment.direction == TextDirection.rtl,
              );
        }
      }
      if (!_ready || token.nativeShaping) {
        // Before the bounded atlas is ready (or on a shader/raster failure),
        // keep complete shaped word fragments. Never cut glyph ink into boxes.
        // Timed sweeps continue; only micro-lift degrades to a word-level pose.
        final lift = lifts[token.firstUnit];
        for (final fragment in token.fragments) {
          final feather = fragment.feather;
          final phase = fragmentPhases[fragment.index];
          var front = fragmentFronts[fragment.index];
          if (phase >= 1) {
            front = fragment.direction == TextDirection.rtl
                ? fullBounds.left - feather
                : fullBounds.right + feather;
          }
          if (fragment.nativeInk case final ink?) {
            if (phase <= 0) {
              front = fragment.direction == TextDirection.rtl
                  ? fullBounds.right + feather
                  : fullBounds.left - feather;
            }
            _ink(
              canvas,
              ink.shader,
              fragment.layerBounds,
              lift,
              colors.active,
              colors.inactive,
              front,
              fragment.direction == TextDirection.rtl ? -1 : 1,
              highlightStrength,
              featherWidth: feather,
            );
          } else if (phase <= 0 || highlightStrength <= 0) {
            _solid(
              canvas,
              fragment.mask!,
              fragment.layerBounds,
              lift,
              colors.inactiveLayer,
            );
          } else if (phase >= 1 && highlightStrength >= 1) {
            _solid(
              canvas,
              fragment.mask!,
              fragment.layerBounds,
              lift,
              colors.activeLayer,
            );
          } else {
            assert(() {
              debugKaraokeGradientLayerCount++;
              return true;
            }());
            canvas.save();
            canvas.translate(0, lift);
            canvas.saveLayer(fragment.layerBounds, colors.coverageLayer);
            canvas.drawPicture(fragment.mask!);
            canvas.save();
            final rtl = fragment.direction == TextDirection.rtl;
            canvas.translate(front + (rtl ? feather / 2 : -feather / 2), 0);
            canvas.scale(rtl ? -feather : feather, 1);
            canvas.drawPaint(colors.gradientForStrength(highlightStrength));
            canvas.restore();
            canvas.restore();
            canvas.restore();
          }
        }
        continue;
      }
      for (var u = 0; u < token.units.length; u++) {
        final unit = token.units[u];
        final index = token.firstUnit + u;
        final rtl = unit.fragment.direction == TextDirection.rtl;
        final feather = unit.fragment.feather;
        var phase = highlights[index];
        var front = unit.sweep.frontAt(phase, feather, rtl: rtl);
        if (synthetic) {
          phase = fragmentPhases[unit.fragment.index];
          front = fragmentFronts[unit.fragment.index];
          if (phase > 0 && phase < 1) {
            if ((!rtl && front - feather / 2 >= unit.bounds.right) ||
                (rtl && front + feather / 2 <= unit.bounds.left)) {
              phase = 1;
            }
            if ((!rtl && front + feather / 2 <= unit.bounds.left) ||
                (rtl && front - feather / 2 >= unit.bounds.right)) {
              phase = 0;
            }
          }
        }
        // Selection advance is not an ink bound: completed glyph overhangs
        // must be fully active too, rather than remaining inside the feather.
        if (phase >= 1) {
          front = rtl ? fullBounds.left - feather : fullBounds.right + feather;
        } else if (phase <= 0) {
          front = rtl ? fullBounds.right + feather : fullBounds.left - feather;
        }
        _ink(
          canvas,
          unit.shader!,
          unit.layerBounds,
          lifts[index],
          colors.active,
          colors.inactive,
          front,
          rtl ? -1 : 1,
          highlightStrength,
          featherWidth: feather,
        );
      }
    }
  }

  void _paintTranslation(Canvas canvas, _KaraokePaintStyle colors) {
    if (_translationNativeInk case final ink?) {
      _ink(
        canvas,
        ink.shader,
        fullBounds,
        0,
        colors.translation,
        colors.translation,
        0,
        1,
        0,
      );
    } else if (!_translationNative && _translationShader != null) {
      _ink(
        canvas,
        _translationShader!,
        fullBounds,
        0,
        colors.translation,
        colors.translation,
        0,
        1,
        0,
      );
    } else {
      _solid(canvas, translationMask, fullBounds, 0, colors.translationLayer);
    }
  }
}

class _SinglePassKaraokePainter extends CustomPainter {
  _SinglePassKaraokePainter({
    required this.cache,
    required this.colors,
    required this.positionListenable,
    required this.exitAnimation,
    required this.isExiting,
    required this.entryAnimation,
    required this.exitStartStrength,
  }) : super(
         repaint: Listenable.merge([
           positionListenable,
           exitAnimation,
           entryAnimation,
           cache,
         ]),
       );
  final _KaraokePaintCache cache;
  final _KaraokePaintStyle colors;
  final ValueListenable<Duration> positionListenable;
  final Animation<double> exitAnimation;
  final bool isExiting;
  final Animation<double> entryAnimation;
  final double exitStartStrength;
  double get highlightStrength => isExiting
      ? exitStartStrength * karaokeExitRetentionFraction(exitAnimation.value)
      : Curves.easeOutCubic.transform(entryAnimation.value);

  @override
  void paint(Canvas canvas, Size size) => cache.paint(
    canvas,
    positionListenable.value.inMicroseconds,
    isExiting
        ? karaokeExitRetentionFraction(exitAnimation.value)
        : Curves.easeOutCubic.transform(entryAnimation.value),
    colors,
    highlightStrength,
  );

  @override
  bool shouldRepaint(covariant _SinglePassKaraokePainter old) =>
      cache != old.cache ||
      colors != old.colors ||
      isExiting != old.isExiting ||
      positionListenable != old.positionListenable ||
      exitAnimation != old.exitAnimation ||
      entryAnimation != old.entryAnimation ||
      exitStartStrength != old.exitStartStrength;
}
