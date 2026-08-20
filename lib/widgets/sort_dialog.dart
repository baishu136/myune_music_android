import 'package:flutter/material.dart';
import '../page/playlist/playlist_content_notifier.dart';

class SortDialog extends StatefulWidget {
  final bool isAlbumView; // 新增参数，标识是否在专辑视图中

  const SortDialog({super.key, this.isAlbumView = false});

  @override
  State<SortDialog> createState() => _SortDialogState();
}

class _SortDialogState extends State<SortDialog> {
  SortCriterion _selectedCriterion = SortCriterion.title;
  bool _isDescending = false;

  bool get _usesFixedOrder =>
      _selectedCriterion == SortCriterion.random ||
      _selectedCriterion == SortCriterion.playCount ||
      _selectedCriterion == SortCriterion.playTime;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('排序歌曲'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 排序标准单选按钮
            RadioGroup<SortCriterion>(
              groupValue: _selectedCriterion,
              onChanged: (value) => setState(() {
                _selectedCriterion = value ?? _selectedCriterion;
                if (_usesFixedOrder) _isDescending = false;
              }),
              child: Column(
                children: [
                  const RadioListTile<SortCriterion>(
                    title: Text('按歌曲名'),
                    value: SortCriterion.title,
                  ),
                  const RadioListTile<SortCriterion>(
                    title: Text('按文件名'),
                    value: SortCriterion.file,
                  ),
                  const RadioListTile<SortCriterion>(
                    title: Text('按歌手名'),
                    value: SortCriterion.artist,
                  ),
                  const RadioListTile<SortCriterion>(
                    title: Text('按修改日期'),
                    value: SortCriterion.dateModified,
                  ),
                  const RadioListTile<SortCriterion>(
                    title: Text('按播放次数排序'),
                    value: SortCriterion.playCount,
                  ),
                  const RadioListTile<SortCriterion>(
                    title: Text('按播放时间排序'),
                    value: SortCriterion.playTime,
                  ),
                  const RadioListTile<SortCriterion>(
                    title: Text('随机排序'),
                    value: SortCriterion.random,
                  ),
                  // 仅在专辑视图中显示音轨号排序选项
                  if (widget.isAlbumView)
                    const RadioListTile<SortCriterion>(
                      title: Text('按音轨号'),
                      value: SortCriterion.trackNumber,
                    ),
                ],
              ),
            ),
            const Divider(),
            // 倒序复选框
            CheckboxListTile(
              title: const Text('倒序排列'),
              value: _isDescending,
              onChanged: _usesFixedOrder
                  ? null // 随机排序与播放统计排序使用固定顺序
                  : (value) => setState(() => _isDescending = value!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            // 当用户点击"应用"时，关闭对话框并返回选择结果
            Navigator.of(context).pop({
              'criterion': _selectedCriterion,
              'descending': _isDescending,
            });
          },
          child: const Text('应用排序'),
        ),
      ],
    );
  }
}
