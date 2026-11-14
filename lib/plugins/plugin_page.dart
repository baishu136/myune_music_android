import 'package:flutter/material.dart';
import 'plugin_controller.dart';
import 'plugin_view.dart';

class PluginPage extends StatefulWidget {
  const PluginPage({
    super.key,
    required this.controller,
    required this.entry,
    this.menu,
  });
  final PluginController controller;
  final PluginEntry entry;
  final String? menu;
  @override
  State<PluginPage> createState() => _PluginPageState();
}

class _PluginPageState extends State<PluginPage> {
  PluginView? _view;
  String? _error;
  bool _busy = true;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _load(
      widget.menu == null ? 'ui.open' : 'menu.action',
      widget.menu == null ? null : {'id': widget.menu},
    );
  }

  Future<void> _load(String event, Object? data) async {
    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.controller.invoke(
        widget.entry,
        event,
        data: data,
      );
      if (!mounted || request != _request) return;
      final view = result is Map<String, dynamic> ? result['view'] : null;
      _view = PluginView(view);
    } catch (error) {
      if (mounted && request == _request) _error = error.toString();
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: Text(widget.entry.package.name)),
      body: !widget.entry.enabled
          ? const Center(child: Text('插件已停用'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null) ...[
                    Text(_error!),
                    TextButton(
                      onPressed: _busy ? null : () => _load('ui.open', null),
                      child: const Text('重试'),
                    ),
                  ],
                  if (_view != null)
                    _view!.build(
                      context,
                      _busy
                          ? null
                          : (action, data) => _load('ui.action', {
                              'id': action,
                              'value': data,
                            }),
                    ),
                ],
              ),
            ),
    ),
  );
}
