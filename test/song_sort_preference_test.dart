import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';

void main() {
  test('song sort preference round-trips the selected rule', () {
    const preference = SongSortPreference(
      criterion: SortCriterion.artist,
      descending: true,
    );

    final restored = SongSortPreference.fromJson(preference.toJson());
    expect(restored, isNotNull);
    expect(restored!.criterion, SortCriterion.artist);
    expect(restored.descending, isTrue);
  });

  test('invalid song sort preference is ignored', () {
    expect(
      SongSortPreference.fromJson({
        'criterion': 'removed-sort-mode',
        'descending': false,
      }),
      isNull,
    );
  });

  test(
    'library membership only changes for added, removed, or duplicate paths',
    () {
      expect(
        libraryMembershipChanged(
          ['music/a.mp3', 'music/b.mp3'],
          {'music/b.mp3', 'music/a.mp3'},
        ),
        isFalse,
      );
      expect(
        libraryMembershipChanged(
          ['music/a.mp3'],
          {'music/a.mp3', 'music/b.mp3'},
        ),
        isTrue,
      );
      expect(
        libraryMembershipChanged(
          ['music/a.mp3', 'music/a.mp3'],
          {'music/a.mp3'},
        ),
        isTrue,
      );
    },
  );
}
