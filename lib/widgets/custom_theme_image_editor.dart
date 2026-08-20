import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

Future<Uint8List?> showCustomThemeImageEditor(
  BuildContext context, {
  required String sourcePath,
  required bool square,
  required String title,
}) {
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _CustomThemeImageEditorPage(
        sourcePath: sourcePath,
        square: square,
        title: title,
      ),
    ),
  );
}

class _CustomThemeImageEditorPage extends StatefulWidget {
  const _CustomThemeImageEditorPage({
    required this.sourcePath,
    required this.square,
    required this.title,
  });

  final String sourcePath;
  final bool square;
  final String title;

  @override
  State<_CustomThemeImageEditorPage> createState() =>
      _CustomThemeImageEditorPageState();
}

class _CustomThemeImageEditorPageState
    extends State<_CustomThemeImageEditorPage> {
  final GlobalKey _captureKey = GlobalKey();
  final TransformationController _controller = TransformationController();
  Rect? _cropRect;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _captureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final cropRect = _cropRect;
      if (cropRect == null || cropRect.isEmpty) return;
      final ratio = (1440 / cropRect.width).clamp(1.0, 3.0);
      final image = await boundary.toImage(pixelRatio: ratio);
      final source = Rect.fromLTWH(
        cropRect.left * ratio,
        cropRect.top * ratio,
        cropRect.width * ratio,
        cropRect.height * ratio,
      );
      final outputWidth = source.width.round();
      final outputHeight = source.height.round();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        image,
        source,
        Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final cropped = await recorder.endRecording().toImage(
        outputWidth,
        outputHeight,
      );
      final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      cropped.dispose();
      if (!mounted || data == null) return;
      Navigator.of(context).pop(data.buffer.asUint8List());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final targetAspect = widget.square ? 1.0 : media.width / media.height;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '重置位置',
            onPressed: () => _controller.value = Matrix4.identity(),
            icon: const Icon(Icons.restart_alt),
          ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('使用', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Text(
                '双指缩放图片，拖动调整显示区域',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final available = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  final cropRect = _inscribedCropRect(
                    available,
                    targetAspect,
                    const EdgeInsets.all(24),
                  );
                  _cropRect = cropRect;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      RepaintBoundary(
                        key: _captureKey,
                        child: ColoredBox(
                          color: Colors.black,
                          child: InteractiveViewer(
                            transformationController: _controller,
                            minScale: 1,
                            maxScale: 6,
                            boundaryMargin: const EdgeInsets.all(600),
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox.fromSize(
                              size: available,
                              child: Image.file(
                                File(widget.sourcePath),
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                          ),
                        ),
                      ),
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _CropOverlayPainter(cropRect: cropRect),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 10, 20, 22),
              child: Text(
                '画面外的部分不会保存；可随时在设置中重新导入或恢复默认。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Rect _inscribedCropRect(Size size, double aspect, EdgeInsets padding) {
    final width = (size.width - padding.horizontal).clamp(1.0, size.width);
    final height = (size.height - padding.vertical).clamp(1.0, size.height);
    var cropWidth = width;
    var cropHeight = cropWidth / aspect;
    if (cropHeight > height) {
      cropHeight = height;
      cropWidth = cropHeight * aspect;
    }
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: cropWidth,
      height: cropHeight,
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter({required this.cropRect});

  final Rect cropRect;

  @override
  void paint(Canvas canvas, Size size) {
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(cropRect);
    canvas.drawPath(mask, Paint()..color = const Color(0x996E6E6E));
    canvas.drawRect(
      cropRect,
      Paint()
        ..color = Colors.white.withValues(alpha: .88)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) =>
      oldDelegate.cropRect != cropRect;
}
