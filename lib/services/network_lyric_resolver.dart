import '../page/playlist/playlist_models.dart';

const _priority = ['netease', 'qq', 'kugou'];

List<String> networkLyricSourceOrder(
  String selectedSource, {
  bool enableFallback = true,
}) {
  final selected = _priority.contains(selectedSource)
      ? selectedSource
      : _priority.first;
  return [
    selected,
    if (enableFallback) ..._priority.where((source) => source != selected),
  ];
}

/// Keep the first matched lyrics while looking for real word timestamps.
/// Synthetic display timing never qualifies a platform as a timed match.
Future<List<LyricLine>> resolveNetworkLyrics({
  required String selectedSource,
  required bool enableFallback,
  required bool enableTimedFallback,
  required Future<List<LyricLine>> Function(String source) fetch,
  bool Function()? isStillNeeded,
  void Function(List<LyricLine> lyrics)? onFallback,
  void Function(String source, Object error)? onError,
}) async {
  List<LyricLine> fallback = const [];
  for (final source in networkLyricSourceOrder(
    selectedSource,
    enableFallback: enableFallback || enableTimedFallback,
  )) {
    if (isStillNeeded?.call() == false) return const [];
    List<LyricLine> lyrics;
    try {
      lyrics = await fetch(source);
    } catch (error) {
      onError?.call(source, error);
      continue;
    }
    if (isStillNeeded?.call() == false) return const [];
    if (lyrics.isEmpty) continue;
    final timed = lyrics.any((line) => line.hasTimedWords);
    if (fallback.isEmpty) {
      fallback = lyrics;
      if (enableTimedFallback && !timed) onFallback?.call(lyrics);
    }
    if (!enableTimedFallback || timed) {
      return lyrics;
    }
  }
  return fallback;
}
