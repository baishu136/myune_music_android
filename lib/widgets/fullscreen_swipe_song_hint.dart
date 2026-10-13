import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../page/playlist/playlist_models.dart';

/// Match the lyric list's active row, excluding its blank/interlude sentinels.
bool hasHighlightedLyricLine({
  required List<LyricLine> lines,
  required int activeIndex,
  required Duration position,
}) {
  if (activeIndex < 0 || activeIndex >= lines.length) return false;
  final line = lines[activeIndex];
  return !line.isInterlude &&
      position >= line.timestamp &&
      line.texts.any((text) => text.trim().isNotEmpty);
}

/// Events deliberately notify even when a cached Song instance is reused.
class FullscreenSwipeSongHintController extends ChangeNotifier
    implements ValueListenable<Song?> {
  Song? _song;
  bool next = true;
  bool switching = false;

  @override
  Song? get value => _song;

  void beginSwitch({required bool next}) {
    this.next = next;
    switching = true;
    notifyListeners();
  }

  void show(Song song) {
    _song = song;
    switching = false;
    notifyListeners();
  }
}

/// A transient overlay independent of lyric geometry and playback frame ticks.
/// Only explicit, completed swipes publish events; mounting never replays one.
class FullscreenSwipeSongHint extends StatefulWidget {
  const FullscreenSwipeSongHint({
    super.key,
    required this.enabled,
    required this.currentSongIdentity,
    required this.songChanges,
    this.lyricHighlightChanges,
    this.readHighlightedSongIdentity,
  });

  static const holdDuration = Duration(milliseconds: 2200);
  static const fadeDuration = Duration(milliseconds: 140);
  final bool enabled;
  final Object currentSongIdentity;
  final FullscreenSwipeSongHintController songChanges;
  final Listenable? lyricHighlightChanges;
  final Object? Function()? readHighlightedSongIdentity;

  @override
  State<FullscreenSwipeSongHint> createState() =>
      _FullscreenSwipeSongHintState();
}

class _FullscreenSwipeSongHintState extends State<FullscreenSwipeSongHint>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _opacity = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: FullscreenSwipeSongHint.fadeDuration,
  );
  Timer? _timer;
  Song? _song;
  bool _foreground = true;
  int _revision = 0;
  double _translation = 20;
  double? _leaveStartX;
  double _leaveStartOpacity = 1;
  bool _checkingHighlight = false;
  bool _watchingHighlight = false;

  void _stopWatchingHighlight() {
    if (!_watchingHighlight) return;
    widget.lyricHighlightChanges?.removeListener(_queueHighlightCheck);
    _watchingHighlight = false;
  }

  void _queueHighlightCheck() {
    if (_checkingHighlight || _song == null) return;
    _checkingHighlight = true;
    // Lyric index may be published during a provider commit/build. Only the
    // isolated overlay changes, after the committed song/lyrics are available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkingHighlight = false;
      if (!mounted || !_watchingHighlight || !widget.enabled || !_foreground) {
        return;
      }
      final identity = _song?.normalizedPath;
      if (identity != null &&
          widget.currentSongIdentity == identity &&
          widget.readHighlightedSongIdentity?.call() == identity) {
        unawaited(_leave(64, FullscreenSwipeSongHint.fadeDuration));
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  double get _currentX {
    final start = _leaveStartX;
    if (start == null) return _translation * (1 - _opacity.value);
    final progress = _leaveStartOpacity > 0
        ? (1 - _opacity.value / _leaveStartOpacity).clamp(0.0, 1.0)
        : 1.0;
    return start + (_translation - start) * progress;
  }

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.songChanges.addListener(_show);
  }

  void _show() {
    if (widget.songChanges.switching) {
      if (widget.enabled && _song != null) {
        unawaited(
          _leave(
            widget.songChanges.next ? -20 : 20,
            const Duration(milliseconds: 110),
          ),
        );
      }
      return;
    }
    final song = widget.songChanges.value;
    if (!mounted || !widget.enabled || !_foreground || song == null) return;
    final revision = ++_revision;
    _timer?.cancel();
    setState(() {
      _song = song;
      _leaveStartX = null;
      _translation = widget.songChanges.next ? 20 : -20;
    });
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _opacity.value = 1;
    } else {
      _opacity.value = 0;
      _opacity.animateTo(1, curve: Curves.easeInOutCubic);
    }
    _timer = Timer(FullscreenSwipeSongHint.holdDuration, () {
      if (!mounted || revision != _revision) return;
      unawaited(_leave(64, FullscreenSwipeSongHint.fadeDuration));
    });
    _stopWatchingHighlight();
    _watchingHighlight = true;
    widget.lyricHighlightChanges?.addListener(_queueHighlightCheck);
    _queueHighlightCheck();
  }

  Future<void> _leave(double translation, Duration duration) async {
    _stopWatchingHighlight();
    final revision = ++_revision;
    _timer?.cancel();
    final startX = _currentX;
    setState(() {
      _leaveStartX = startX;
      _leaveStartOpacity = _opacity.value;
      _translation = translation;
    });
    if (MediaQuery.disableAnimationsOf(context)) {
      _opacity.value = 0;
    } else {
      try {
        await _opacity
            .animateTo(0, duration: duration, curve: Curves.easeInCubic)
            .orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (mounted && revision == _revision) setState(() => _song = null);
  }

  void _clear() {
    _stopWatchingHighlight();
    _revision++;
    _timer?.cancel();
    _opacity.stop();
    _opacity.value = 0;
    _song = null;
  }

  @override
  void didUpdateWidget(covariant FullscreenSwipeSongHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyricHighlightChanges != widget.lyricHighlightChanges &&
        _watchingHighlight) {
      oldWidget.lyricHighlightChanges?.removeListener(_queueHighlightCheck);
      widget.lyricHighlightChanges?.addListener(_queueHighlightCheck);
    }
    if (oldWidget.songChanges != widget.songChanges) {
      oldWidget.songChanges.removeListener(_show);
      widget.songChanges.addListener(_show);
      _clear();
    }
    if (_watchingHighlight) _queueHighlightCheck();
    if (!widget.enabled ||
        (oldWidget.currentSongIdentity != widget.currentSongIdentity &&
            _song?.normalizedPath != widget.currentSongIdentity)) {
      _clear();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && _song != null) setState(_clear);
  }

  @override
  void dispose() {
    _stopWatchingHighlight();
    widget.songChanges.removeListener(_show);
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _revision++;
    _opacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final song = _song;
    if (song == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _opacity,
        builder: (_, child) => Transform.translate(
          key: const ValueKey('fullscreen-swipe-song-hint-slide'),
          offset: Offset(_currentX, 0),
          child: FadeTransition(
            key: const ValueKey('fullscreen-swipe-song-hint-fade'),
            opacity: _opacity,
            child: child,
          ),
        ),
        child: RepaintBoundary(
          child: Semantics(
            liveRegion: true,
            child: Column(
              key: const ValueKey('fullscreen-swipe-song-hint'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  textScaler: TextScaler.noScaling,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 24,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  song.artist,
                  textScaler: TextScaler.noScaling,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 24,
                    height: 1.12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
