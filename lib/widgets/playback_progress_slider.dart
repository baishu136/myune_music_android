import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Keep the Material slider, gestures and semantics. Ignore position changes
/// smaller than a quarter physical pixel; the audio/lyric clocks stay exact.
class PlaybackProgressSlider extends StatefulWidget {
  const PlaybackProgressSlider({
    super.key,
    required this.position,
    required this.preview,
    required this.totalMs,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
  });
  final ValueListenable<Duration> position;
  final ValueListenable<double?> preview;
  final double totalMs;
  final ValueChanged<double> onStart, onChanged, onEnd;
  @override
  State<PlaybackProgressSlider> createState() => _PlaybackProgressSliderState();
}

class _PlaybackProgressSliderState extends State<PlaybackProgressSlider>
    with WidgetsBindingObserver {
  double _shown = 0, _threshold = 0;
  bool _bound = false, _visible = true, _foreground = true;
  double get _maximum => widget.totalMs > 0 ? widget.totalMs : 1;
  double _read() =>
      (widget.preview.value ?? widget.position.value.inMilliseconds.toDouble())
          .clamp(0, _maximum);
  void _changed() {
    final next = _read();
    if (next == _shown) return;
    if (widget.preview.value == null &&
        next > 0 &&
        next < _maximum &&
        (next - _shown).abs() < _threshold) {
      return;
    }
    setState(() => _shown = next);
  }

  void _sync() {
    final enabled = _visible && _foreground;
    if (enabled == _bound) return;
    _bound = enabled;
    if (enabled) {
      _shown = _read();
      widget.position.addListener(_changed);
      widget.preview.addListener(_changed);
    } else {
      widget.position.removeListener(_changed);
      widget.preview.removeListener(_changed);
    }
  }

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _shown = _read();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    _sync();
    _shown = _read();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
    if (_bound && mounted) setState(() => _shown = _read());
  }

  @override
  void didUpdateWidget(PlaybackProgressSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_bound) {
      oldWidget.position.removeListener(_changed);
      oldWidget.preview.removeListener(_changed);
      _bound = false;
    }
    _shown = _read();
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_bound) {
      widget.position.removeListener(_changed);
      widget.preview.removeListener(_changed);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final pixels =
          (constraints.maxWidth - 48).clamp(1.0, double.infinity) *
          MediaQuery.devicePixelRatioOf(context);
      _threshold = _maximum / (pixels * 4);
      return RepaintBoundary(
        child: Slider(
          value: _shown.clamp(0, _maximum),
          max: _maximum,
          onChangeStart: widget.onStart,
          onChanged: widget.onChanged,
          onChangeEnd: widget.onEnd,
        ),
      );
    },
  );
}
