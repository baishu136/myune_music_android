import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/setting/project_changelog.dart';

void main() {
  test(
    'changelog covers the first Android release through the current build',
    () {
      expect(projectChangelogEntries.first.version, '1.0.0-android.360');
      expect(projectChangelogEntries.last.version, '0.9.2-android.1—3');
      expect(projectChangelogEntries.last.date, '2026-08-08');
      expect(projectReleaseCount, 16);
      expect(githubReleaseEffectiveChangeCounts, hasLength(16));
      expect(projectEffectiveChangeCount, 142);
      expect(projectChangeItemCount, greaterThan(0));
      expect(
        projectChangeItemCount,
        projectChangelogEntries.expand((entry) => entry.allItems).length,
      );
    },
  );

  test('every changelog record has a date and at least one item', () {
    for (final entry in projectChangelogEntries) {
      expect(entry.date, isNotEmpty, reason: entry.version);
      expect(entry.allItems, isNotEmpty, reason: entry.version);
      expect(entry.allItems.every((item) => item.trim().isNotEmpty), isTrue);
    }
  });

  test(
    '0.99 contains every post-129 change under the three allowed groups',
    () {
      final current = projectChangelogEntries.firstWhere(
        (entry) => entry.version == '0.99（0.9.9-android.244）',
      );
      expect(current.features, isNotEmpty);
      expect(current.fixes, isNotEmpty);
      expect(current.optimizations, isNotEmpty);
      expect(current.allItems.length, 46);
    },
  );

  test(
    'latest updates include every record from this release through 0.99',
    () {
      final boundary = projectChangelogEntries.indexWhere(
        (entry) => entry.version == projectChangelog099Version,
      );

      expect(boundary, greaterThanOrEqualTo(0));
      expect(projectChangelogSince099.first.version, '1.0.0-android.360');
      expect(projectChangelogSince099.last.version, projectChangelog099Version);
      expect(
        projectChangelogSince099,
        projectChangelogEntries.take(boundary + 1),
      );
      expect(
        projectChangelogSince099.any(
          (entry) => entry.version == '0.9.9-android.243',
        ),
        isFalse,
      );
    },
  );

  test('GitHub 0.99 notes use the same three groups and item count', () {
    final notes = File('docs/github_release_notes_0.99.md').readAsStringSync();
    final headings = RegExp(
      r'^## (.+)$',
      multiLine: true,
    ).allMatches(notes).map((match) => match.group(1)).toList();
    final bulletCount = RegExp(
      r'^- ',
      multiLine: true,
    ).allMatches(notes).length;
    expect(headings, ['新功能', '修复', '优化']);
    expect(
      bulletCount,
      projectChangelogEntries
          .firstWhere((entry) => entry.version == '0.99（0.9.9-android.244）')
          .allItems
          .length,
    );
  });
}
