import '../page/playlist/playlist_models.dart';

enum PlayMode { sequence, shuffle, repeatOne, repeatShuffle }

enum SongTitleLanguage { other, english, japanese, chinese }

final _kana = RegExp(
  r'[\u3041-\u3096\u309d-\u309f\u30a1-\u30fa\u30fd-\u30ff\uff66-\uff9d]',
);
final _han = RegExp(r'[\u3400-\u9fff\u{20000}-\u{323af}]', unicode: true);
final _latin = RegExp(r'[a-zA-Z\u00c0-\u024f]');

SongTitleLanguage songTitleLanguage(String title) {
  if (_kana.hasMatch(title)) return SongTitleLanguage.japanese;
  if (_han.hasMatch(title)) return SongTitleLanguage.chinese;
  if (_latin.hasMatch(title)) return SongTitleLanguage.english;
  return SongTitleLanguage.other;
}

class PlaybackSkipRules {
  const PlaybackSkipRules({
    this.lowPlayCount = false,
    this.minimumPlayCount = 10,
    this.english = false,
    this.japanese = false,
    this.chinese = false,
  });

  final bool lowPlayCount, english, japanese, chinese;
  final int minimumPlayCount;

  bool allows(Song song, int playCount) {
    if (lowPlayCount && playCount < minimumPlayCount) return false;
    return switch (songTitleLanguage(song.title)) {
      SongTitleLanguage.english => !english,
      SongTitleLanguage.japanese => !japanese,
      SongTitleLanguage.chinese => !chinese,
      SongTitleLanguage.other => true,
    };
  }

  PlaybackSkipRules copyWith({
    bool? lowPlayCount,
    int? minimumPlayCount,
    bool? english,
    bool? japanese,
    bool? chinese,
  }) => PlaybackSkipRules(
    lowPlayCount: lowPlayCount ?? this.lowPlayCount,
    minimumPlayCount: minimumPlayCount ?? this.minimumPlayCount,
    english: english ?? this.english,
    japanese: japanese ?? this.japanese,
    chinese: chinese ?? this.chinese,
  );
}

/// The same bounded selection is used by manual controls and gapless lookahead.
int? nextPlaybackIndex({
  required int count,
  required int current,
  required PlayMode mode,
  required bool automatic,
  required bool Function(int index) allows,
  List<int>? shuffleOrder,
  bool previous = false,
  bool stopAfterQueue = false,
}) {
  if (count == 0) return null;
  final repeating =
      mode == PlayMode.repeatOne || mode == PlayMode.repeatShuffle;
  if (automatic && repeating) {
    return stopAfterQueue || current < 0 || current >= count ? null : current;
  }
  final shuffled = mode == PlayMode.shuffle || mode == PlayMode.repeatShuffle;
  final order = shuffled && shuffleOrder?.length == count
      ? shuffleOrder!
      : List<int>.generate(count, (i) => i);
  final position = order.indexOf(current);
  final step = previous ? -1 : 1;
  for (var n = 1; n <= count; n++) {
    final raw = position + n * step;
    if (automatic && stopAfterQueue && (raw < 0 || raw >= count)) return null;
    final candidate = order[raw % count];
    if (allows(candidate)) return candidate;
  }
  return null;
}
