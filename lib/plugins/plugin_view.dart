import 'dart:convert';
import 'package:flutter/material.dart';
import 'plugin_package.dart';

/// Bounded host-rendered components. Plugins describe views; they never run
/// code on the Flutter frame clock or receive navigation/gesture objects.
class PluginView {
  PluginView(Object? value) : root = pluginMap(value) {
    var nodes = 0, textSize = 0;
    void check(Map<String, dynamic> node, int depth) {
      if (++nodes > 120 || depth > 8) throw const FormatException('界面过大');
      switch (node['type']) {
        case 'text':
          final text = node['text'];
          if (text is! String ||
              text.length > 2000 ||
              (textSize += text.length) > 16000) {
            throw const FormatException('文字过长');
          }
        case 'button':
          if (node['text'] is! String ||
              (node['text'] as String).length > 80 ||
              node['action'] is! String ||
              !RegExp(
                r'^[a-z][a-z0-9_-]{0,39}$',
              ).hasMatch(node['action'] as String) ||
              utf8.encode(jsonEncode(node['data'])).length > 4096) {
            throw const FormatException('按钮无效');
          }
        case 'column':
        case 'card':
        case 'row':
          final children = node['children'];
          if (children is! List ||
              children.length > (node['type'] == 'row' ? 4 : 60)) {
            throw const FormatException('容器无效');
          }
          for (final child in children) {
            check(pluginMap(child), depth + 1);
          }
        case 'space':
          final height = node['height'] ?? 8;
          if (height is! num || !height.isFinite || height < 0 || height > 32) {
            throw const FormatException('间距无效');
          }
        default:
          throw const FormatException('不支持的界面组件');
      }
    }

    check(root, 0);
  }
  final Map<String, dynamic> root;
  Widget build(BuildContext context, void Function(String, Object?)? onAction) {
    Widget render(Map<String, dynamic> node) {
      List<Widget> children() =>
          (node['children'] as List).map((e) => render(pluginMap(e))).toList();
      return switch (node['type']) {
        'text' => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            node['text'] as String,
            style: node['style'] == 'title'
                ? Theme.of(context).textTheme.titleLarge
                : node['style'] == 'muted'
                ? Theme.of(context).textTheme.bodySmall
                : Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        'button' => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: FilledButton.tonal(
            onPressed: onAction == null
                ? null
                : () => onAction(node['action'] as String, node['data']),
            child: Text(
              node['text'] as String,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        'space' => SizedBox(height: (node['height'] as num? ?? 8).toDouble()),
        'row' => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children().map((e) => Expanded(child: e)).toList(),
        ),
        'card' => Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: children(),
            ),
          ),
        ),
        _ => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: children(),
        ),
      };
    }

    return render(root);
  }
}
