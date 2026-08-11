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
      final width = boundary.size.width;
      final ratio = (1440 / width).clamp(1.0, 2.5);
      final image = await boundary.toImage(pixelRatio: ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
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
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: AspectRatio(
                    aspectRatio: targetAspect,
                    child: RepaintBoundary(
                      key: _captureKey,
                      child: ClipRect(
                        child: ColoredBox(
                          color: Colors.black,
                          child: InteractiveViewer(
                            transformationController: _controller,
                            minScale: 1,
                            maxScale: 6,
                            boundaryMargin: const EdgeInsets.all(600),
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox.expand(
                              child: Image.file(
                                File(widget.sourcePath),
                                // Keep the complete source visible when the editor
                                // first opens. The user can then zoom and position it
                                // deliberately instead of starting from a hidden crop.
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
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
}
