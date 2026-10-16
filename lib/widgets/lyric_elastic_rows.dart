part of 'mobile_lyrics_list.dart';

final _chineseLyric = RegExp(
  r'[\u3400-\u9fff\u{20000}-\u{3134f}]',
  unicode: true,
);
bool _hasChineseLyric(String text) => _chineseLyric.hasMatch(text);

class _LyricElasticFrame extends ChangeNotifier {
  List<LyricElasticSegment> _segments = [
    LyricElasticSegment(amplitude: 0, role: LyricElasticRole.surrounding),
  ];
  List<double> _centres = const [0];
  double _height = 0, _elapsed = 1, _duration = .78;
  Float64List _positions = Float64List(1);
  double _displacement = 0, _font = 20, _viewport = 1, _centre = 0;
  LyricElasticRole _role = LyricElasticRole.surrounding;
  bool get settled => _elapsed >= _duration;
  double offset(int row) =>
      settled ? 0 : _positions[row.clamp(0, _positions.length - 1)];
  void configureRows(List<double> centres, double height) {
    if (_centres.length == centres.length && _height == height) return;
    _centres = centres;
    _height = height;
    _segments = [for (var i = 0; i < centres.length; i++) _make(i, 0, 0)];
    _positions = Float64List(centres.length);
    _sample();
  }

  LyricElasticSegment _make(int row, double value, double velocity) {
    final y = _centre + _centres[row] - _height / 2;
    final edge = ((y / _viewport - .4).abs() / .6).clamp(0.0, 1.0);
    final fraction = _role == LyricElasticRole.surrounding
        ? .16 + .42 * edge * edge
        : _role == LyricElasticRole.departing
        ? .16
        : .12;
    final limit =
        _font *
        switch (_role) {
          LyricElasticRole.surrounding => 1.10,
          LyricElasticRole.departing => .52,
          LyricElasticRole.arriving => .38,
        };
    final amplitude = (_displacement * fraction).clamp(-limit, limit);
    return LyricElasticSegment(
      amplitude: amplitude,
      role: _role,
      initialOffset: value,
      initialVelocity: velocity,
      seconds:
          _duration *
          (.94 -
              .06 *
                  ((_centres[row] - _height / 2) / _viewport).clamp(-1.0, 1.0)),
    );
  }

  void retarget({
    required double displacement,
    required LyricElasticRole role,
    required double fontSize,
    required double viewportHeight,
    required double centre,
    required double lineSeconds,
  }) {
    final previous = _segments, elapsed = _elapsed;
    final wasSettled = settled;
    _displacement = displacement;
    _role = role;
    _font = fontSize;
    _viewport = math.max(1, viewportHeight);
    _centre = centre;
    _duration =
        (.62 +
                .05 * lineSeconds.clamp(.35, 4) +
                .03 * mobileLyricsLargeFontProgress(fontSize))
            .clamp(.66, .86);
    _segments = [
      for (var i = 0; i < _centres.length; i++)
        _make(
          i,
          wasSettled ? 0 : previous[i].value(elapsed),
          wasSettled ? 0 : previous[i].velocity(elapsed),
        ),
    ];
    _elapsed = 0;
    _sample();
    notifyListeners();
  }

  void tick(double time) {
    _elapsed = time;
    _sample();
    notifyListeners();
  }

  void clear() {
    _elapsed = _duration;
    _positions.fillRange(0, _positions.length, 0);
    notifyListeners();
  }

  void _sample() {
    for (var i = 0; i < _positions.length; i++) {
      _positions[i] = settled ? 0 : _segments[i].value(_elapsed);
    }
  }
}

class _LyricElasticScope extends InheritedWidget {
  const _LyricElasticScope({
    required this.frame,
    required this.physical,
    required super.child,
  });
  final _LyricElasticFrame frame;
  final bool physical;
  static _LyricElasticScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LyricElasticScope>();
  @override
  bool updateShouldNotify(_LyricElasticScope old) =>
      frame != old.frame || physical != old.physical;
}

Widget _elasticPlainText(
  BuildContext context,
  TextSpan text,
  TextAlign align, {
  bool cacheForeground = false,
}) {
  final scope = _LyricElasticScope.of(context);
  return scope?.physical == true
      ? _ElasticPlainParagraph(
          text: text,
          textAlign: align,
          frame: scope!.frame,
        )
      : text.children == null && text.style == null
      ? cacheForeground
            ? LyricPlainForeground(text: text.text ?? '', textAlign: align)
            : Text(text.text ?? '', textAlign: align)
      : Text.rich(text, textAlign: align);
}

