import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../playlist/playlist_content_notifier.dart';

class EqualizerSaveButton extends StatelessWidget {
  const EqualizerSaveButton({super.key, required this.notifier});
  final PlaylistContentNotifier notifier;
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: () => showDialog<void>(
      context: context,
      builder: (_) => _PresetNameDialog(notifier: notifier),
    ),
    icon: const Icon(Icons.save_outlined),
    label: const Text('保留均衡器参数'),
  );
}

class _PresetNameDialog extends StatefulWidget {
  const _PresetNameDialog({required this.notifier});
  final PlaylistContentNotifier notifier;
  @override
  State<_PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<_PresetNameDialog> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;
  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.notifier.saveEqualizerPreset(_name.text);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ArgumentError
              ? error.message.toString()
              : '无法保存，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('保留均衡器参数'),
    content: TextField(
      controller: _name,
      autofocus: true,
      maxLength: 40,
      enabled: !_busy,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _save(),
      decoration: InputDecoration(labelText: '预设名称', errorText: _error),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _busy ? null : _save, child: const Text('保存')),
    ],
  );
}

class EqualizerPresetManager extends StatelessWidget {
  const EqualizerPresetManager({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('均衡器参数')),
    body: Consumer<PlaylistContentNotifier>(
      builder: (context, notifier, _) {
        final presets = notifier.savedEqualizerPresets;
        if (presets.isEmpty) return const Center(child: Text('暂无保存的均衡器参数'));
        return ListView.builder(
          itemCount: presets.length,
          itemBuilder: (context, index) {
            final preset = presets[index];
            return ListTile(
              title: Text(preset.name),
              trailing: IconButton(
                tooltip: '移除预设',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('移除均衡器参数'),
                      content: Text(preset.name),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('移除'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    try {
                      await notifier.removeEqualizerPreset(preset.id!);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('无法移除，请重试')),
                        );
                      }
                    }
                  }
                },
              ),
            );
          },
        );
      },
    ),
  );
}
