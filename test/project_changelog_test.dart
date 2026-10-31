import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/setting/project_changelog.dart';
import 'package:myune_music/page/setting/project_changelog_page.dart';

void main() {
  test(
    'changelog covers the first Android release through the current build',
    () {
      expect(projectChangelogEntries.first.version, '1.0.0-android.441');
      expect(projectChangelogEntries.last.version, '0.9.2-android.1');
      expect(projectChangelogEntries.last.date, '2026-08-08');
      expect(projectReleaseCount, 21);
      expect(githubReleaseEffectiveChangeCounts, hasLength(21));
      expect(projectEffectiveChangeCount, 191);
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
        (entry) => entry.version == projectChangelog099Version,
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
      expect(projectChangelogSince099.first.version, '1.0.0-android.441');
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
          .firstWhere((entry) => entry.version == projectChangelog099Version)
          .allItems
          .length,
    );
  });

  test(
    'each actual GitHub release has exactly one entry in publication order',
    () {
      final catalog =
          jsonDecode(
                File(
                  'docs/github_release_catalog_20261031.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final published = (catalog['publishedBeforeThisRelease'] as List)
          .cast<Map<String, dynamic>>();
      final tags = [
        catalog['targetTag'],
        ...published.map((release) => release['tag']),
      ];
      expect(published, hasLength(20));
      expect(projectChangelogEntries.map((entry) => 'v${entry.version}'), tags);
      expect(tags.toSet(), hasLength(tags.length));
      expect(projectChangelogEntries.first.date, catalog['targetDate']);
      for (final release in published) {
        final entry = projectChangelogEntries.singleWhere(
          (entry) => 'v${entry.version}' == release['tag'],
        );
        expect(entry.date, release['date']);
      }
      expect(projectChangelogSince099, hasLength(6));
      expect(projectEffectiveChangeCount, projectChangeItemCount);
    },
  );

  test(
    'current release notes match final changes and do not revive withdrawn prototypes',
    () {
      final current = projectChangelogEntries.first;
      final notes = File(
        'docs/github_release_notes_android_441.md',
      ).readAsStringSync();
      for (final item in current.allItems) {
        expect(notes, contains('- $item'));
      }
      final text = current.allItems.join('\n');
      expect(text, contains('关闭后统一生效'));
      expect(text, contains('最大字号提高至60'));
      expect(text, contains('歌词同步校准'));
      expect(text, contains('蓝牙'));
      expect(text, isNot(contains('128种')));
      expect(text, isNot(contains('72%')));
      expect(
        projectChangelogEntries.any(
          (entry) => entry.version == '1.0.0-android.410',
        ),
        isFalse,
      );
      final patched325 = projectChangelogEntries.singleWhere(
        (entry) => entry.version == '0.9.9-android.325',
      );
      expect(patched325.date, '2026-09-22');
      expect(patched325.fixes.join(), contains('文件类型过滤器'));
      final previous = projectChangelogEntries.singleWhere(
        (entry) => entry.version == '1.0.0-android.412',
      );
      final oldNotes = File(
        'docs/github_release_notes_android_412.md',
      ).readAsStringSync();
      for (final item in previous.allItems) {
        expect(oldNotes, contains('- $item'));
      }
    },
  );

  test(
    'new release notes describe user experience without engineering logs',
    () {
      final current = projectChangelogEntries.first;
      final notes = File(
        'docs/github_release_notes_android_441.md',
      ).readAsStringSync();
      final headings = RegExp(
        r'^## (.+)$',
        multiLine: true,
      ).allMatches(notes).map((match) => match.group(1)).toList();
      expect(headings, ['新功能', '修复', '优化']);
      expect(
        RegExp(r'^- ', multiLine: true).allMatches(notes),
        hasLength(current.allItems.length),
      );
      for (final term in [
        'Shader',
        'Ticker',
        'JNI',
        'PCM',
        '缓存',
        '线程',
        '单测',
        '测试数量',
        '构建耗时',
        'SHA256',
        '重构',
      ]) {
        expect(notes, isNot(contains(term)), reason: term);
      }
    },
  );

  testWidgets(
    'latest updates render release cards without per-build headings',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ProjectChangelogPage()));
      await tester.pumpAndSettle();
      expect(find.text('1.0.0-android.441'), findsOneWidget);
      expect(find.text('1.0.0-android.440'), findsNothing);
      expect(find.text('1.0.0-android.411'), findsNothing);
      expect(find.text('1.0.0-android.410'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
