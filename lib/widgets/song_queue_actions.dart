import 'package:flutter/material.dart';

class SongQueueActions extends StatefulWidget {
  const SongQueueActions({
    super.key,
    required this.onAdd,
    required this.onNext,
  });
  final Future<void> Function() onAdd, onNext;
  @override
  State<SongQueueActions> createState() => _SongQueueActionsState();
}

class _SongQueueActionsState extends State<SongQueueActions> {
  bool _busy = false;
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('无法更新播放队列，请重试')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: '加入播放队列',
        icon: const Icon(Icons.playlist_add),
        constraints: const BoxConstraints(minWidth: 44, minHeight: 48),
        onPressed: _busy ? null : () => _run(widget.onAdd),
      ),
      IconButton(
        tooltip: '下一首播放',
        icon: const Icon(Icons.playlist_play),
        constraints: const BoxConstraints(minWidth: 44, minHeight: 48),
        onPressed: _busy ? null : () => _run(widget.onNext),
      ),
    ],
  );
}