/// Exact paragraph shaping is cached once. Only physical row Pictures move;
/// no per-glyph widget/layout, raster readback or new ticker. Plain text has
/// one tint layer per paragraph so animated colour never reshapes the masks.
class _PhysicalLyricPictures extends ChangeNotifier {
  _PhysicalLyricPictures(
    TextPainter layout,
    double width, {
    int? translationStart,
    bool splitRows = true,
    this.padding = 32,
    this.maxRasterPixels = 262144,
    this.onReleased,
    this.priorityForWork,
  }) {
    height = layout.height;
    _width = width;
    final metrics = layout.computeLineMetrics();
    centres.addAll(
      metrics.map((line) => line.baseline + (line.descent - line.ascent) / 2),
    );
    // One band for every physical row, including long/wrapped Chinese text.
    // Paragraph shaping is shared; glow rows share one bounded raster atlas.
    final step = splitRows ? 1 : math.max(1, metrics.length);
    for (var i = 0; i < metrics.length; i += step) {
      final end = math.min(metrics.length, i + step);
      final top = i == 0
          ? -padding
          : (metrics[i - 1].baseline +
                    metrics[i - 1].descent +
                    metrics[i].baseline -
                    metrics[i].ascent) /
                2;
      final bottom = end == metrics.length
          ? height + padding
          : (metrics[end - 1].baseline +
                    metrics[end - 1].descent +
                    metrics[end].baseline -
                    metrics[end].ascent) /
                2;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.clipRect(Rect.fromLTRB(-padding, top, width + padding, bottom));
      bands.add(Rect.fromLTRB(-padding, top, width + padding, bottom));
      layout.paint(canvas, Offset.zero);
      pictures.add(recorder.endRecording());
      rowIndices.add(i);
      secondary.add(
        translationStart != null &&
            layout
                    .getPositionForOffset(
                      Offset(width / 2, metrics[i].baseline),
                    )
                    .offset >=
                translationStart,
      );
    }
  }
  late final double height;
  late final double _width;
  final double padding;
  final int maxRasterPixels;
  final VoidCallback? onReleased;
  final InteractionWorkPriority Function()? priorityForWork;
  bool _finished = false, _released = false;
  void _releaseReservation() {
    if (_released) return;
    _released = true;
    onReleased?.call();
  }

  double rasterScale = 1;
  final pictures = <ui.Picture>[];
  final centres = <double>[];
  final rowIndices = <int>[];
  final secondary = <bool>[];
  final bands = <Rect>[];
  final _sources = <Rect>[];
  final Paint rasterPaint = Paint()..filterQuality = FilterQuality.low;
  ui.Image? raster;
  bool _disposed = false, _requested = false;
  bool _needed() => !_disposed;
  void prepareRaster(double pixelRatio) {
    if (_requested || _disposed) return;
    _requested = true;
    final scale = math.min(
      pixelRatio.clamp(1.0, 4.0),
      math.min(
        4096 / math.max(_width + 2 * padding, height + 2 * padding),
        math.sqrt(
          maxRasterPixels / ((_width + 2 * padding) * (height + 2 * padding)),
        ),
      ),
    );
    rasterScale = scale;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(scale)
      ..translate(padding, padding);
    for (final picture in pictures) {
      canvas.drawPicture(picture);
    }
    final picture = recorder.endRecording();
    unawaited(() async {
      try {
        final image = await InteractionPerformanceController.instance
            .runIdleResource<ui.Image>(
              () => picture.toImage(
                ((_width + 2 * padding) * scale).floor().clamp(1, 4096),
                ((height + 2 * padding) * scale).floor().clamp(1, 4096),
              ),
              priority: InteractionWorkPriority.userVisible,
              priorityForWork: priorityForWork,
              allowDuringVisualAnimation: true,
              isStillNeeded: _needed,
            );
        if (_disposed) {
          image?.dispose();
          return;
        }
        if (image == null) return;
        for (final band in bands) {
          _sources.add(
            Rect.fromLTRB(
              (band.left + padding) * scale,
              (band.top + padding) * scale,
              (band.right + padding) * scale,
              (band.bottom + padding) * scale,
            ),
          );
        }
        raster = image;
        notifyListeners();
      } catch (_) {
        /* Retain the vector pictures after raster/OOM failure. */
      } finally {
        picture.dispose();
        _finished = true;
        if (_disposed || raster == null) _releaseReservation();
      }
    }());
  }

