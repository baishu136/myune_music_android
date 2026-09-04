import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../theme/theme_provider.dart';
import 'settings_provider.dart';

Color? parseThemeColorHex(String input) {
  var normalized = input.trim();
  if (normalized.startsWith('#')) normalized = normalized.substring(1);
  if (normalized.toLowerCase().startsWith('0x')) {
    normalized = normalized.substring(2);
  }
  if (normalized.length == 3) {
    normalized = normalized.split('').map((digit) => '$digit$digit').join();
  }
  if (normalized.length != 6 ||
      !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)) {
    return null;
  }
  return Color(0xFF000000 | int.parse(normalized, radix: 16));
}

String formatThemeColorHex(Color color) => color
    .toARGB32()
    .toRadixString(16)
    .padLeft(8, '0')
    .substring(2)
    .toUpperCase();

class ThemeSelectionScreen extends StatelessWidget {
  const ThemeSelectionScreen({super.key});

  Future<void> _applyColor(BuildContext context, Color color) async {
    final settings = context.read<SettingsProvider>();
    if (settings.useDynamicColor) await settings.setUseDynamicColor(false);
    if (!context.mounted) return;
    await context.read<ThemeProvider>().setSeedColor(color, isManual: true);
  }

  @override
  Widget build(BuildContext context) {
    final selected = context.watch<ThemeProvider>().lastManualSeedColor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('主题配色', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Container(
                key: const ValueKey('exact-custom-theme-color'),
                width: 58,
                height: 34,
                decoration: BoxDecoration(
                  color: selected,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: '打开自定义取色盘',
                icon: const Icon(Icons.colorize),
                onPressed: () async {
                  final color = await showDialog<Color>(
                    context: context,
                    builder: (_) => AdobeColorPickerDialog(initial: selected),
                  );
                  if (color != null && context.mounted) {
                    await _applyColor(context, color);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: themePresetColors.length,
            itemBuilder: (context, index) {
              final color = themePresetColors[index];
              final isSelected = color.toARGB32() == selected.toARGB32();
              return Semantics(
                button: true,
                label: '主题颜色 ${index + 1}',
                selected: isSelected,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _applyColor(context, color),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.outlineVariant,
                        width: isSelected ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class AdobeColorPickerDialog extends StatefulWidget {
  const AdobeColorPickerDialog({
    super.key,
    required this.initial,
    this.title = '自定义主题颜色',
  });

  final Color initial;
  final String title;

  @override
  State<AdobeColorPickerDialog> createState() => _AdobeColorPickerDialogState();
}

class _AdobeColorPickerDialogState extends State<AdobeColorPickerDialog> {
  late HSVColor _hsv;
  late final TextEditingController _hexController;
  bool _hexInvalid = false;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _hexController = TextEditingController(
      text: formatThemeColorHex(widget.initial),
    );
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _setHsv(HSVColor value, {bool syncHex = true}) {
    setState(() {
      _hsv = value;
      _hexInvalid = false;
    });
    if (!syncHex) return;
    final text = formatThemeColorHex(value.toColor());
    _hexController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _updateFromHex(String value) {
    final color = parseThemeColorHex(value);
    if (color == null) {
      setState(() => _hexInvalid = value.length == 6);
      return;
    }
    _setHsv(HSVColor.fromColor(color), syncHex: false);
  }

  void _updateSaturationValue(Offset point, Size size) {
    _setHsv(
      _hsv
          .withSaturation((point.dx / size.width).clamp(0.0, 1.0))
          .withValue((1 - point.dy / size.height).clamp(0.0, 1.0)),
    );
  }

  void _updateHue(Offset point, Size size) {
    _setHsv(_hsv.withHue((point.dy / size.height * 360).clamp(0.0, 360.0)));
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      content: SizedBox(
        width: 360,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final squareSize = (constraints.maxWidth - 44).clamp(210.0, 300.0);
            final square = Size.square(squareSize);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTapDown: (details) =>
                          _updateSaturationValue(details.localPosition, square),
                      onPanStart: (details) =>
                          _updateSaturationValue(details.localPosition, square),
                      onPanUpdate: (details) =>
                          _updateSaturationValue(details.localPosition, square),
                      child: SizedBox.fromSize(
                        size: square,
                        child: CustomPaint(
                          painter: _SaturationValuePainter(_hsv.hue),
                          foregroundPainter: _SelectionPainter(
                            Offset(
                              _hsv.saturation * square.width,
                              (1 - _hsv.value) * square.height,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTapDown: (details) => _updateHue(
                        details.localPosition,
                        Size(28, squareSize),
                      ),
                      onPanStart: (details) => _updateHue(
                        details.localPosition,
                        Size(28, squareSize),
                      ),
                      onPanUpdate: (details) => _updateHue(
                        details.localPosition,
                        Size(28, squareSize),
                      ),
                      child: SizedBox(
                        width: 28,
                        height: squareSize,
                        child: CustomPaint(
                          painter: const _HuePainter(),
                          foregroundPainter: _HueSelectionPainter(_hsv.hue),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('custom-theme-hex-field'),
                        controller: _hexController,
                        textCapitalization: TextCapitalization.characters,
                        keyboardType: TextInputType.text,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9a-fA-F]'),
                          ),
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: InputDecoration(
                          labelText: '色号',
                          prefixText: '#',
                          helperText: '输入 6 位色号可定位颜色',
                          errorText: _hexInvalid ? '请输入有效的 6 位色号' : null,
                        ),
                        onChanged: _updateFromHex,
                        onSubmitted: _updateFromHex,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, color),
          child: const Text('应用'),
        ),
      ],
    );
  }
}

class _SaturationValuePainter extends CustomPainter {
  const _SaturationValuePainter(this.hue);

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, HSVColor.fromAHSV(1, hue, 1, 1).toColor()],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SaturationValuePainter oldDelegate) =>
      oldDelegate.hue != hue;
}

class _HuePainter extends CustomPainter {
  const _HuePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.red,
            Colors.yellow,
            Colors.green,
            Colors.cyan,
            Colors.blue,
            Colors.purple,
            Colors.red,
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SelectionPainter extends CustomPainter {
  const _SelectionPainter(this.position);

  final Offset position;

  @override
  void paint(Canvas canvas, Size size) {
    final point = Offset(
      position.dx.clamp(0.0, size.width),
      position.dy.clamp(0.0, size.height),
    );
    canvas.drawCircle(point, 7, Paint()..color = Colors.white);
    canvas.drawCircle(
      point,
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.black,
    );
  }

  @override
  bool shouldRepaint(_SelectionPainter oldDelegate) =>
      oldDelegate.position != position;
}

class _HueSelectionPainter extends CustomPainter {
  const _HueSelectionPainter(this.hue);

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final y = (hue / 360 * size.height).clamp(1.0, size.height - 1);
    canvas.drawRect(
      Rect.fromLTWH(-2, y - 2, size.width + 4, 4),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_HueSelectionPainter oldDelegate) =>
      oldDelegate.hue != hue;
}
