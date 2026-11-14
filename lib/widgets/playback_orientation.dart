import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Startup remains portrait. Only mounted playback routes opt into rotation.
class PlaybackOrientationScope extends StatefulWidget {
  const PlaybackOrientationScope({super.key, required this.child});
  final Widget child;
  @override
  State<PlaybackOrientationScope> createState() =>
      _PlaybackOrientationScopeState();
}

class _PlaybackOrientationScopeState extends State<PlaybackOrientationScope> {
  static int _players = 0;
  late final bool _android =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  void initState() {
    super.initState();
    if (_android && _players++ == 0) {
      unawaited(
        SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]),
      );
    }
  }

  @override
  void dispose() {
    if (_android && --_players == 0) {
      unawaited(
        SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
        ]),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class PlaybackOrientationButton extends StatelessWidget {
  const PlaybackOrientationButton({super.key});
  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return IconButton(
      key: const ValueKey('playback-orientation-toggle'),
      tooltip: landscape ? '竖屏播放' : '横屏播放',
      icon: Icon(
        landscape ? Icons.stay_current_portrait : Icons.stay_current_landscape,
      ),
      onPressed: () => SystemChrome.setPreferredOrientations(
        landscape
            ? const [DeviceOrientation.portraitUp]
            : const [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ],
      ),
    );
  }
}