  @override
  void dispose() {
    _disposed = true;
    InteractionPerformanceController.instance.cancelIdleWork(_needed);
    raster?.dispose();
    for (final picture in pictures) {
      picture.dispose();
    }
    if (!_requested || _finished) _releaseReservation();
    super.dispose();
  }
}

class _ElasticPlainParagraph extends StatefulWidget {
  const _ElasticPlainParagraph({
    required this.text,
    required this.textAlign,
    required this.frame,
  });
  final TextSpan text;
  final TextAlign textAlign;
  final _LyricElasticFrame frame;
  @override
  State<_ElasticPlainParagraph> createState() => _ElasticPlainParagraphState();
}

class _ElasticPlainParagraphState extends State<_ElasticPlainParagraph> {
  TextPainter? _layout;
  _PhysicalLyricPictures? _pictures;
  Object? _signature;
  @override
  void dispose() {
    _layout?.dispose();
    _pictures?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = DefaultTextStyle.of(context).style;
      final direction = Directionality.of(context);
      final scaler = MediaQuery.textScalerOf(context);
      final locale = Localizations.maybeLocaleOf(context);
      TextSpan mask(TextSpan span) => TextSpan(
        text: span.text,
        style: span.style?.copyWith(color: Colors.white.withValues(alpha: 1)),
        children: span.children
            ?.map((s) => s is TextSpan ? mask(s) : s)
            .toList(),
      );
      final maskStyle = style.copyWith(
        color: Colors.white,
        // Decorations belong to the same white mask; their animated colour
        // must not invalidate paragraph geometry during a focus handoff.
        decorationColor: Colors.white,
      );
      final signature = (
        widget.text,
        maskStyle,
        widget.textAlign,
        direction,
        scaler,
        locale,
        constraints.maxWidth,
      );
      if (_signature != signature) {
        _layout?.dispose();
        _pictures?.dispose();
        _layout = TextPainter(
          text: TextSpan(style: maskStyle, children: [mask(widget.text)]),
          textAlign: widget.textAlign,
          textDirection: direction,
          textScaler: scaler,
          locale: locale,
        )..layout(maxWidth: constraints.maxWidth);
        final translation = widget.text.children?.last;
        _pictures = _PhysicalLyricPictures(
          _layout!,
          constraints.maxWidth,
          translationStart:
              translation is TextSpan && translation.style?.color != null
              ? widget.text.toPlainText().length -
                    translation.toPlainText().length
              : null,
        );
        _signature = signature;
        assert(() {
          debugElasticPhysicalLayoutCount++;
          return true;
        }());
      }
      widget.frame.configureRows(_pictures!.centres, _pictures!.height);
      final translation = widget.text.children?.last;
      final secondaryColor = translation is TextSpan
          ? translation.style?.color
          : null;
      Widget layer(Color color, bool? secondary) => ColorFiltered(
        colorFilter: ColorFilter.mode(color, BlendMode.modulate),
        child: CustomPaint(
          painter: _ElasticPhysicalPainter(
            _pictures!,
            widget.frame,
            secondary: secondary,
          ),
        ),
      );
      return Semantics(
        label: widget.text.toPlainText(),
        child: SizedBox(
          width: constraints.maxWidth,
          height: _layout!.height,
          child: secondaryColor == null
              ? layer(style.color ?? Colors.white, null)
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    layer(style.color ?? Colors.white, false),
                    layer(secondaryColor, true),
                  ],
                ),
        ),
      );
    },
  );
}

int debugElasticPhysicalLayoutCount = 0;

class _ElasticPhysicalPainter extends CustomPainter {
  _ElasticPhysicalPainter(
    this.pictures,
    this.frame, {
    this.center = false,
    this.secondary,
  }) : super(repaint: Listenable.merge([frame, pictures]));
  final _PhysicalLyricPictures pictures;
  final _LyricElasticFrame frame;
  final bool center;
  final bool? secondary;
  @override
  void paint(Canvas canvas, Size size) {
    final y = center ? (size.height - pictures.height) / 2 : 0.0;
    for (var i = 0; i < pictures.pictures.length; i++) {
      if (secondary != null && pictures.secondary[i] != secondary) continue;
      canvas.save();
      canvas.translate(0, y + frame.offset(pictures.rowIndices[i]));
      if (pictures.raster case final image?) {
        canvas.drawImageRect(
          image,
          pictures._sources[i],
          pictures.bands[i],
          pictures.rasterPaint,
        );
      } else {
        canvas.drawPicture(pictures.pictures[i]);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ElasticPhysicalPainter old) =>
      pictures != old.pictures ||
      frame != old.frame ||
      center != old.center ||
      secondary != old.secondary;
}
