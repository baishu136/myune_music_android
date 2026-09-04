import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('legacy grid preferences migrate to the indexed grid mode', () async {
    SharedPreferences.setMockInitialValues({
      'artistGroupGridView': true,
      'albumGroupGridView': false,
    });
    final settings = SettingsProvider();
    await settings.initializationFuture;

    expect(settings.artistGroupViewMode, GroupViewMode.indexedGrid);
    expect(settings.albumGroupViewMode, GroupViewMode.list);
  });

  test('indexed group modes persist independently', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.initializationFuture;

    await settings.setArtistGroupViewMode(GroupViewMode.indexedGrid);
    await settings.setAlbumGroupViewMode(GroupViewMode.list);

    final restored = SettingsProvider();
    await restored.initializationFuture;
    expect(restored.artistGroupViewMode, GroupViewMode.indexedGrid);
    expect(restored.albumGroupViewMode, GroupViewMode.list);
  });

  test('stored regular grid mode migrates to indexed grid', () async {
    SharedPreferences.setMockInitialValues({
      'artistGroupViewMode': 'grid',
      'albumGroupViewMode': 'grid',
    });
    final settings = SettingsProvider();
    await settings.initializationFuture;

    expect(settings.artistGroupViewMode, GroupViewMode.indexedGrid);
    expect(settings.albumGroupViewMode, GroupViewMode.indexedGrid);
  });

  test('library and playlist view modes persist independently', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.initializationFuture;

    expect(settings.libraryViewMode, LibraryViewMode.list);
    expect(settings.playlistViewMode, PlaylistViewMode.cards);

    await settings.setLibraryViewMode(LibraryViewMode.indexed);
    await settings.setPlaylistViewMode(PlaylistViewMode.split);

    final restored = SettingsProvider();
    await restored.initializationFuture;
    expect(restored.libraryViewMode, LibraryViewMode.indexed);
    expect(restored.playlistViewMode, PlaylistViewMode.split);
  });

  test('artist and album group sorting persist independently', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.initializationFuture;

    await settings.setArtistGroupSort(
      mode: GroupCollectionSortMode.playCount,
      descending: true,
    );
    await settings.setAlbumGroupSort(
      mode: GroupCollectionSortMode.songCount,
      descending: false,
    );

    final restored = SettingsProvider();
    await restored.initializationFuture;
    expect(restored.artistGroupSortMode, GroupCollectionSortMode.playCount);
    expect(restored.artistGroupSortDescending, isTrue);
    expect(restored.albumGroupSortMode, GroupCollectionSortMode.songCount);
    expect(restored.albumGroupSortDescending, isFalse);
  });
}
