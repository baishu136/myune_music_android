import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'plugin_controller.dart';
import 'plugin_package.dart';
import 'plugin_page.dart';

const pluginPermissionLabels = {
  'playback.read': '读取播放状态',
  'playback.control': '控制播放',
  'library.read': '查询曲库',
  'queue.write': '修改播放队列',
  'lyrics.provide': '提供歌词（优先于内置来源）',
  'ui.page': '显示插件页面',
  'ui.menu': '添加插件菜单',
  'storage': '保存插件数据',
  'network': '访问指定网络域名',
};

class PluginManagerPage extends StatefulWidget {
  const PluginManagerPage({super.key});
  @override
  State<PluginManagerPage> createState() => _PluginManagerPageState();
}

class _PluginManagerPageState extends State<PluginManagerPage> {
  bool _busy = false;
  Future<void> _work(Future<void> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _approve(PluginPackage package, String action) async {
    final replacing =
        action == '导入' &&
        context.read<PluginController>().entries.any(
          (e) => e.package.id == package.id,
        );
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('$action${package.name}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${package.id}\n${package.version}'),
                  if (replacing) const Text('替换会停用旧版本并清除其插件数据。'),
                  const SizedBox(height: 12),
                  for (final permission in package.permissions)
                    Text('• ${pluginPermissionLabels[permission]}'),
                  for (final domain in package.domains) Text(domain),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _import(String source) async {
    final package = PluginPackage.parse(source);
    if (!mounted || !await _approve(package, '导入')) return;
    if (!mounted) return;
    await context.read<PluginController>().install(package);
  }

  Future<void> _file() => _work(() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: false,
    );
    if (result == null) return;
    final selected = result.files.single;
    if (selected.size > pluginPackageByteLimit || selected.path == null) {
      throw const FormatException('插件包过大或无法读取');
    }
    final bytes = <int>[];
    await for (final chunk in File(
      selected.path!,
    ).openRead(0, pluginPackageByteLimit + 1)) {
      bytes.addAll(chunk);
      if (bytes.length > pluginPackageByteLimit) {
        throw const FormatException('插件包过大');
      }
    }
    await _import(utf8.decode(bytes));
  });
  Future<void> _diagnose(PluginController controller) => _work(() async {
    final result = await controller.diagnose();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(result['passed'] == true ? '接口检测通过' : '接口检测未通过'),
        content: Text(
          result['passed'] == true ? '脚本执行、超时中断、内存限额和异常后恢复正常。' : '请查看运行记录并重试。',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonEncode(result)));
            },
            child: const Text('复制结果'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  });
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PluginController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('插件'),
        actions: [
          IconButton(
            tooltip: '导入插件',
            onPressed: _busy ? null : _file,
            icon: const Icon(Icons.add),
          ),
          PopupMenuButton<String>(
            enabled: !_busy,
            onSelected: (value) {
              if (value == 'check') {
                _diagnose(controller);
              } else {
                _work(
                  () async => _import(
                    await rootBundle.loadString(
                      'assets/plugins/$value.myune-plugin',
                    ),
                  ),
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'demo-tools', child: Text('导入工具示例')),
              PopupMenuItem(value: 'demo-lyrics', child: Text('导入歌词示例')),
              PopupMenuItem(value: 'check', child: Text('检测接口')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (controller.entries.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Text('尚未安装插件')),
          for (final entry in controller.entries)
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text(entry.package.name),
                    subtitle: Text(
                      '${entry.package.version}${entry.lastError == null ? '' : '\n${entry.lastError}'}',
                    ),
                    value: entry.enabled,
                    onChanged: _busy
                        ? null
                        : (enabled) => _work(() async {
                            if (!enabled ||
                                await _approve(entry.package, '启用')) {
                              await controller.setEnabled(entry, enabled);
                            }
                          }),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (entry.package.features.contains('page'))
                        TextButton(
                          onPressed: entry.enabled && !_busy
                              ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => PluginPage(
                                      controller: controller,
                                      entry: entry,
                                    ),
                                  ),
                                )
                              : null,
                          child: const Text('打开'),
                        ),
                      for (final menu in entry.package.menus)
                        TextButton(
                          onPressed: entry.enabled && !_busy
                              ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => PluginPage(
                                      controller: controller,
                                      entry: entry,
                                      menu: menu.id,
                                    ),
                                  ),
                                )
                              : null,
                          child: Text(menu.title),
                        ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _work(() async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text('移除${entry.package.name}？'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('取消'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('移除'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await controller.remove(entry);
                                }
                              }),
                        child: const Text('移除'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (controller.logs.isNotEmpty)
            ExpansionTile(
              title: const Text('运行记录'),
              children: [
                for (final line in controller.logs.reversed)
                  ListTile(dense: true, title: Text(line)),
              ],
            ),
        ],
      ),
    );
  }
}
