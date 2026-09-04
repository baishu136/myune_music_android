import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';

void main() {
  test(
    'folder refresh only updates the playlist that owns the scanned root',
    () {
      final folderPlaylist = Playlist(
        id: 'folder',
        name: '文件夹歌单',
        isFolderBased: true,
        folderPaths: [r'F:\Music'],
        songFilePaths: [r'F:\Music\existing.mp3'],
      );
      final regularPlaylist = Playlist(
        id: 'regular',
        name: '自建歌单',
        songFilePaths: [r'F:\Music\existing.mp3'],
      );

      expect(
        folderPlaylistTracksImportedRoot(folderPlaylist, r'f:\music'),
        isTrue,
      );
      expect(
        folderPlaylistTracksImportedRoot(regularPlaylist, r'F:\Music'),
        isFalse,
      );
    },
  );
}
