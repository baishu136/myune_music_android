import 'package:flutter/material.dart';

/// The same four actions in library and playlist selection mode.
class SongSelectionActions extends StatelessWidget {
  const SongSelectionActions({
    super.key,
    required this.onSelectAll,
    required this.onDeselectAll,
    required this.onExit,
    required this.onVisibility,
    required this.restoreHidden,
  });
  final VoidCallback onSelectAll, onDeselectAll, onExit;
  final VoidCallback? onVisibility;
  final bool restoreHidden;

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
        tooltip: restoreHidden ? '取消隐藏' : '隐藏歌曲',
        icon: Icon(
          restoreHidden ? Icons.visibility : Icons.visibility_off_outlined,
        ),
        onPressed: onVisibility,
      ),
    ],
  );
}
