import 'package:flutter/material.dart';

final _nativeColorGlyph = RegExp(
  r'[\u00a9\u00ae\u200d\u20e3\u2600-\u27ff\ufe0f\u{1f000}-\u{1faff}]',
  unicode: true,
);

/// Reuse native RGB foreground ink while focus changes its alpha. The glow
/// remains a separate sibling and keeps its original source-over blending.
class LyricPlainForeground extends StatefulWidget {
  const LyricPlainForeground({
    super.key,
    required this.text,
    required this.textAlign,
  });

  final String text;
  final TextAlign textAlign;

  @override
  State<LyricPlainForeground> createState() => _LyricPlainForegroundState();
}

class _LyricPlainForegroundState extends State<LyricPlainForeground> {
  Color? _opaqueColor;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final color = style.color ?? Colors.white;
    if (style.foreground != null ||
        style.background != null ||
        style.backgroundColor != null ||
        (style.shadows?.isNotEmpty ?? false) ||
        (style.decoration != null && style.decoration != TextDecoration.none) ||
        _nativeColorGlyph.hasMatch(widget.text)) {
      return Text(widget.text, textAlign: widget.textAlign);
    }
    final previous = _opaqueColor;
    // Color.lerp can introduce machine epsilon even when both RGB endpoints
    // are identical. Keep those exact native RGB values, not quantized colors.
    if (previous == null ||
        previous.colorSpace != color.colorSpace ||
        (previous.r - color.r).abs() > 1e-12 ||
        (previous.g - color.g).abs() > 1e-12 ||
        (previous.b - color.b).abs() > 1e-12) {
      _opaqueColor = color.withValues(alpha: 1);
    }
    return Opacity(
      key: const ValueKey('mobile_lyric_foreground_opacity'),
      opacity: color.a,
      child: RepaintBoundary(
        child: Text(
          widget.text,
          textAlign: widget.textAlign,
          style: style.copyWith(
            inherit: false,
            color: _opaqueColor,
            decorationColor: _opaqueColor,
          ),
        ),
      ),
    );
  }
}
