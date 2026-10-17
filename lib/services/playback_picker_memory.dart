enum PlaybackPickerPage { library, artist, album, search, playlists }

class PlaybackPickerMemory {
  const PlaybackPickerMemory({
    this.page = PlaybackPickerPage.library,
    this.playlistId,
    this.query = '',
    this.offset = 0,
  });
  final PlaybackPickerPage page;
  final String? playlistId;
  final String query;
  final double offset;

  factory PlaybackPickerMemory.fromJson(Map<String, dynamic> json) {
    final page =
        PlaybackPickerPage.values
            .where((p) => p.name == json['page'])
            .firstOrNull ??
        PlaybackPickerPage.library;
    final offset = json['offset'];
    return PlaybackPickerMemory(
      page: page,
      playlistId: json['playlistId'] is String
          ? json['playlistId'] as String
          : null,
      query: json['query'] is String ? json['query'] as String : '',
      offset: offset is num && offset.isFinite && offset >= 0
          ? offset.toDouble()
          : 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'page': page.name,
    'playlistId': playlistId,
    'query': query,
    'offset': offset,
  };
}
