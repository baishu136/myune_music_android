import 'package:flutter/material.dart';

/// Shared selection actions with independent hide and restore commands.
class SongSelectionActions extends StatelessWidget {
  const SongSelectionActions({
    super.key,
    required this.onSelectAll,
    required this.onDeselectAll,
    required this.onExit,
    required this.onHide,
    required this.onRestore,
  });
  final VoidCallback onSelectAll, onDeselectAll, onExit;
  final VoidCallback? onHide, onRestore;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: '全选',
        icon: const Icon(Icons.select_all),
        onPressed: onSelectAll,
      ),
      IconButton(
        tooltip: '取消全选',
        icon: const Icon(Icons.deselect),
        onPressed: onDeselectAll,
      ),
      IconButton(
        tooltip: '取消多选',
        icon: const Icon(Icons.close),
        onPressed: onExit,
      ),
      IconButton(
        tooltip: '隐藏歌曲',
        icon: const Icon(Icons.visibility_off_outlined),
        onPressed: onHide,
      ),
      IconButton(
        tooltip: '取消隐藏',
        icon: const Icon(Icons.visibility),
        onPressed: onRestore,
      ),
    ],
  );
}
