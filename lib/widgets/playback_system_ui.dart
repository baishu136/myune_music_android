import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

/// Native insets control also works when SDK36 enforces edge-to-edge.
class PlaybackSystemUi extends StatefulWidget {
  const PlaybackSystemUi({super.key, this.active = true, required this.child});
  final bool active;
  final Widget child;
  @override
  State<PlaybackSystemUi> createState() => _PlaybackSystemUiState();
}

class _PlaybackSystemUiState extends State<PlaybackSystemUi>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.myune.music/playback_ui');
  static int _owners = 0;
  bool _owns = false;
  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  void _update(bool enabled) {
    if (!_android) return;
    if (_owns != enabled) {
      _owners += enabled ? 1 : -1;
      _owns = enabled;
    }
    unawaited(_channel.invokeMethod<void>('setPlaybackActive', _owners > 0));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _update(widget.active);
  }

  @override
  void didUpdateWidget(covariant PlaybackSystemUi oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _update(widget.active);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _update(widget.active);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _update(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
